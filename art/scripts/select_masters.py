"""母本集挑選工具：產出帶編號的候選印樣，並記錄選了哪一張、來自哪個 stage。

精緻度規格 §2 對策 5 要求「10 選 1」，美術聖經 §8 要求母本集是「人工嚴格挑選」。
**挑選必須留痕**——A2x §9.3 實測：沒有這份紀錄，重跑管線根本對不到同一張圖
（鐵人軍在 10 張批次後 files[0] 換了張；大熕船進 game/assets 的是被拒絕的舊圖）。

    python art/scripts/select_masters.py --sheets                 # 產生帶編號印樣（預設 stage flat）
    python art/scripts/select_masters.py --pick enemy_archer=2    # 選第 2 張
    python art/scripts/select_masters.py --pick enemy_warjunk=1 --stage a   # 從別的 stage 挑
    python art/scripts/select_masters.py --apply                  # 選中的複製到 02_selected/master/
    python art/scripts/select_masters.py --status

master_set.json 的每筆是 {"stage": "flat", "file": "<檔名>", "picked_at": "YYYY-MM-DD"}。
postprocess.py 優先讀它，沒有紀錄的資產才退回 files[0]。
"""

import argparse
import datetime
import glob
import json
import os
import shutil

from PIL import Image, ImageDraw

import _console

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MANIFEST = os.path.join(REPO, "art", "manifest", "chapter01_assets.json")
MASTER = os.path.join(REPO, "art", "manifest", "master_set.json")
RAW = os.path.join(REPO, "art_src", "01_raw")
SHEETS = os.path.join(REPO, "art_src", "candidates")
SELECTED = os.path.join(REPO, "art_src", "02_selected", "master")

BG = (232, 220, 198)
FG = (58, 42, 34)


def candidates(asset_id: str, stage: str) -> list[str]:
    """候選只看 stage_<stage>/ 的頂層；_rejected/ 子目錄不算。"""
    return sorted(glob.glob(os.path.join(RAW, asset_id, f"stage_{stage}", "*.png")))


def load_master() -> dict:
    if os.path.exists(MASTER):
        with open(MASTER, encoding="utf-8") as f:
            return json.load(f)
    return {
        "_doc": "黃金母本集定版（美術聖經 §8 A2）。每筆記錄候選來源 stage 與檔名，"
                "postprocess.py 據此取圖；此檔亦是日後任何風格訓練的資料集清單。由 select_masters.py 維護。",
        "selections": {},
    }


def save_master(data: dict) -> None:
    with open(MASTER, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def _assets() -> list[dict]:
    with open(MANIFEST, encoding="utf-8") as f:
        return json.load(f)["assets"]


def build_sheets(stage: str, only: list[str] | None) -> int:
    os.makedirs(SHEETS, exist_ok=True)
    made = 0
    for a in _assets():
        if only and a["id"] not in only:
            continue
        files = candidates(a["id"], stage)
        if not files:
            continue
        cell = 240
        cols = min(5, len(files))
        rows = (len(files) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * cell, rows * (cell + 18) + 18), BG)
        d = ImageDraw.Draw(sheet)
        d.text((4, 2), f"{a['id']}  [{stage}]", fill=FG)
        for i, p in enumerate(files):
            x, y = (i % cols) * cell, (i // cols) * (cell + 18) + 18
            im = Image.open(p).convert("RGB")
            im.thumbnail((cell - 6, cell - 6))
            sheet.paste(im, (x + 3, y + 3))
            # 編號從 1 起，與 --pick 的參數一致
            d.text((x + 6, y + cell), f"{i + 1}", fill=FG)
        sheet.save(os.path.join(SHEETS, f"{a['id']}_{stage}.png"))
        made += 1
    print(f"=== 產生 {made} 張候選印樣 → {os.path.relpath(SHEETS, REPO)}")
    return 0


def pick(spec: str, stage: str) -> int:
    asset_id, _, num = spec.partition("=")
    files = candidates(asset_id, stage)
    if not files:
        print(f"{asset_id} 在 stage_{stage} 沒有候選")
        return 1
    if not num.isdigit() or not 1 <= int(num) <= len(files):
        print(f"{asset_id} 的編號 {num!r} 超出範圍（1–{len(files)}）")
        return 1
    data = load_master()
    data["selections"][asset_id] = {
        "stage": stage,
        "file": os.path.basename(files[int(num) - 1]),
        "picked_at": datetime.date.today().isoformat(),
    }
    save_master(data)
    print(f"  {asset_id} ← stage_{stage}/{os.path.basename(files[int(num) - 1])}")
    return 0


def selected_path(asset_id: str, data: dict | None = None) -> str | None:
    """postprocess.py 用：回傳母本集指定的原圖路徑，沒有紀錄回 None。"""
    data = data or load_master()
    sel = data["selections"].get(asset_id)
    if not sel:
        return None
    return os.path.join(RAW, asset_id, f"stage_{sel['stage']}", sel["file"])


def apply_selections() -> int:
    data = load_master()
    os.makedirs(SELECTED, exist_ok=True)
    n = 0
    for asset_id in data["selections"]:
        src = selected_path(asset_id, data)
        if not os.path.exists(src):
            print(f"  缺檔：{asset_id} 的 {os.path.relpath(src, REPO)}")
            continue
        shutil.copyfile(src, os.path.join(SELECTED, f"{asset_id}.png"))
        n += 1
    print(f"=== 已複製 {n} 個母本 → {os.path.relpath(SELECTED, REPO)}")
    return 0


def status() -> int:
    assets = _assets()
    data = load_master()
    missing = [a["id"] for a in assets if a["id"] not in data["selections"]]
    print(f"已挑選 {len(data['selections'])}/{len(assets)}")
    for asset_id, sel in data["selections"].items():
        print(f"  {asset_id:<22} stage_{sel['stage']}/{sel['file']}  ({sel['picked_at']})")
    if missing:
        print("未挑選：" + ", ".join(missing))
    return 0


def main() -> int:
    _console.fix()
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--stage", default="flat", help="候選所在的 stage（印樣與 --pick 共用）")
    ap.add_argument("--sheets", action="store_true")
    ap.add_argument("--only", action="append", help="--sheets 只做這些資產")
    ap.add_argument("--pick", action="append", default=[], help="格式 asset_id=編號")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--status", action="store_true")
    args = ap.parse_args()

    if args.sheets:
        return build_sheets(args.stage, args.only)
    for spec in args.pick:
        rc = pick(spec, args.stage)
        if rc:
            return rc
    if args.apply:
        return apply_selections()
    if args.status or not args.pick:
        return status()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
