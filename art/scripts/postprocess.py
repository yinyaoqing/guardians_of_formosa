"""A4 後處理管線：把生成原圖轉成可進 game/assets/ 的貼圖。

精緻度規格 §3 定義的五步：

    ① 去背與裁切          ← 本檔已實作
    ② 色票量化            ← 本檔已實作
    ③ 描邊統一            ← 本檔已實作（見 outline()）
    ④ 縮放至 128 並檢查剪影 ← 本檔已實作（剪影檢查見 silhouette.py）
    ⑤ 打包 Sprite Atlas    ← 未實作

**③ 與 ④ 的順序與規格相反，這是刻意的。** 規格寫「③ 描邊 → ④ 縮放」，但描邊若在
縮放前加，1024px 上的 3px 縮到 128px 只剩 0.4px，粗細一致的保證就沒了——而「保證
粗細一致」正是這一步存在的理由。故本檔先縮放再描邊，讓線寬以**最終像素**為準。

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

# 色票的唯一來源是 data/art_palette.json，與 tests/test_art_palette.gd 共用。
# **不要在這裡另外寫死一份**——量化器與測試各自持有色票的話兩邊會漂開：
# 量化器放行的顏色測試擋掉，或反之。
PALETTE_JSON = os.path.join(REPO, "data", "art_palette.json")


def _hex(v: str) -> tuple[int, int, int]:
    v = v.lstrip("#")
    return int(v[0:2], 16), int(v[2:4], 16), int(v[4:6], 16)


with open(PALETTE_JSON, encoding="utf-8") as _f:
    _P = json.load(_f)
PALETTE = {k: _hex(v) for k, v in _P["palette"].items()}
SKIN = [_hex(v) for v in _P["skin"].values()]
# 描邊色：art-direction-bible §1.1 要彩色描邊（焦茶／深赭／墨綠），不是粗黑均勻描邊
# ——那是明列要與 Kingdom Rush 區隔的第一項。故依局部色相在三色間選。
OUTLINE_COLORS = [_hex(v) for v in _P["outline"].values()]

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



def outline(im: Image.Image, width: int = 2) -> Image.Image:
    """沿外輪廓加一圈描邊，顏色取自相鄰像素的暗化色並吸附到描邊三色。

    只加**外輪廓**。§1.1 要的「粗細有變化、帶手繪抖動」指的是角色內部的線描，
    那是生成模型畫的，本函式不動；§3 要統一的是外緣——讓所有資產在任何背景上
    讀起來是同一套。兩者不衝突。
    """
    im = im.convert("RGBA")
    w, h = im.size
    src = im.load()
    out = im.copy()
    dst = out.load()

    opaque = [[src[x, y][3] > 128 for x in range(w)] for y in range(h)]
    for y in range(h):
        for x in range(w):
            if opaque[y][x]:
                continue
            # 找出 width 範圍內最近的不透明像素
            best = None
            for dy in range(-width, width + 1):
                for dx in range(-width, width + 1):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and opaque[ny][nx]:
                        d = dx * dx + dy * dy
                        if best is None or d < best[0]:
                            best = (d, src[nx, ny])
            if best is None or best[0] > width * width:
                continue
            r, g, b = best[1][:3]
            # 暗化後吸附到描邊三色，讓描邊隨局部色相走而不是一律焦茶
            dr, dg, db = r * 0.45, g * 0.45, b * 0.45
            c = min(OUTLINE_COLORS,
                    key=lambda o: (o[0] - dr) ** 2 + (o[1] - dg) ** 2 + (o[2] - db) ** 2)
            dst[x, y] = (*c, 255)
    return out


def fit(im: Image.Image, size: int) -> Image.Image:
    """等比縮到 size 見方並置中，保留透明留白，不變形。"""
    im = im.copy()
    im.thumbnail((size, size), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(im, ((size - im.width) // 2, (size - im.height) // 2))
    return canvas


def verify(paths: list[str]) -> int:
    """掃描產出，回報色票外的色相。精緻度規格 §3「建議的自動檢查」第一項。

    做完量化與描邊還不夠——**沒有東西在驗證它們真的生效**。規格 §3 說得很直白：
    在 AI 協作下，只有能自動驗證與自動執行的東西才不會腐化。這支檢查就是那個閘門。
    """
    allowed = set(PALETTE.values()) | set(SKIN) | set(OUTLINE_COLORS)
    bad_total = 0
    for path in paths:
        im = Image.open(path).convert("RGBA")
        offenders: dict[tuple[int, int, int], int] = {}
        px = im.load()
        for y in range(im.height):
          for x in range(im.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            if (r, g, b) not in allowed:
                offenders[(r, g, b)] = offenders.get((r, g, b), 0) + 1
        if offenders:
            top = sorted(offenders.items(), key=lambda kv: -kv[1])[:3]
            shown = ", ".join(f"#{r:02X}{g:02X}{b:02X}×{n}" for (r, g, b), n in top)
            print(f"  色票外 {sum(offenders.values()):>7} px  {os.path.basename(path):<28} {shown}")
            bad_total += 1
    if bad_total:
        print()
        print(f"=== 色票檢查失敗：{bad_total} 個檔案含色票外的色相")
    else:
        print()
        print(f"=== 色票檢查通過：{len(paths)} 個檔案全部落在色票內")
    return bad_total


def main() -> int:
    _console.fix()
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--stage", default="flux2", help="讀 stage_<stage>/；空字串表示資產目錄本身")
    ap.add_argument("--only", action="append")
    ap.add_argument("--cat", action="append")
    ap.add_argument("--tol", type=int, default=46, help="去背的顏色容差")
    ap.add_argument("--no-quantize", action="store_true", help="跳過色票量化")
    ap.add_argument("--keep-full", action="store_true", help="同時輸出未縮放的去背原圖")
    ap.add_argument("--no-outline", action="store_true", help="跳過統一描邊")
    ap.add_argument("--outline-width", type=int, default=2, help="描邊寬度（最終像素）")
    ap.add_argument("--verify-only", action="store_true", help="不重跑，只檢查現有產出的色票")
    args = ap.parse_args()

    with open(MANIFEST, encoding="utf-8") as f:
        assets = json.load(f)["assets"]
    if args.only:
        assets = [a for a in assets if a["id"] in args.only]
    if args.cat:
        assets = [a for a in assets if a["cat"] in args.cat]

    if args.verify_only:
        paths = [os.path.join(OUT, f"{a['id']}.png") for a in assets
                 if os.path.exists(os.path.join(OUT, f"{a['id']}.png"))]
        return 1 if verify(paths) else 0

    os.makedirs(OUT, exist_ok=True)
    written: list[str] = []
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
        if args.keep_full:
            im.save(os.path.join(OUT, f"{a['id']}_full.png"))
        # **必須先縮放再量化。** 反過來的話 LANCZOS 會把量化好的顏色重新插值出
        # 中間色，每通道差 1–2，量化等於白做——這是加了色票檢查才發現的。
        # 順帶好處：量化在 128px 上跑，比在 1024px 上快一個數量級。
        out = fit(im, SIZE_BY_CAT.get(a["cat"], 128))
        if not args.no_quantize:
            out = quantize(out)
        # 場景是滿版貼片，沒有外輪廓可描。
        if not args.no_outline and a["cat"] != "scene":
            out = outline(out, args.outline_width)
        dest = os.path.join(OUT, f"{a['id']}.png")
        out.save(dest)
        written.append(dest)
        opaque = sum(1 for p in out.getdata() if p[3] > 0)
        print(f"  {a['id']:<22} {out.width}x{out.height}  前景佔比 {opaque / (out.width * out.height):.0%}")
        done += 1

    print(f"\n=== 完成 {done}，跳過 {skipped}（無產出）→ {os.path.relpath(OUT, REPO)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
