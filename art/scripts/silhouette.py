"""把生成結果壓成純黑剪影並縮到 128px，檢查可讀性。

這是精緻度規格 §4 的第 ② 步。該步常被跳過，但它是最便宜的保險——
剪影不可讀的角色，上完色也不會可讀，而此時重畫的成本已經是十倍。

判準來自章節規格 §3.4：128px 下靠剪影辨識，不靠細節。
笠形盔的三角、鐵人的方塊、鏢手的長鏢斜線，這些必須在純黑剪影下仍看得出來。

另外輸出兩兩相似度，用來抓「兩個不同單位的剪影長得太像」——
規格 §3 的建議自動檢查之一。

    python art/scripts/silhouette.py                     # 全部
    python art/scripts/silhouette.py --cat unit          # 只看單位
    python art/scripts/silhouette.py --threshold 0.92    # 相似度告警門檻
"""

import argparse
import json
import os

from PIL import Image, ImageDraw

import _console

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MANIFEST = os.path.join(REPO, "art", "manifest", "chapter01_assets.json")
RAW = os.path.join(REPO, "art_src", "01_raw")
OUT = os.path.join(REPO, "art_src", "silhouette")
SIZE = 128


def to_silhouette(path: str) -> Image.Image:
    """背景為單一平色，故取四角顏色的中位當背景，與之差異夠大的即為前景。"""
    im = Image.open(path).convert("RGB")
    w, h = im.size
    corners = [im.getpixel(p) for p in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1))]
    bg = tuple(sorted(c[i] for c in corners)[len(corners) // 2] for i in range(3))

    mask = Image.new("L", (w, h), 0)
    px, mk = im.load(), mask.load()
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            if abs(r - bg[0]) + abs(g - bg[1]) + abs(b - bg[2]) > 60:
                mk[x, y] = 255

    # 等比縮到 SIZE 見方，保留留白，避免縮放改變剪影比例
    mask.thumbnail((SIZE, SIZE), Image.LANCZOS)
    out = Image.new("L", (SIZE, SIZE), 0)
    out.paste(mask, ((SIZE - mask.width) // 2, (SIZE - mask.height) // 2))
    return out.point(lambda v: 255 if v > 110 else 0)


def similarity(a: Image.Image, b: Image.Image) -> float:
    pa, pb = a.load(), b.load()
    same = sum(1 for y in range(SIZE) for x in range(SIZE) if (pa[x, y] > 0) == (pb[x, y] > 0))
    return same / (SIZE * SIZE)


def main() -> int:
    _console.fix()
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--cat", action="append")
    ap.add_argument("--threshold", type=float, default=0.93)
    args = ap.parse_args()

    with open(MANIFEST, encoding="utf-8") as f:
        assets = [a for a in json.load(f)["assets"] if not args.cat or a["cat"] in args.cat]

    os.makedirs(OUT, exist_ok=True)
    sils: list[tuple[str, Image.Image]] = []
    for a in assets:
        d = os.path.join(RAW, a["id"])
        if not os.path.isdir(d):
            continue
        for n in sorted(f for f in os.listdir(d) if f.endswith(".png")):
            sil = to_silhouette(os.path.join(d, n))
            sil.save(os.path.join(OUT, f"{a['id']}__{n}"))
            sils.append((a["id"], sil))

    if not sils:
        print("沒有可處理的圖")
        return 1

    cols = 10
    rows = (len(sils) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (SIZE + 4), rows * (SIZE + 18)), (232, 220, 198))
    d = ImageDraw.Draw(sheet)
    for i, (aid, sil) in enumerate(sils):
        x, y = (i % cols) * (SIZE + 4), (i // cols) * (SIZE + 18)
        sheet.paste(Image.new("RGB", (SIZE, SIZE), (255, 255, 255)), (x, y))
        sheet.paste(Image.new("RGB", (SIZE, SIZE), (26, 26, 26)), (x, y), sil)
        d.text((x + 2, y + SIZE + 3), aid[:20], fill=(58, 42, 34))
    p = os.path.join(OUT, "_sheet.png")
    sheet.save(p)
    print(f"{p}  ({len(sils)} 個剪影)")

    # 同陣營／同類的剪影過於相似即告警——128px 下玩家分不出來就是設計失敗
    warned = 0
    for i in range(len(sils)):
        for j in range(i + 1, len(sils)):
            if sils[i][0] == sils[j][0]:
                continue
            s = similarity(sils[i][1], sils[j][1])
            if s >= args.threshold:
                print(f"  相似度 {s:.3f}  {sils[i][0]} ↔ {sils[j][0]}")
                warned += 1
    print(f"超過門檻 {args.threshold} 的配對：{warned}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
