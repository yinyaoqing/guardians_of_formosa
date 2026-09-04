"""把 art_src/01_raw/ 底下的生成結果拼成接觸印樣，供人工挑選。

美術聖經 §2 的對策是「大量生成 → 嚴格篩選（10 選 1）」，而篩選的前提是
能一次看到整批。單張逐一開檔看不出風格漂移——漂移只在並排時才顯現。

    python art/scripts/contact_sheet.py                    # 全部，一張總表
    python art/scripts/contact_sheet.py --cat unit         # 只看單位
    python art/scripts/contact_sheet.py --per-asset        # 每個資產各一張
"""

import argparse
import json
import os

from PIL import Image, ImageDraw

import _console

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MANIFEST = os.path.join(REPO, "art", "manifest", "chapter01_assets.json")
RAW = os.path.join(REPO, "art_src", "01_raw")
OUT = os.path.join(REPO, "art_src", "contact")

CELL = 260
PAD = 6
LABEL_H = 18
BG = (232, 220, 198)  # 蚵殼灰，避免白底讓淺色資產看不出邊界
FG = (58, 42, 34)  # 焦茶


def cells_for(asset_ids: list[str]) -> list[tuple[str, str]]:
    out = []
    for aid in asset_ids:
        d = os.path.join(RAW, aid)
        if not os.path.isdir(d):
            continue
        for n in sorted(os.listdir(d)):
            if n.lower().endswith(".png"):
                out.append((aid, os.path.join(d, n)))
    return out


def build(cells: list[tuple[str, str]], cols: int, path: str) -> None:
    if not cells:
        print("沒有可用的圖")
        return
    rows = (len(cells) + cols - 1) // cols
    cw, ch = CELL + PAD * 2, CELL + PAD * 2 + LABEL_H
    sheet = Image.new("RGB", (cols * cw, rows * ch), BG)
    draw = ImageDraw.Draw(sheet)

    for i, (aid, p) in enumerate(cells):
        x, y = (i % cols) * cw, (i // cols) * ch
        im = Image.open(p).convert("RGB")
        im.thumbnail((CELL, CELL))
        sheet.paste(im, (x + PAD + (CELL - im.width) // 2, y + PAD + (CELL - im.height) // 2))
        draw.text((x + PAD, y + PAD * 2 + CELL), aid[:34], fill=FG)

    os.makedirs(os.path.dirname(path), exist_ok=True)
    sheet.save(path)
    print(f"{path}  ({sheet.width}x{sheet.height}, {len(cells)} 格)")


def main() -> int:
    _console.fix()
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--cat", action="append", help="只收這些分類")
    ap.add_argument("--cols", type=int, default=8)
    ap.add_argument("--per-asset", action="store_true", help="每個資產各輸出一張")
    args = ap.parse_args()

    with open(MANIFEST, encoding="utf-8") as f:
        assets = json.load(f)["assets"]
    if args.cat:
        assets = [a for a in assets if a["cat"] in args.cat]

    if args.per_asset:
        for a in assets:
            build(cells_for([a["id"]]), args.cols, os.path.join(OUT, f"{a['id']}.png"))
        return 0

    name = "all" if not args.cat else "-".join(sorted(args.cat))
    build(cells_for([a["id"] for a in assets]), args.cols, os.path.join(OUT, f"contact_{name}.png"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
