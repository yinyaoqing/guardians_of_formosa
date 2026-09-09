"""以色票程序化畫一組 32px 地面磚，供 TileMap 可讀性實驗（game/fx/pixel_demo.gd）。

為什麼不用 AI 畫地磚：無縫磚是擴散模型最弱的項目之一，而平色地面本來就不需要它——
地面只要「顏色對、對比夠、有一點不重複的碎點」，這三件事程式做比模型穩。

圖集配置（每格 32×32）：
    列 0  草地（榕蔭綠底 + 翠綠／墨綠碎點）×4 變體
    列 1  沙洲路徑（沙洲黃平色，素沙）×4 變體
    列 2  水（台江靛底 + 潮水青波紋）×2 變體
另輸出一張接觸陰影橢圓（精緻度規格 L1）。

    python art/scripts/make_tiles.py                              # 正式：game/assets/chapter01/
    python art/scripts/make_tiles.py --out art_src/03_processed_px  # 實驗（pixel_demo）
"""

import json
import os
import random

from PIL import Image, ImageDraw

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(REPO, "game", "assets", "chapter01")
TILE = 32


def _hex(v: str) -> tuple[int, int, int, int]:
    v = v.lstrip("#")
    return int(v[0:2], 16), int(v[2:4], 16), int(v[4:6], 16), 255


# 色票鍵名是中文（美術聖經 §2.1 的名稱），這裡用英文別名對到 hex，並確認 hex 真的在色票內
with open(os.path.join(REPO, "data", "art_palette.json"), encoding="utf-8") as f:
    _ALLOWED = set(json.load(f)["palette"].values())
_ALIAS = {
    "banyan_green": "#2F5B3A", "ink_green": "#1E4029", "jade": "#5C8A4A",
    "sand": "#C9A96B", "sun_sand": "#D9C08E", "indigo": "#2C5470", "tidal_teal": "#3E7A94",
}
_missing = [v for v in _ALIAS.values() if v not in _ALLOWED]
assert not _missing, f"不在色票內：{_missing}"
P = {k: _hex(v) for k, v in _ALIAS.items()}


def grass(rng: random.Random) -> Image.Image:
    # 地面用受光的翠綠，樹冠用榕蔭綠——深樹冠落在亮地面上才讀得出來（參考圖同理）
    im = Image.new("RGBA", (TILE, TILE), P["jade"])
    d = ImageDraw.Draw(im)
    for _ in range(rng.randint(5, 9)):
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        d.point((x, y), P["banyan_green"])
        if rng.random() < 0.5:
            d.point((x + 1, y), P["banyan_green"])
    for _ in range(rng.randint(1, 3)):
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        d.point((x, y), P["sun_sand"])
    return im


def path(rng: random.Random) -> Image.Image:
    # 素沙（2026-09-09 決定）：沙洲黃平色，只撒極少量曝曬沙碎點打破重複感。
    # 路徑靠「沙洲黃 vs 翠綠」的色對比讀，不靠紋理——扁平幾何風格下紋理反而突兀。
    im = Image.new("RGBA", (TILE, TILE), P["sand"])
    d = ImageDraw.Draw(im)
    for _ in range(rng.randint(1, 3)):
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        d.point((x, y), P["sun_sand"])
    return im


def water(rng: random.Random) -> Image.Image:
    im = Image.new("RGBA", (TILE, TILE), P["indigo"])
    d = ImageDraw.Draw(im)
    for _ in range(rng.randint(3, 5)):
        x, y = rng.randrange(TILE - 8), rng.randrange(TILE)
        d.line((x, y, x + rng.randint(4, 8), y), P["tidal_teal"])
    return im


def shadow_ellipse() -> Image.Image:
    im = Image.new("RGBA", (24, 10), (0, 0, 0, 0))
    ImageDraw.Draw(im).ellipse((0, 0, 23, 9), fill=(58, 42, 34, 110))  # 焦茶 #3A2A22 + alpha，色票測試看 RGB
    return im


def main() -> int:
    import argparse
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", default=OUT_DIR, help="輸出目錄（預設 game/assets/chapter01；實驗用 art_src/03_processed_px）")
    args = ap.parse_args()
    out_dir = args.out
    os.makedirs(out_dir, exist_ok=True)
    rng = random.Random(1661)
    rows = [[grass(rng) for _ in range(4)], [path(rng) for _ in range(4)], [water(rng) for _ in range(2)]]
    atlas = Image.new("RGBA", (TILE * 4, TILE * 3), (0, 0, 0, 0))
    for r, tiles in enumerate(rows):
        for c, t in enumerate(tiles):
            atlas.paste(t, (c * TILE, r * TILE))
    atlas.save(os.path.join(out_dir, "tiles.png"))
    shadow_ellipse().save(os.path.join(out_dir, "shadow_ellipse.png"))
    print(f"→ {os.path.relpath(out_dir, REPO)}/tiles.png ({atlas.width}x{atlas.height}), shadow_ellipse.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
