"""量測貼圖的光源偏向，實作精緻度規格 §1 的 L2 驗收。

L2 訂「全遊戲光源固定自左上方」，驗收方式是「把當前所有單位並排一列，高光全在同一側」。
人眼看得出來，但**要十幾張並排才看得出來**——規格 §2 說的正是這種延遲問題：
單張看不出漂移，累積到十幾張才顯現，此時已經產出一批廢圖。故先做量尺。

    python art/scripts/check_lighting.py --stage flux2
    python art/scripts/check_lighting.py --self-test
"""

import argparse

from PIL import Image

import _console


def lighting_bias(path: str) -> dict:
    """左半減右半、左上象限減右下象限的平均亮度差。光源自左上時兩者皆為正。

    只統計不透明像素，並以不透明區的外接框切象限——用整張畫布切的話，
    置中留白會把結果稀釋掉。
    """
    im = Image.open(path).convert("RGBA")
    px = im.load()
    w, h = im.size

    xs, ys = [], []
    for y in range(h):
        for x in range(w):
            if px[x, y][3] > 0:
                xs.append(x)
                ys.append(y)
    if not xs:
        return {"horizontal": 0.0, "diagonal": 0.0, "opaque_px": 0}

    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    mx, my = (x0 + x1) / 2.0, (y0 + y1) / 2.0

    sums = {"left": [0.0, 0], "right": [0.0, 0], "ul": [0.0, 0], "lr": [0.0, 0]}
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
            side = "left" if x <= mx else "right"
            sums[side][0] += lum
            sums[side][1] += 1
            if x <= mx and y <= my:
                sums["ul"][0] += lum
                sums["ul"][1] += 1
            elif x > mx and y > my:
                sums["lr"][0] += lum
                sums["lr"][1] += 1

    def mean(k: str):
        """回傳該桶平均亮度；桶內沒有像素時回傳 None（未定義，不是全黑）。

        外接框只有 1px 寬或 1px 高時，"left"/"right" 或 "ul"/"lr"
        其中一桶可能完全沒有像素。若在此把空桶當成亮度 0 的黑，
        會讓對應的 horizontal/diagonal 指標被拉向錯誤的方向，
        誤報成「光源偏右/偏右下」。
        """
        total, n = sums[k]
        return total / n if n else None

    def bias(a: str, b: str) -> float:
        ma, mb = mean(a), mean(b)
        if ma is None or mb is None:
            return 0.0
        return (ma - mb) / 255.0

    return {
        "horizontal": bias("left", "right"),
        "diagonal": bias("ul", "lr"),
        "opaque_px": sums["left"][1] + sums["right"][1],
    }


def _synthetic(lit_from_left: bool) -> Image.Image:
    """合成一張只有明暗梯度的圖，用來驗證偵測方向沒有寫反。"""
    im = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    px = im.load()
    for y in range(64):
        for x in range(64):
            t = (x + y) / 126.0
            v = int(255 * (1.0 - t) if lit_from_left else 255 * t)
            px[x, y] = (v, v, v, 255)
    return im


def self_test() -> int:
    import os
    import tempfile

    failures = 0
    with tempfile.TemporaryDirectory() as tmp:
        for lit_left, expect_positive in ((True, True), (False, False)):
            p = os.path.join(tmp, f"probe_{lit_left}.png")
            _synthetic(lit_left).save(p)
            bias = lighting_bias(p)
            # _synthetic() 的梯度是 t = (x + y) / 126，對 x、y 對稱，
            # 所以只驗 diagonal 的話，horizontal 算反（回傳 right - left）
            # 也會因為左右對稱而恰好通過測試，偵測不出符號寫反的 bug。
            # horizontal 是回傳值合約的一部分，必須跟 diagonal 一樣被驗證。
            ok_h = (bias["horizontal"] > 0) == expect_positive
            ok_d = (bias["diagonal"] > 0) == expect_positive
            ok = ok_h and ok_d
            print(
                f"  左上打光={lit_left}  horizontal={bias['horizontal']:+.3f}  "
                f"diagonal={bias['diagonal']:+.3f}  {'OK' if ok else '錯'}"
            )
            if not ok:
                failures += 1
    print("=== 自我驗證通過" if failures == 0 else f"=== 自我驗證失敗 {failures} 項")
    return failures


def main() -> int:
    _console.fix()
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--stage", default="flux2")
    ap.add_argument("--cat", action="append", default=None)
    args = ap.parse_args()
    if args.self_test:
        return 1 if self_test() else 0

    import json
    import os

    repo = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    with open(os.path.join(repo, "art", "manifest", "chapter01_assets.json"), encoding="utf-8") as f:
        assets = json.load(f)["assets"]
    if args.cat:
        assets = [a for a in assets if a["cat"] in args.cat]

    rows, wrong = [], []
    for a in assets:
        # source_stage：該資產正確候選釘死的 stage，覆蓋 --stage——與
        # postprocess.py 同一條規則，見 manifest 的 _source_stage_note。
        # 沒有這個覆蓋，--stage flux2 的預設呼叫量測到的是已被拒絕、不再
        # 出貨的舊候選，L2 閘門等於沒驗到真正出貨的那張圖。
        stage = a.get("source_stage", args.stage)
        d = os.path.join(repo, "art_src", "01_raw", a["id"], f"stage_{stage}")
        if not os.path.isdir(d):
            continue
        for n in sorted(x for x in os.listdir(d) if x.endswith(".png")):
            b = lighting_bias(os.path.join(d, n))
            rows.append((a["id"], n, b))
            if b["diagonal"] <= 0.0:
                wrong.append((a["id"], n, b["diagonal"]))

    for aid, n, b in rows:
        print(f"  {aid:<22} h={b['horizontal']:+.3f}  d={b['diagonal']:+.3f}")
    print()
    if wrong:
        print(f"=== 光源方向不一致 {len(wrong)}/{len(rows)}（diagonal 應為正，代表左上較亮）")
        for aid, n, d in wrong:
            print(f"  {aid} / {n}  diagonal={d:+.3f}")
        return 1
    print(f"=== 光源方向一致：{len(rows)} 張全部自左上打光")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
