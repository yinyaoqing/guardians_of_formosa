"""A4 後處理管線：把生成原圖轉成可進 game/assets/ 的貼圖。

精緻度規格 §3 定義的五步：

    ① 去背與裁切          ← 本檔已實作
    ② 色票量化            ← 本檔已實作
    ③ 描邊統一            ← 未實作
    ④ 縮放至 128 並檢查剪影 ← 本檔已實作（剪影檢查見 silhouette.py）
    ⑤ 打包 Sprite Atlas    ← 未實作

**為什麼這條管線必須是腳本而不是手工**（精緻度規格 §3）：色票量化把不同批次的色偏
強制拉齊、描邊由程式統一加上——這正是 AI 畫不穩的兩件事，交給程式即可根除。
在 AI 協作下，只有能自動驗證與自動執行的東西才不會腐化。

去背方法：本專案的生成圖背景是單一平色，故從四邊做泛洪填充，只吃與邊緣色相近的
連通區域。**不能用「整張圖比對背景色」**——那會把單位身上同色的部分一起挖掉
（例如灰袍、灰甲）。泛洪只吃與畫布邊緣連通的像素，內部同色區塊會保留。

    python art/scripts/postprocess.py --stage flux2
    python art/scripts/postprocess.py --stage flux2 --only enemy_ironman --no-quantize
"""

import argparse
import json
import os
from collections import deque

from PIL import Image

import _console

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MANIFEST = os.path.join(REPO, "art", "manifest", "chapter01_assets.json")
RAW = os.path.join(REPO, "art_src", "01_raw")
OUT = os.path.join(REPO, "art_src", "03_processed")

# art-direction-bible §2.1 的限定色域。量化即映射到這組色。
PALETTE = {
    "紅瓦赭": (0xB5, 0x44, 0x2E), "深赭": (0x8C, 0x3A, 0x22),
    "榕蔭綠": (0x2F, 0x5B, 0x3A), "墨綠": (0x1E, 0x40, 0x29),
    "翠綠": (0x5C, 0x8A, 0x4A), "沙洲黃": (0xC9, 0xA9, 0x6B),
    "曝曬沙": (0xD9, 0xC0, 0x8E), "蚵殼灰": (0xE8, 0xDC, 0xC6),
    "台江靛": (0x2C, 0x54, 0x70), "潮水青": (0x3E, 0x7A, 0x94),
    "藤黃": (0xE0, 0xA9, 0x3B), "硃砂": (0xA8, 0x33, 0x2B),
    "焦茶": (0x3A, 0x2A, 0x22), "鐵灰": (0x5A, 0x5A, 0x5E),
    "鹿皮褐": (0xA8, 0x75, 0x45),
}
# 膚色四階，art-direction-bible §2.1「唯一的例外：膚色」。四階的分野同時承擔
# 章節規格 §2.5 與 §3.3 的敘事要求——城內 547 名奴隸不是背景，把 VOC 畫成
# 純歐洲人前哨是美化殖民地。
SKIN = [
    (0xF2, 0xD6, 0xB8),  # 淺膚：VOC 歐洲人
    (0xD9, 0xA9, 0x7E),  # 中膚：漢人、鄭軍
    (0xA8, 0x75, 0x45),  # 深膚：西拉雅（與鹿皮褐同值）
    (0x6B, 0x47, 0x2E),  # 極深膚：VOC 奴工
]

SIZE_BY_CAT = {"unit": 128, "building": 192, "prop": 128, "vessel": 192, "scene": 512, "icon": 64}


