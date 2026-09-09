"""針對性修圖：拿一張「幾乎對了」的候選當參考，用 FLUX.2 Klein 參考圖編輯只改指定的一件事。

母本挑選第二輪的回饋是「這張最理想，但標槍應在人物前方／弓弦不自然／配劍不自然」——
整張重出會失去已經對的部分，Klein 編輯（A2x §6.1：角色一致性一次解決）正好只動一處。

    python art/scripts/refine.py --asset tower_hunter_t1 \\
        --ref art_src/01_raw/tower_hunter_t1/stage_flat/tower_hunter_t1_flat_00003_.png \\
        --text "the javelin is held in front of the body, the throwing arm extended forward" --batch 4

產出落在 art_src/01_raw/<asset>/stage_fix/，select_masters.py --stage fix 可挑。
"""

import argparse
import json
import os
import shutil
import sys
import time

import generate_batch as gb

WORKFLOW = os.path.join(gb.REPO, "art", "workflows", "a2x_flux2_edit.api.json")
TEMPLATE = (
    "Edit this image. Keep the exact same character, costume, colours, flat geometric style, plain flat "
    "background, framing and size on the canvas. Change only this: {text}. Everything else stays identical. "
    "Full body, head to toe visible, featureless face with only the vertical light/dark split."
)


def main() -> int:
    gb._console.fix()
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--asset", required=True)
    ap.add_argument("--ref", required=True, help="參考候選的路徑")
    ap.add_argument("--text", required=True, help="要改的那一件事（英文）")
    ap.add_argument("--batch", type=int, default=4)
    ap.add_argument("--seed", type=int, default=16630430)
    ap.add_argument("--tag", default="", help="同一資產多個參考時用來區分檔名")
    ap.add_argument("--timeout", type=float, default=900.0)
    args = ap.parse_args()

    with open(WORKFLOW, encoding="utf-8") as f:
        raw = json.load(f)
    roles = raw["_roles"]
    wf = {k: v for k, v in raw.items() if not k.startswith("_")}

    ref_name = f"fix_ref_{args.asset}{args.tag}.png"
    shutil.copyfile(args.ref, os.path.join(gb.COMFY_INPUT, ref_name))
    wf[roles["positive"]]["inputs"]["text"] = TEMPLATE.format(text=args.text)
    wf[roles["ref"]]["inputs"]["image"] = ref_name
    wf[roles["latent"]]["inputs"]["batch_size"] = args.batch
    wf[roles["sampler"]]["inputs"]["seed"] = args.seed
    wf[roles["save"]]["inputs"]["filename_prefix"] = f"{args.asset}_fix{args.tag}"

    dest = os.path.join(gb.OUT_ROOT, args.asset, "stage_fix")
    os.makedirs(dest, exist_ok=True)
    print(f"{args.asset}{args.tag}: {args.text}", flush=True)
    prompt_id = gb.post("/prompt", {"prompt": wf})["prompt_id"]
    deadline = time.monotonic() + args.timeout
    names: list[str] = []
    while time.monotonic() < deadline:
        entry = gb.get(f"/history/{prompt_id}").get(prompt_id)
        if entry is not None:
            if entry.get("status", {}).get("status_str") == "error":
                print("    失敗", file=sys.stderr)
                return 1
            names = [img["filename"] for out in entry.get("outputs", {}).values()
                     for img in out.get("images", [])]
            if names:
                break
        time.sleep(2)
    for n in names:
        shutil.move(os.path.join(gb.COMFY_OUT, n), os.path.join(dest, n))
    print(f"=== {len(names)} 張 → {os.path.relpath(dest, gb.REPO)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
