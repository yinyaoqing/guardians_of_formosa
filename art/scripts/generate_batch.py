"""依資產清單批次出圖。

prompt 的組裝順序是 A0 實測的結論（見 docs/art/A0-environment.md §6.1）：
**構圖 → 主體 → 風格 → 色票 → 比例**。美術聖經 §4.1 把風格區塊放最前面，
實測會把主體與構圖描述稀釋掉，得到半身、多人、灰底的插畫。

    python art/scripts/generate_batch.py                      # 全部
    python art/scripts/generate_batch.py --only enemy_ironman # 單一資產
    python art/scripts/generate_batch.py --cat unit --batch 2
"""

import argparse
import json
import os
import shutil
import sys
import time
import urllib.error
import urllib.request

import _console

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MANIFEST = os.path.join(REPO, "art", "manifest", "chapter01_assets.json")
WORKFLOWS = {
    "text": os.path.join(REPO, "art", "workflows", "a0_smoke_test.api.json"),
    "a": os.path.join(REPO, "art", "workflows", "a1_unit_ref_pose.api.json"),
    "b": os.path.join(REPO, "art", "workflows", "a1_stage_b_restyle.api.json"),
}
COMFY_INPUT = r"C:\Users\yinya\git\comfyui\input"
OUT_ROOT = os.path.join(REPO, "art_src", "01_raw")
COMFY_OUT = r"C:\Users\yinya\git\comfyui\output"
SERVER = "127.0.0.1:8188"


def build_prompts(m: dict, asset: dict) -> tuple[str, str]:
    cat, fac = asset["cat"], asset["fac"]
    positive = " ".join(
        p
        for p in (
            m["framing"][cat],
            "SUBJECT: " + asset["subject"],
            m["shared"]["style"],
            m["shared"]["palette"],
            m["proportions"][cat],
        )
        if p
    )
    negative = ", ".join(
        n
        for n in (
            m["shared"]["negative_base"],
            m["negatives_by_cat"][cat],
            m["negatives"][fac],
        )
        if n
    )
    return positive, negative


def stage_dir(asset_id: str, stage: str) -> str:
    if stage == "text":
        return os.path.join(OUT_ROOT, asset_id)
    return os.path.join(OUT_ROOT, asset_id, f"stage_{stage}")


def done_count(asset_id: str, stage: str = "text") -> int:
    d = stage_dir(asset_id, stage)
    if not os.path.isdir(d):
        return 0
    return sum(1 for n in os.listdir(d) if n.lower().endswith(".png"))


