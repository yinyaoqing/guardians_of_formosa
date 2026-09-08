"""行走循環實驗：用 FLUX.2 Klein 參考圖編輯，從一張母本產出「同一角色」的 N 幀。

    python art/scripts/walk_frames.py --ref art_src/01_raw/xp_face_musketeer/stage_flux2/xp_face_musketeer_flux2_00001_.png --name face

產出落在 art_src/01_raw/xp_walk_<name>/stage_edit/frame_<i>.png。
這是實驗腳本，不進 chapter01 的正式產線；正式產線若採用逐格路線再併入 generate_batch.py。
"""

import argparse
import os
import shutil
import sys

import generate_batch as gb

FRAMES = [
    "contact pose: front leg planted far forward, back leg stretched behind, body at its lowest point",
    "passing pose: both legs close together under the body, back knee bent and lifted, body at its highest point",
    "contact pose mirrored: the other leg planted far forward, the first leg stretched behind, body at its lowest point",
    "passing pose mirrored: legs close together, the other knee bent and lifted, body at its highest point",
]

TEMPLATE = (
    "Edit this image. Keep the exact same character: same costume, same colors, same hat, same weapon, "
    "same art style, same plain flat background, same framing and same size on the canvas. "
    "Only change the pose: the character is now mid-walk, {frame}. "
    "The weapon stays held level at hip height with both hands. Full body, head to toe visible."
)

WORKFLOW = os.path.join(gb.REPO, "art", "workflows", "a2x_flux2_edit.api.json")


def main() -> int:
    gb._console.fix()
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--ref", required=True, help="母本圖路徑")
    ap.add_argument("--name", required=True, help="產出目錄名 xp_walk_<name>")
    ap.add_argument("--seed", type=int, default=16610430)
    ap.add_argument("--timeout", type=float, default=600.0)
    args = ap.parse_args()

    import json
    with open(WORKFLOW, encoding="utf-8") as f:
        raw = json.load(f)
    roles = raw["_roles"]
    base = {k: v for k, v in raw.items() if not k.startswith("_")}

    ref_name = f"walk_ref_{args.name}.png"
    shutil.copyfile(args.ref, os.path.join(gb.COMFY_INPUT, ref_name))
    dest = os.path.join(gb.OUT_ROOT, f"xp_walk_{args.name}", "stage_edit")
    os.makedirs(dest, exist_ok=True)

    for i, frame in enumerate(FRAMES, 1):
        wf = json.loads(json.dumps(base))
        wf[roles["positive"]]["inputs"]["text"] = TEMPLATE.format(frame=frame)
        wf[roles["ref"]]["inputs"]["image"] = ref_name
        wf[roles["sampler"]]["inputs"]["seed"] = args.seed
        wf[roles["save"]]["inputs"]["filename_prefix"] = f"walk_{args.name}_{i}"
        print(f"[{i}/{len(FRAMES)}] {frame[:40]}…", flush=True)
        prompt_id = gb.post("/prompt", {"prompt": wf})["prompt_id"]
        import time
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
            shutil.move(os.path.join(gb.COMFY_OUT, n), os.path.join(dest, f"frame_{i}.png"))
    print(f"=== 完成 → {os.path.relpath(dest, gb.REPO)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
