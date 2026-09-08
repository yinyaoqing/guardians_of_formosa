"""行走循環實驗的素材打包：AI 幀 → 對齊的 128／48px 幀；皮影母本 → 軀幹 + 兩腿分件。

    python art/scripts/walk_pack.py

輸出到 art_src/04_walk/，供 game/fx/walk_demo.gd 讀取。

AI 幀**不做 trim**：每幀單獨裁切會讓腳的位置在幀間跳動，必須以整張畫布等比縮放，
幀間對齊靠「母本與各幀同畫布、同構圖」這個前提（walk_frames.py 的 prompt 要求同框同大小）。

拆件用固定的水平切線（由人看母本決定，見 HEM／LEG_TOP／HIP）：
  軀幹 = 切線以上（含衣襬，蓋住腿的接縫）
  腿   = 切線以下，以 alpha 連通區分成後腿／前腿（母本是跨步姿勢，兩腿在衣襬下方分開）
髖關節 pivot 放在腿頂中央往上、衣襬之內，旋轉時接縫被衣襬遮住。
"""

import argparse
import json
import os
import shutil

from PIL import Image

import postprocess as pp

REPO = pp.REPO
RAW = os.path.join(REPO, "art_src", "01_raw")
OUT = os.path.join(REPO, "art_src", "04_walk")
# 預設母本：皮影銃卒 xp_shadow_musketeer_flux2_00002_（688×907 去背後）。切線單位是母本像素。
# 換母本時用 --src/--hem/--leg-top/--hip 覆蓋；兩腿在衣襬下方相連（3/4 視角）時再給 --split-x。
PUPPET_SRC = os.path.join(OUT, "xp_shadow_musketeer_full.png")
HEM = 720       # 軀幹保留到這裡（含衣襬）
LEG_TOP = 690   # 腿從這裡開始（與衣襬重疊 30px，藏接縫）
HIP = 645       # 髖關節 y


def pack_frames(name: str, size: int, outline_w: int, tag: str) -> int:
    src = os.path.join(RAW, f"xp_walk_{name}", "stage_edit")
    if not os.path.isdir(src):
        return 0
    n = 0
    for i in range(1, 5):
        f = os.path.join(src, f"frame_{i}.png")
        if not os.path.exists(f):
            continue
        # 扁平幾何的淺膚（#F2D6B8）與灰底相距只有 ~48，預設容差 46 會把臉和腳一起泛洪掉；收緊到 28
        im = pp.remove_background(Image.open(f), 28)
        im = _drop_specks(im, 400)
        k = size / im.height
        im = im.resize((max(1, round(im.width * k)), size), Image.LANCZOS)
        im = pp.quantize(im)
        im = pp.outline(im, outline_w)
        im.save(os.path.join(OUT, f"{tag}_{i}.png"))
        n += 1
    return n


def _drop_specks(im: Image.Image, min_px: int) -> Image.Image:
    """去掉泛洪沒吃到的背景雜點：Klein 編輯輸出的灰底有細微噪聲，孤島會被描邊成紅點。"""
    mask = im.split()[3].point(lambda a: 255 if a > 0 else 0)
    keep = Image.new("L", im.size, 0)
    kp = keep.load()
    for comp in _components(mask):
        if len(comp) < min_px:
            continue
        for x, y in comp:
            kp[x, y] = 255
    return Image.composite(im, Image.new("RGBA", im.size, (0, 0, 0, 0)), keep)


def _components(mask: Image.Image) -> list[set[tuple[int, int]]]:
    """alpha 遮罩的 4 連通區，回傳像素集合，依大小遞減。"""
    w, h = mask.size
    px = mask.load()
    seen = set()
    comps = []
    for y in range(h):
        for x in range(w):
            if px[x, y] == 0 or (x, y) in seen:
                continue
            comp = set()
            stack = [(x, y)]
            seen.add((x, y))
            while stack:
                cx, cy = stack.pop()
                comp.add((cx, cy))
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < w and 0 <= ny < h and px[nx, ny] and (nx, ny) not in seen:
                        seen.add((nx, ny))
                        stack.append((nx, ny))
            comps.append(comp)
    return sorted(comps, key=len, reverse=True)