def remove_background(im: Image.Image, tol: int = 46) -> Image.Image:
    """從四邊泛洪填充，把與邊緣色相近且連通的像素設為透明。"""
    im = im.convert("RGBA")
    w, h = im.size
    px = im.load()
    corners = [px[0, 0][:3], px[w - 1, 0][:3], px[0, h - 1][:3], px[w - 1, h - 1][:3]]
    bg = tuple(sorted(c[i] for c in corners)[len(corners) // 2] for i in range(3))

    seen = bytearray(w * h)
    q: deque[tuple[int, int]] = deque()
    for x in range(w):
        q.append((x, 0)); q.append((x, h - 1))
    for y in range(h):
        q.append((0, y)); q.append((w - 1, y))

    while q:
        x, y = q.popleft()
        i = y * w + x
        if seen[i]:
            continue
        r, g, b, _ = px[x, y]
        if abs(r - bg[0]) + abs(g - bg[1]) + abs(b - bg[2]) > tol:
            continue
        seen[i] = 1
        px[x, y] = (r, g, b, 0)
        if x > 0: q.append((x - 1, y))
        if x < w - 1: q.append((x + 1, y))
        if y > 0: q.append((x, y - 1))
        if y < h - 1: q.append((x, y + 1))
    return im


def trim(im: Image.Image, pad: int = 2) -> Image.Image:
    box = im.getbbox()
    if box is None:
        return im
    l, t, r, b = box
    w, h = im.size
    return im.crop((max(0, l - pad), max(0, t - pad), min(w, r + pad), min(h, b + pad)))


def quantize(im: Image.Image) -> Image.Image:
    """把每個像素映射到最近的色票色。透明像素不動。"""
    targets = list(PALETTE.values()) + SKIN
    im = im.convert("RGBA")
    px = im.load()
    cache: dict[tuple[int, int, int], tuple[int, int, int]] = {}
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            key = (r >> 2, g >> 2, b >> 2)  # 量化快取，避免逐像素跑 19 次距離
            hit = cache.get(key)
            if hit is None:
                hit = min(targets, key=lambda c: (c[0] - r) ** 2 + (c[1] - g) ** 2 + (c[2] - b) ** 2)
                cache[key] = hit
            px[x, y] = (*hit, a)
    return im


def fit(im: Image.Image, size: int) -> Image.Image:
    """等比縮到 size 見方並置中，保留透明留白，不變形。"""
    im = im.copy()
    im.thumbnail((size, size), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(im, ((size - im.width) // 2, (size - im.height) // 2))
    return canvas


def main() -> int:
    _console.fix()
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--stage", default="flux2", help="讀 stage_<stage>/；空字串表示資產目錄本身")
    ap.add_argument("--only", action="append")
    ap.add_argument("--cat", action="append")
    ap.add_argument("--tol", type=int, default=46, help="去背的顏色容差")
    ap.add_argument("--no-quantize", action="store_true", help="跳過色票量化")
    ap.add_argument("--keep-full", action="store_true", help="同時輸出未縮放的去背原圖")
    args = ap.parse_args()

    with open(MANIFEST, encoding="utf-8") as f:
        assets = json.load(f)["assets"]
    if args.only:
        assets = [a for a in assets if a["id"] in args.only]
    if args.cat:
        assets = [a for a in assets if a["cat"] in args.cat]

    os.makedirs(OUT, exist_ok=True)
    done = skipped = 0
    for a in assets:
        d = os.path.join(RAW, a["id"], f"stage_{args.stage}") if args.stage else os.path.join(RAW, a["id"])
        if not os.path.isdir(d):
            skipped += 1
            continue
        files = sorted(f for f in os.listdir(d) if f.lower().endswith(".png"))
        if not files:
            skipped += 1
            continue
        src = Image.open(os.path.join(d, files[0]))
        # 場景是滿版地形，沒有「背景」可去——對它泛洪會把邊角吃掉。
        if a["cat"] == "scene":
            im = src.convert("RGBA")
        else:
            im = trim(remove_background(src, args.tol))
        if not args.no_quantize:
            im = quantize(im)
        if args.keep_full:
            im.save(os.path.join(OUT, f"{a['id']}_full.png"))
        out = fit(im, SIZE_BY_CAT.get(a["cat"], 128))
        out.save(os.path.join(OUT, f"{a['id']}.png"))
        opaque = sum(1 for p in out.getdata() if p[3] > 0)
        print(f"  {a['id']:<22} {out.width}x{out.height}  前景佔比 {opaque / (out.width * out.height):.0%}")
        done += 1

    print(f"\n=== 完成 {done}，跳過 {skipped}（無產出）→ {os.path.relpath(OUT, REPO)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
