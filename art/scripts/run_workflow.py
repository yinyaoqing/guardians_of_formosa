"""把 API 格式的 ComfyUI 節點圖送進本機 ComfyUI，等它畫完，回報輸出檔路徑。

用途：讓出圖這件事可以在 CI／腳本裡重跑，而不是只能手點 UI。
見美術聖經 §7.2「節點圖本身就是可重現的管線」。

    python art/scripts/run_workflow.py art/workflows/a0_smoke_test.api.json
"""

import argparse
import json
import sys
import time
import urllib.error
import urllib.request

DEFAULT_SERVER = "127.0.0.1:8188"


def _post(server: str, path: str, payload: dict) -> dict:
    req = urllib.request.Request(
        f"http://{server}{path}",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def _get(server: str, path: str) -> dict:
    with urllib.request.urlopen(f"http://{server}{path}") as resp:
        return json.loads(resp.read())


def submit(server: str, workflow: dict, timeout: float) -> list[str]:
    prompt_id = _post(server, "/prompt", {"prompt": workflow})["prompt_id"]
    print(f"已送出 prompt_id={prompt_id}", flush=True)

    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        history = _get(server, f"/history/{prompt_id}")
        entry = history.get(prompt_id)
        if entry is not None:
            status = entry.get("status", {})
            if status.get("status_str") == "error":
                raise RuntimeError(f"ComfyUI 執行失敗：{json.dumps(status, ensure_ascii=False)}")
            images = [
                img["filename"]
                for node_output in entry.get("outputs", {}).values()
                for img in node_output.get("images", [])
            ]
            if images:
                return images
        time.sleep(2)

    raise TimeoutError(f"等待 {timeout} 秒仍未出圖")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("workflow", help="API 格式的節點圖 JSON")
    parser.add_argument("--server", default=DEFAULT_SERVER)
    parser.add_argument("--timeout", type=float, default=900.0)
    parser.add_argument("--seed", type=int, help="覆寫所有 KSampler 的 seed")
    args = parser.parse_args()

    with open(args.workflow, encoding="utf-8") as f:
        workflow = json.load(f)

    if args.seed is not None:
        for node in workflow.values():
            if node.get("class_type") == "KSampler":
                node["inputs"]["seed"] = args.seed

    try:
        images = submit(args.server, workflow, args.timeout)
    except urllib.error.URLError as exc:
        print(f"連不上 ComfyUI（{args.server}）：{exc}", file=sys.stderr)
        print("先啟動：cd C:/Users/yinya/git/comfyui && .venv/Scripts/python.exe main.py", file=sys.stderr)
        return 2
    except (RuntimeError, TimeoutError) as exc:
        print(str(exc), file=sys.stderr)
        return 1

    for name in images:
        print(f"輸出：{name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