def slice_puppet(src_path: str = PUPPET_SRC, hem: int = HEM, leg_top: int = LEG_TOP, hip: int = HIP,
                 split_x: int | None = None) -> dict:
    src = Image.open(src_path).convert("RGBA")
    W, H = src.size
    k = 128 / H  # 與 128px 幀同比例
    cx, cy = W / 2, H / 2

    body = src.copy()
    body.paste((0, 0, 0, 0), (0, hem, W, H))
    legs = src.copy()
    legs.paste((0, 0, 0, 0), (0, 0, W, leg_top))
    mask = legs.split()[3].point(lambda a: 255 if a > 0 else 0)
    if split_x is not None:
        # 3/4 視角兩腿在衣襬下相連，連通區分不開：改以一條垂直線切
        px = mask.load()
        left, right = set(), set()
        for y in range(leg_top, H):
            for x in range(W):
                if px[x, y]:
                    (left if x < split_x else right).add((x, y))
        comps = [left, right]
    else:
        comps = _components(mask)[:2]
        assert len(comps) == 2, f"腿的連通區不是 2 個：{len(comps)}（3/4 視角請給 --split-x）"
        comps.sort(key=lambda c: sum(x for x, _ in c) / len(c))  # 左＝後腿、右＝前腿

    meta = {}

    def emit(name: str, im: Image.Image, pixels: set | None, pivot: tuple | None) -> None:
        if pixels is not None:
            mask = Image.new("L", im.size, 0)
            mp = mask.load()
            for x, y in pixels:
                mp[x, y] = 255
            im = Image.composite(im, Image.new("RGBA", im.size, (0, 0, 0, 0)), mask)
        bbox = im.getbbox()
        piece = im.crop(bbox)
        piece = piece.resize((max(1, round(piece.width * k)), max(1, round(piece.height * k))), Image.LANCZOS)
        piece = pp.quantize(piece)
        piece.save(os.path.join(OUT, f"puppet_{name}.png"))
        entry = {"origin": [round((bbox[0] - cx) * k, 2), round((bbox[1] - cy) * k, 2)]}
        if pivot:
            entry["pivot"] = [round((pivot[0] - cx) * k, 2), round((pivot[1] - cy) * k, 2)]
        meta[name] = entry

    emit("body", body, None, None)
    for name, comp in zip(("leg_back", "leg_front"), comps):
        top = min(y for _, y in comp)
        xs = [x for x, y in comp if y <= top + 20]
        emit(name, legs, comp, (sum(xs) / len(xs), hip))
    with open(os.path.join(OUT, "puppet.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=1)
    return meta


def install(name: str, meta: dict) -> None:
    """把拆件裝進遊戲：貼圖進 game/assets/puppets/<name>/、定義進 data/puppets/<name>.json。

    遊戲端的 JSON 格式（EnemyView._build_puppet 讀）：parts 依繪製順序排列，
    role 決定誰是腿、誰是軀幹；origin／pivot 是相對圖心的像素座標（128px 版）。
    """
    asset_dir = os.path.join(REPO, "game", "assets", "puppets", name)
    os.makedirs(asset_dir, exist_ok=True)
    os.makedirs(os.path.join(REPO, "data", "puppets"), exist_ok=True)
    parts = []
    for piece, role in (("leg_back", "leg_a"), ("leg_front", "leg_b"), ("body", "body")):
        shutil.copyfile(os.path.join(OUT, f"puppet_{piece}.png"), os.path.join(asset_dir, f"{piece}.png"))
        entry = meta[piece]
        parts.append({
            "name": piece,
            "texture": f"res://game/assets/puppets/{name}/{piece}.png",
            "origin": entry["origin"],
            "pivot": entry.get("pivot", entry["origin"]),
            "role": role,
        })
    definition = {
        "_doc": f"分件動畫定義，由 art/scripts/walk_pack.py --install {name} 產生。parts 依繪製順序；"
                "origin／pivot 為相對圖心的像素（128px 版）。swing_deg 腿擺幅、bob_px 軀幹起伏、"
                "stride_px 走幾像素算一圈——EnemyView 以走過的距離推進相位。",
        "parts": parts,
        "swing_deg": 28,
        "bob_px": 2,
        "stride_px": 40,
    }
    with open(os.path.join(REPO, "data", "puppets", f"{name}.json"), "w", encoding="utf-8") as f:
        json.dump(definition, f, ensure_ascii=False, indent=1)
    print(f"  installed → game/assets/puppets/{name}/, data/puppets/{name}.json")


def main() -> int:
    pp._console.fix()
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--install", metavar="NAME", help="把拆件裝進 game/assets/puppets/<NAME> 與 data/puppets/<NAME>.json")
    ap.add_argument("--src", default=PUPPET_SRC, help="拆件母本（去背後的全尺寸圖）")
    ap.add_argument("--hem", type=int, default=HEM)
    ap.add_argument("--leg-top", type=int, default=LEG_TOP)
    ap.add_argument("--hip", type=int, default=HIP)
    ap.add_argument("--split-x", type=int, default=None, help="兩腿以垂直線切開的 x（3/4 視角用）")
    ap.add_argument("--skip-frames", action="store_true", help="只拆件，不重打包 AI 幀")
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    if not args.skip_frames:
        for name, size, ow, tag in (("face", 128, 2, "face"), ("face", 48, 1, "face48"), ("shadow", 128, 2, "shadow")):
            n = pack_frames(name, size, ow, tag)
            print(f"  {tag:<8} {n} 幀")
    if os.path.exists(args.src):
        meta = slice_puppet(args.src, args.hem, args.leg_top, args.hip, args.split_x)
        print("  puppet  ", json.dumps(meta))
        if args.install:
            install(args.install, meta)
    print(f"=== → {os.path.relpath(OUT, REPO)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