def post(path: str, payload: dict) -> dict:
    req = urllib.request.Request(
        f"http://{SERVER}{path}",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def get(path: str) -> dict:
    with urllib.request.urlopen(f"http://{SERVER}{path}") as resp:
        return json.loads(resp.read())


def run_one(base_wf: dict, m: dict, asset: dict, batch: int, seed: int, timeout: float,
            stage: str = "text", source_image: str | None = None) -> list[str]:
    wf = json.loads(json.dumps(base_wf))
    positive, negative = build_prompts(m, asset)
    w, h = m["size"][asset["cat"]]

    wf["3"]["inputs"]["text"] = positive
    wf["4"]["inputs"]["text"] = negative
    wf["6"]["inputs"]["seed"] = seed
    wf["8"]["inputs"]["filename_prefix"] = f"{asset['id']}_{stage}" if stage != "text" else asset["id"]

    if stage == "b":
        # 階段 B 是 img2img，尺寸由來源圖決定，沒有 EmptyLatentImage 可設。
        wf["9"]["inputs"]["image"] = source_image
    else:
        wf["5"]["inputs"].update({"width": w, "height": h, "batch_size": batch})
    if stage == "a":
        wf["9"]["inputs"]["image"] = asset["ref"]
        wf["12"]["inputs"]["image"] = f"pose_{asset['pose']}.png"

    prompt_id = post("/prompt", {"prompt": wf})["prompt_id"]
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        entry = get(f"/history/{prompt_id}").get(prompt_id)
        if entry is not None:
            if entry.get("status", {}).get("status_str") == "error":
                raise RuntimeError(f"{asset['id']} 執行失敗")
            names = [
                img["filename"]
                for out in entry.get("outputs", {}).values()
                for img in out.get("images", [])
            ]
            if names:
                return names
        time.sleep(2)
    raise TimeoutError(f"{asset['id']} 逾時")


def main() -> int:
    _console.fix()
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--only", action="append", help="只做這些 id，可重複")
    ap.add_argument("--cat", action="append", help="只做這些分類")
    ap.add_argument("--batch", type=int, default=2, help="每個資產出幾張")
    ap.add_argument("--seed", type=int, default=16610430, help="1661/04/30 大潮")
    ap.add_argument("--timeout", type=float, default=1200.0)
    ap.add_argument("--force", action="store_true", help="重做已有足量產出的資產")
    ap.add_argument("--stage", choices=["text", "a", "b"], default="text",
                    help="text=純文字（僅適用場景）；a=史料參考+骨架；b=重新上風格")
    ap.add_argument("--dry-run", action="store_true", help="只印 prompt 不出圖")
    args = ap.parse_args()

    with open(MANIFEST, encoding="utf-8") as f:
        m = json.load(f)
    with open(WORKFLOWS[args.stage], encoding="utf-8") as f:
        # 丟掉底線開頭的鍵——那是給人看的註解，ComfyUI 會把它當節點。
        base_wf = {k: v for k, v in json.load(f).items() if not k.startswith("_")}

    assets = m["assets"]
    if args.stage in ("a", "b"):
        # 階段 A/B 需要史料參考與骨架，沒標註的資產跳過而不是靜默走錯的路徑。
        assets = [a for a in assets if a.get("ref") and a.get("pose")]
    if args.only:
        assets = [a for a in assets if a["id"] in args.only]
    if args.cat:
        assets = [a for a in assets if a["cat"] in args.cat]
    if not assets:
        print("沒有符合條件的資產", file=sys.stderr)
        return 1

    # 可續跑：出圖動輒數十分鐘，中斷後不該從頭再來一次。
    if not (args.force or args.dry_run):
        pending = [a for a in assets if done_count(a["id"], args.stage) < args.batch]
        skipped = len(assets) - len(pending)
        if skipped:
            print(f"跳過 {skipped} 個已有 {args.batch} 張以上產出的資產（--force 可重做）")
        assets = pending
        if not assets:
            print("全部資產都已達目標張數")
            return 0

    if args.dry_run:
        for a in assets:
            pos, neg = build_prompts(m, a)
            print(f"\n=== {a['id']} / {a['name']} ({a['cat']}, {a['fac']})")
            print("POS:", pos)
            print("NEG:", neg)
        return 0

    total, failed = len(assets), []
    for i, a in enumerate(assets, 1):
        print(f"[{i}/{total}] {a['id']} — {a['name']}", flush=True)
        # 階段 B 逐張吃階段 A 的產出；其餘階段一次出 batch 張。
        sources: list[str | None] = [None]
        if args.stage == "b":
            sa = stage_dir(a["id"], "a")
            sources = sorted(os.listdir(sa)) if os.path.isdir(sa) else []
            if not sources:
                print("    略過：沒有階段 A 的產出", file=sys.stderr, flush=True)
                failed.append(a["id"])
                continue

        names: list[str] = []
        try:
            for src_name in sources:
                if src_name is not None:
                    shutil.copyfile(os.path.join(stage_dir(a["id"], "a"), src_name),
                                    os.path.join(COMFY_INPUT, src_name))
                names += run_one(base_wf, m, a, args.batch, args.seed, args.timeout,
                                 args.stage, src_name)
        except (RuntimeError, TimeoutError, urllib.error.URLError) as exc:
            print(f"    失敗：{exc}", file=sys.stderr, flush=True)
            failed.append(a["id"])
            continue
        dest = stage_dir(a["id"], args.stage)
        os.makedirs(dest, exist_ok=True)
        for n in names:
            src = os.path.join(COMFY_OUT, n)
            if os.path.exists(src):
                shutil.move(src, os.path.join(dest, n))
        print(f"    {len(names)} 張 → {os.path.relpath(dest, REPO)}", flush=True)

    print(f"\n=== 完成 {total - len(failed)}/{total}")
    if failed:
        print("失敗：" + ", ".join(failed))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
