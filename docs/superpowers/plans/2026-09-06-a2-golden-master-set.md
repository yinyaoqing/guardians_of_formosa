# A2 黃金母本集 實作計畫

> **給代理執行者：** 必用子技能：`superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐任務執行。步驟以核取方塊（`- [ ]`）追蹤。

**目標：** 產出 20–30 張人工嚴格挑選的定調資產，並讓「連續三批風格穩定」與「光源方向一致」兩項判準可自動量測，通過後解除 A5 量產的閘門。

**架構：** 沿用既有的 FLUX.2 管線（`generate_batch.py --stage flux2` → `postprocess.py`）。新增三支腳本：光源一致性量測、挑選工具、批次穩定性量測。挑選結果寫進 `art/manifest/master_set.json`，並由一支 GdUnit4 測試確保 `game/assets/chapter01/` 與母本集一致，避免有人繞過挑選直接塞圖。

**技術棧：** Python 3.12 + Pillow（管線與量測）、ComfyUI + FLUX.2 Klein 4B（生成）、GdUnit4（閘門）。

## Global Constraints

以下為規格原文，每個任務都隱含適用。

- **A2 交付物**（美術聖經 §8）：「20–30 張人工嚴格挑選的定調資產」
- **A2 完成判準**（美術聖經 §8）：「連續三批風格穩定；並排檢視時光源方向一致」
- **A2 是閘門**（美術聖經 §8）：「母本集確立前不量產」
- **L2 驗收**（精緻度規格 §1）：「把當前所有單位並排一列，高光全在同一側」
- **光源定義**（精緻度規格 §1 L2）：「全遊戲光源固定自**左上方**，投影短而硬（亞熱帶正午）」
- **篩選比例**（精緻度規格 §2 對策 5）：「大量生成 → 嚴格篩選（10 選 1），不要靠修圖搶救」
- **尺寸上限**（美術聖經 §5.1）：敵人／士兵 ≤128×128；塔（含底座）≤192×192
- **色彩**（美術聖經 §5.1）：sRGB，**必須通過色票檢查**
- **art_src/ 不進 git**（美術聖經 §5.2）；`game/assets/` 進 git 走 LFS
- **只用 GDScript，不引入 C#**（CLAUDE.md）
- **遊戲資料一律 JSON，置於 `data/`**（CLAUDE.md）

## 目前狀態（計畫撰寫時）

- `art_src/01_raw/<id>/stage_flux2/` 已有 33 個資產各 2 張候選
- `game/assets/chapter01/` 已有 33 張成品，走 LFS，通過色票與尺寸兩道 GdUnit4 閘門
- 剪影相似度超過 0.93 的配對：1（`enemy_musketeer ↔ voc_coyett`，0.930）
- **尚未達成 A2 的三件事**：
  1. 現有 33 張是**程式自動取第一張**，不是「10 選 1 人工嚴格挑選」
  2. 「連續三批風格穩定」從未量測
  3. 「光源方向一致」從未量測
- **兩個已知錯誤資產**：`enemy_ironman`（畫成歐洲鎖子甲）、`enemy_warjunk`（畫成歐洲蓋倫帆船）

## 檔案結構

| 檔案 | 責任 |
|---|---|
| `art/scripts/check_lighting.py`（新增） | 量測單一資產的光源偏向，回報整組的一致性。實作 L2 驗收 |
| `art/scripts/select_masters.py`（新增） | 產出帶編號的候選印樣；讀寫 `master_set.json`；把選中的複製到 `02_selected/` |
| `art/scripts/batch_stability.py`（新增） | 以色票直方圖量測三批之間的風格距離 |
| `art/manifest/master_set.json`（新增） | 母本集定版：資產 id → 選中的候選檔名 + 選定日期 |
| `tests/test_art_master_set.gd`（新增） | 閘門：`game/assets/chapter01/` 的每張圖都必須出自母本集 |
| `art/manifest/chapter01_assets.json`（修改） | 為 `enemy_ironman` 與 `enemy_warjunk` 補史料參考與修正描述 |
| `docs/art/A2-master-set.md`（新增） | 母本集的驗收記錄：三批距離、光源分佈、挑選原則 |

---

### Task 1：光源方向一致性量測

L2 的驗收是「把當前所有單位並排一列，高光全在同一側」。人眼看得出來，但**十幾張並排才看得出來**——這正是規格 §2 說的延遲問題。先做量尺。

**Files:**
- Create: `art/scripts/check_lighting.py`

**Interfaces:**
- Produces: `lighting_bias(path: str) -> dict` 回傳 `{"horizontal": float, "diagonal": float, "opaque_px": int}`；`horizontal` 為左半減右半的平均亮度差（除以 255），`diagonal` 為左上象限減右下象限。光源自左上時兩者皆應為正。

- [ ] **Step 1：先寫會失敗的自我驗證**

Python 端沒有測試框架，且引入 pytest 屬範圍外。改用與色票檢查同樣的紀律：腳本自帶 `--self-test`，用合成圖驗證偵測真的有效。

建立 `art/scripts/check_lighting.py`，先只放自我驗證與尚未實作的函式：

```python
"""量測貼圖的光源偏向，實作精緻度規格 §1 的 L2 驗收。

L2 訂「全遊戲光源固定自左上方」，驗收方式是「把當前所有單位並排一列，高光全在同一側」。
人眼看得出來，但**要十幾張並排才看得出來**——規格 §2 說的正是這種延遲問題：
單張看不出漂移，累積到十幾張才顯現，此時已經產出一批廢圖。故先做量尺。

    python art/scripts/check_lighting.py --stage flux2
    python art/scripts/check_lighting.py --self-test
"""

import argparse
import sys

from PIL import Image

import _console


def lighting_bias(path: str) -> dict:
    raise NotImplementedError


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
            ok = (bias["diagonal"] > 0) == expect_positive
            print(f"  左上打光={lit_left}  diagonal={bias['diagonal']:+.3f}  {'OK' if ok else '錯'}")
            if not ok:
                failures += 1
    print("=== 自我驗證通過" if failures == 0 else f"=== 自我驗證失敗 {failures} 項")
    return failures


def main() -> int:
    _console.fix()
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        return 1 if self_test() else 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2：執行確認它失敗**

```bash
cd c:/Users/yinya/git/guardians_of_formosa
python art/scripts/check_lighting.py --self-test
```

預期：`NotImplementedError`。

- [ ] **Step 3：實作 `lighting_bias`**

把 `raise NotImplementedError` 換成：

```python
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

    def mean(k: str) -> float:
        total, n = sums[k]
        return total / n if n else 0.0

    return {
        "horizontal": (mean("left") - mean("right")) / 255.0,
        "diagonal": (mean("ul") - mean("lr")) / 255.0,
        "opaque_px": sums["left"][1] + sums["right"][1],
    }
```

- [ ] **Step 4：執行確認自我驗證通過**

```bash
python art/scripts/check_lighting.py --self-test
```

預期輸出含 `=== 自我驗證通過`，離開碼 0。

- [ ] **Step 5：加上掃描全資產的模式**

把 `main()` 換成：

```python
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
        d = os.path.join(repo, "art_src", "01_raw", a["id"], f"stage_{args.stage}")
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
```

- [ ] **Step 6：對現有 33 個資產執行，記錄基線**

```bash
python art/scripts/check_lighting.py --stage flux2
```

把輸出貼進 `docs/art/A2-master-set.md` 的「光源基線」段落。**這一步不預期全過**——目的是知道現況分佈，決定要不要重生成。

- [ ] **Step 7：提交**

```bash
git add art/scripts/check_lighting.py docs/art/A2-master-set.md
git commit -m "feat(art): 光源方向一致性量測，實作 L2 驗收"
```

---

### Task 2：修正鐵人軍與大熕船

母本集是後續 LoRA 訓練（A3）的資料集。**含有已知錯誤的母本會把錯誤鎖進 LoRA**，之後每張圖都會帶著它。故必須在量產候選之前修掉。

兩者同屬「特定東亞軍事／船舶形制」的模型知識缺口（見 `docs/art/A1-findings.md` §9.3）——FLUX.2 知道明代步兵服裝，不知道鐵人軍與中式硬帆。

**Files:**
- Modify: `art/manifest/chapter01_assets.json`（`enemy_ironman` 與 `enemy_warjunk` 的 `subject`）
- Modify: `art/manifest/reference_images.json`（補中式帆船的史料來源）

**Interfaces:**
- Consumes: Task 1 的 `check_lighting.py`（驗收時一併跑）
- Produces: 兩個資產的候選圖，供 Task 3 量產

- [ ] **Step 1：先確認純文字 prompt 到底能不能救**

在改任何東西之前，先用更具體的形制描述試一輪。若可行就不必動用參考圖路線。

編輯 `art/manifest/chapter01_assets.json`，把 `enemy_ironman` 的 `subject` 換成：

```
a 17th-century Ming Chinese heavy infantryman. Chinese lamellar armour made of hundreds of small overlapping rectangular iron plates laced with cord, NOT European chainmail and NOT a European great helm. A rounded Chinese iron helmet with a neck guard of the same lamellar plates, and a separate iron face mask covering the whole face. An enormous two-handed Chinese horse-cutting sabre with a long straight single-edged blade, held across the shoulders. A round rattan shield slung on the back. BARE FEET, no boots, no shoes. Bulky rectangular heavy silhouette, iron grey with no bright colors.
```

把 `enemy_warjunk` 的 `subject` 換成：

```
a 17th-century Chinese war junk. Chinese battened lug sails made of stiff panels divided by horizontal bamboo battens, forming a broad fan shape — NOT European square sails and NOT triangular lateen sails. A high square transom stern, a blunt bow with no bowsprit, a flat bottom. Dark burnt umber timber hull, sails in ochre and sand. Open side gun ports with bronze cannon muzzles, a cinnabar red banner at the masthead.
```

- [ ] **Step 2：生成並檢視**

```bash
python art/scripts/generate_batch.py --stage flux2 --batch 4 --force \
  --only enemy_ironman --only enemy_warjunk
python art/scripts/contact_sheet.py --cat unit --cat vessel --cols 4
```

檢視 `art_src/contact/`。判準：鐵人是**札甲＋鐵面罩＋赤足**、大熕船是**硬帆的扇形剪影**（章節規格 §3.2）。

- [ ] **Step 3：若仍失敗，改走階段 A 的史料參考圖**

只有在 Step 2 四張都不對時才做這一步。

先補史料來源。編輯 `art/manifest/reference_images.json`，在 `groups` 加入：

```json
"chinese_junk": {
  "zh": "中式硬帆：扇形帆、橫向竹製帆骨、方形艉",
  "note": "章節規格 §3.2 要求大熕船的剪影是「中式硬帆的扇形」。FLUX.2 不知道這個形制，兩輪都畫成歐洲蓋倫帆船。",
  "titles": [
    "File:Chinese junk Keying.jpg",
    "File:Junk (ship) - Wikipedia.jpg"
  ]
}
```

執行 `python art/scripts/fetch_refs.py --group chinese_junk --list` 先確認檔名是否存在；不存在就用 `--list` 的輸出換成 Commons 上實際有的檔名。

取得後裁成**單一孤立主體**（A1 §7.5 的結論：IP-Adapter 會把整張參考圖搬過來），放進 `C:/Users/yinya/git/comfyui/input/ref_junk.jpg`，在清單為 `enemy_warjunk` 補 `"ref": "ref_junk.jpg"` 與 `"pose": "idle"`，然後：

```bash
python art/scripts/generate_batch.py --stage a --batch 4 --force --only enemy_warjunk
```

- [ ] **Step 4：跑後處理與兩道閘門**

```bash
python art/scripts/postprocess.py --stage flux2 --only enemy_ironman --only enemy_warjunk
python art/scripts/postprocess.py --verify-only
```

預期：色票檢查通過。

- [ ] **Step 5：提交**

```bash
git add art/manifest/chapter01_assets.json art/manifest/reference_images.json
git commit -m "fix(art): 鐵人軍與大熕船改用形制具體的描述"
```

---

### Task 3：候選量產（每資產 10 張）

精緻度規格 §2 對策 5：「大量生成 → 嚴格篩選（10 選 1）」。現有的每資產 2 張不足以支撐「嚴格」。

**Files:**
- 無新增檔案；產出落在 `art_src/01_raw/<id>/stage_flux2/`

**Interfaces:**
- Consumes: Task 2 修正後的清單
- Produces: 每個資產 10 張候選，供 Task 4 挑選

- [ ] **Step 1：確認 ComfyUI 在線**

```bash
curl -s -o /dev/null -m 5 -w "HTTP %{http_code}\n" http://127.0.0.1:8188/system_stats
```

預期 `HTTP 200`。若不是，用下列指令啟動（PowerShell）：

```powershell
Start-Process -FilePath "C:\Users\yinya\git\comfyui\.venv\Scripts\python.exe" `
  -ArgumentList "main.py","--listen","127.0.0.1","--port","8188" `
  -WorkingDirectory "C:\Users\yinya\git\comfyui" `
  -RedirectStandardOutput "C:\Users\yinya\git\comfyui\comfyui-server.log" `
  -RedirectStandardError "C:\Users\yinya\git\comfyui\comfyui-server.log.err" `
  -WindowStyle Hidden
```

- [ ] **Step 2：量產候選**

`--seed` 每批不同，否則 batch 內雖有變化但批與批之間會重複。

```bash
python art/scripts/generate_batch.py --stage flux2 --batch 10 --force --seed 16610430
```

預估：33 資產 × 10 張，約 60–90 分鐘。用 `nohup ... &` 背景執行，避免 session 中斷。

- [ ] **Step 3：確認張數**

```bash
python -c "
import json,io,os
d=json.load(io.open('art/manifest/chapter01_assets.json',encoding='utf-8'))
short=[(a['id'],len(os.listdir(os.path.join('art_src/01_raw',a['id'],'stage_flux2'))))
       for a in d['assets']
       if len(os.listdir(os.path.join('art_src/01_raw',a['id'],'stage_flux2')))<10]
print('不足 10 張的:', short or '無')"
```

預期：`無`。

- [ ] **Step 4：跑光源量測，先刷掉方向錯的候選**

```bash
python art/scripts/check_lighting.py --stage flux2 > art_src/lighting_baseline.txt
tail -5 art_src/lighting_baseline.txt
```

輸出留著給 Task 4 參考——**光源方向錯的候選一律不選**，這是 A2 的判準之一，不是主觀偏好。

---

### Task 4：挑選工具與母本集清單

> **2026-09-09 實作完成**（`art/scripts/select_masters.py`）。與本計畫的差異：`master_set.json` 每筆多記 `stage`（候選可能來自 `flat`／`ref`／`a` 不同 stage）；預設 stage 改為 `flat`（風格已定案扁平幾何無五官）；`02_selected/master/` 取代 `02_selected/flux2/`；`postprocess.py` 直接讀 `master_set.json` 取圖、沒有紀錄的資產印提醒。理由見 `docs/art/A2x` §9.3——沒有來源紀錄，重跑管線對不到同一張圖。

人工挑選需要兩件東西：一次看得到十張的帶編號印樣，以及一個記錄「選了哪張」的檔案。**選擇必須留痕**，否則 A3 訓練 LoRA 時無從得知母本是哪些圖。

**Files:**
- Create: `art/scripts/select_masters.py`
- Create: `art/manifest/master_set.json`（由腳本產生骨架）

**Interfaces:**
- Consumes: `art_src/01_raw/<id>/stage_flux2/*.png`
- Produces: `master_set.json`，結構為 `{"selections": {"<asset_id>": {"file": "<檔名>", "picked_at": "YYYY-MM-DD"}}, ...}`；以及 `art/scripts/select_masters.py` 的 `apply_selections() -> int`

- [ ] **Step 1：建立腳本**

```python
"""母本集挑選工具：產出帶編號的候選印樣，並記錄選了哪一張。

精緻度規格 §2 對策 5 要求「10 選 1」，美術聖經 §8 要求母本集是「人工嚴格挑選」。
**挑選必須留痕**——A3 要用母本集訓 LoRA，屆時得知道母本究竟是哪 20–30 張。

    python art/scripts/select_masters.py --sheets       # 產生帶編號印樣
    python art/scripts/select_masters.py --pick enemy_archer=3
    python art/scripts/select_masters.py --apply        # 把選中的複製到 02_selected/
    python art/scripts/select_masters.py --status
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
SELECTED = os.path.join(REPO, "art_src", "02_selected", "flux2")


def candidates(asset_id: str, stage: str = "flux2") -> list[str]:
    return sorted(glob.glob(os.path.join(RAW, asset_id, f"stage_{stage}", "*.png")))


def load_master() -> dict:
    if os.path.exists(MASTER):
        with open(MASTER, encoding="utf-8") as f:
            return json.load(f)
    return {
        "_doc": "黃金母本集定版。美術聖經 §8 A2：20–30 張人工嚴格挑選的定調資產。"
                "A3 以此訓練風格 LoRA，故此檔即該次訓練的資料集清單。",
        "selections": {},
    }


def save_master(data: dict) -> None:
    with open(MASTER, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def build_sheets(stage: str) -> int:
    os.makedirs(SHEETS, exist_ok=True)
    with open(MANIFEST, encoding="utf-8") as f:
        assets = json.load(f)["assets"]
    made = 0
    for a in assets:
        files = candidates(a["id"], stage)
        if not files:
            continue
        cell = 240
        cols = min(5, len(files))
        rows = (len(files) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * cell, rows * (cell + 18)), (232, 220, 198))
        d = ImageDraw.Draw(sheet)
        for i, p in enumerate(files):
            x, y = (i % cols) * cell, (i // cols) * (cell + 18)
            im = Image.open(p).convert("RGB")
            im.thumbnail((cell - 6, cell - 6))
            sheet.paste(im, (x + 3, y + 3))
            # 編號從 1 起，與 --pick 的參數一致
            d.text((x + 6, y + cell), f"{i + 1}", fill=(58, 42, 34))
        sheet.save(os.path.join(SHEETS, f"{a['id']}.png"))
        made += 1
    print(f"=== 產生 {made} 張候選印樣 → {os.path.relpath(SHEETS, REPO)}")
    return 0


def pick(spec: str, stage: str) -> int:
    asset_id, _, num = spec.partition("=")
    files = candidates(asset_id, stage)
    if not files:
        print(f"{asset_id} 沒有候選")
        return 1
    idx = int(num) - 1
    if not 0 <= idx < len(files):
        print(f"{asset_id} 的編號 {num} 超出範圍（1–{len(files)}）")
        return 1
    data = load_master()
    data["selections"][asset_id] = {
        "file": os.path.basename(files[idx]),
        "picked_at": datetime.date.today().isoformat(),
    }
    save_master(data)
    print(f"  {asset_id} ← {os.path.basename(files[idx])}")
    return 0


def apply_selections(stage: str) -> int:
    data = load_master()
    os.makedirs(SELECTED, exist_ok=True)
    n = 0
    for asset_id, sel in data["selections"].items():
        src = os.path.join(RAW, asset_id, f"stage_{stage}", sel["file"])
        if not os.path.exists(src):
            print(f"  缺檔：{asset_id} 的 {sel['file']}")
            continue
        shutil.copyfile(src, os.path.join(SELECTED, f"{asset_id}.png"))
        n += 1
    print(f"=== 已複製 {n} 個母本 → {os.path.relpath(SELECTED, REPO)}")
    return 0


def status(stage: str) -> int:
    with open(MANIFEST, encoding="utf-8") as f:
        assets = json.load(f)["assets"]
    data = load_master()
    missing = [a["id"] for a in assets if a["id"] not in data["selections"]]
    print(f"已挑選 {len(data['selections'])}/{len(assets)}")
    if missing:
        print("未挑選：" + ", ".join(missing))
    return 0


def main() -> int:
    _console.fix()
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--stage", default="flux2")
    ap.add_argument("--sheets", action="store_true")
    ap.add_argument("--pick", action="append", default=[], help="格式 asset_id=編號")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--status", action="store_true")
    args = ap.parse_args()

    if args.sheets:
        return build_sheets(args.stage)
    for spec in args.pick:
        rc = pick(spec, args.stage)
        if rc:
            return rc
    if args.apply:
        return apply_selections(args.stage)
    if args.status or not args.pick:
        return status(args.stage)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2：產生印樣並確認編號可讀**

```bash
python art/scripts/select_masters.py --sheets
python art/scripts/select_masters.py --status
```

預期：`已挑選 0/33`，且 `art_src/candidates/` 有 33 張帶 1–10 編號的印樣。

- [ ] **Step 3：驗證挑選與套用**

```bash
python art/scripts/select_masters.py --pick enemy_archer=1
python art/scripts/select_masters.py --apply
python art/scripts/select_masters.py --status
```

預期：`已挑選 1/33`，且 `art_src/02_selected/flux2/enemy_archer.png` 存在。

- [ ] **Step 4：提交**

```bash
git add art/scripts/select_masters.py art/manifest/master_set.json
git commit -m "feat(art): 母本集挑選工具，挑選結果留痕"
```

---

### Task 5：人工挑選

**這一步無法自動化，也不該自動化。** 美術聖經 §8 寫的是「人工嚴格挑選」，A2 的價值就在這個判斷。

**Files:**
- Modify: `art/manifest/master_set.json`（累積 33 筆選擇）

- [ ] **Step 1：逐一檢視印樣並挑選**

開啟 `art_src/candidates/<asset_id>.png`，對每個資產下 `--pick`。

挑選判準，依序：

1. **史實正確**（章節規格 §3）——鄭軍赤足、不得辮髮、西拉雅裸身圍腰、VOC 無制式軍服。錯的直接淘汰，不進入後續比較
2. **光源自左上**——參考 Task 3 產出的 `art_src/lighting_baseline.txt`，`diagonal` 為負的一律不選
3. **剪影可讀**（章節規格 §3.4）——笠形盔的三角、鐵人的方塊、鏢手的長鏢斜線
4. **陣營識別色**（美術聖經 §2.2）——玩家方必須有一塊藤黃，敵方必須沒有
5. 以上皆同分時，才看主觀的好看

- [ ] **Step 2：套用並跑後處理**

```bash
python art/scripts/select_masters.py --apply
python art/scripts/postprocess.py --stage flux2
python art/scripts/postprocess.py --verify-only
```

預期：色票檢查通過。

- [ ] **Step 3：跑光源與剪影兩項判準**

```bash
python art/scripts/check_lighting.py --stage flux2
python art/scripts/silhouette.py --stage flux2 --cat unit
python art/scripts/contact_sheet.py --cat unit --cols 17
```

預期：光源全部為正；剪影超過 0.93 的配對數不高於現況的 1 對。**若超過，回到 Step 1 換選**——這正是 10 選 1 的用途。

第三行的 `--cols 17` 是為了把所有單位排成一列——**L2 的驗收原文是「把當前所有單位並排一列，高光全在同一側」，那是人眼檢視，自動量測取代不了**。`check_lighting.py` 是先刷掉明顯錯的，並排帶才是最終判準。開啟 `art_src/contact/contact_unit.png` 目視確認高光同側。

- [ ] **Step 4：提交**

```bash
git add art/manifest/master_set.json
git commit -m "feat(art): 母本集人工挑選定版"
```

---

### Task 6：連續三批風格穩定

A2 的另一項判準。規格沒有給數字，故本任務**先量測再定門檻**，並把依據寫進文件——憑空訂一個數字比不訂更糟。

**Files:**
- Create: `art/scripts/batch_stability.py`

**Interfaces:**
- Consumes: `data/art_palette.json`
- Produces: `palette_histogram(path) -> dict[str, float]`（色票色 → 佔不透明像素的比例）；`tv_distance(a, b) -> float`（總變異距離，0 為完全相同、1 為完全不同）

- [ ] **Step 1：建立腳本**

```python
"""量測批次之間的風格距離，實作美術聖經 §8 A2 的「連續三批風格穩定」。

方法：把每張圖的用色分佈算成色票直方圖，再取批次內所有資產的平均，
以總變異距離（TV distance）比較批次之間的差異。

為什麼用色票直方圖而不是像素差：批與批之間人物姿勢本來就不同，逐像素比較毫無意義；
風格漂移的表現是**用色比例改變**——這正是規格 §2 說的「三十張擺在一起不像同一款遊戲」。

    python art/scripts/batch_stability.py --batches art_src/batch_a art_src/batch_b art_src/batch_c
"""

import argparse
import glob
import json
import os

from PIL import Image

import _console

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PALETTE_JSON = os.path.join(REPO, "data", "art_palette.json")


def _hex(v: str) -> tuple[int, int, int]:
    v = v.lstrip("#")
    return int(v[0:2], 16), int(v[2:4], 16), int(v[4:6], 16)


def _targets() -> dict[str, tuple[int, int, int]]:
    with open(PALETTE_JSON, encoding="utf-8") as f:
        p = json.load(f)
    out = {}
    for section in ("palette", "skin", "outline"):
        for name, v in p[section].items():
            out[f"{section}/{name}"] = _hex(v)
    return out


def palette_histogram(path: str) -> dict[str, float]:
    targets = _targets()
    im = Image.open(path).convert("RGBA")
    px = im.load()
    counts = {k: 0 for k in targets}
    total = 0
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            total += 1
            best = min(targets.items(),
                       key=lambda kv: (kv[1][0] - r) ** 2 + (kv[1][1] - g) ** 2 + (kv[1][2] - b) ** 2)
            counts[best[0]] += 1
    if total == 0:
        return {k: 0.0 for k in targets}
    return {k: v / total for k, v in counts.items()}


def tv_distance(a: dict[str, float], b: dict[str, float]) -> float:
    return 0.5 * sum(abs(a[k] - b.get(k, 0.0)) for k in a)


def batch_histogram(folder: str) -> dict[str, float]:
    files = sorted(glob.glob(os.path.join(folder, "*.png")))
    if not files:
        raise SystemExit(f"{folder} 沒有 PNG")
    acc: dict[str, float] = {}
    for p in files:
        h = palette_histogram(p)
        for k, v in h.items():
            acc[k] = acc.get(k, 0.0) + v
    return {k: v / len(files) for k, v in acc.items()}


def main() -> int:
    _console.fix()
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--batches", nargs="+", required=True)
    args = ap.parse_args()

    hists = [(os.path.basename(b.rstrip("/\\")), batch_histogram(b)) for b in args.batches]
    print("=== 批次之間的總變異距離（0 = 完全相同）")
    worst = 0.0
    for i in range(len(hists)):
        for j in range(i + 1, len(hists)):
            d = tv_distance(hists[i][1], hists[j][1])
            worst = max(worst, d)
            print(f"  {hists[i][0]} ↔ {hists[j][0]}  TV={d:.4f}")
    print(f"\n最大距離 {worst:.4f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2：產生三批**

三批必須用**不同 seed**，否則量到的是同一批。

```bash
for s in 16610430 16610501 16620201; do
  python art/scripts/generate_batch.py --stage flux2 --batch 1 --force --seed $s
  python art/scripts/postprocess.py --stage flux2
  mkdir -p art_src/stability/batch_$s
  cp art_src/03_processed/*.png art_src/stability/batch_$s/
done
```

三個 seed 取自章節規格 §2 的關鍵日期（4/30 突入、5/1 北線尾之戰、1662/2/1 簽約），純粹為了可重現。

- [ ] **Step 3：量測**

```bash
python art/scripts/batch_stability.py --batches art_src/stability/batch_*
```

- [ ] **Step 4：依實測值定門檻並記錄**

把三個兩兩距離與最大值寫進 `docs/art/A2-master-set.md`，並在該文件明訂：

> **穩定門檻定為實測最大距離的 1.5 倍**，取整到小數第二位。依據是本次三批的實測值 X.XXXX；A3 訓練 LoRA 後產出的新批次若超過此值，視為風格漂移。

**不要先訂數字再去湊。** 規格沒給數字，就用實測值定，並寫明依據。

- [ ] **Step 5：提交**

```bash
git add art/scripts/batch_stability.py docs/art/A2-master-set.md
git commit -m "feat(art): 批次風格穩定度量測，門檻依實測值訂定"
```

---

### Task 7：凍結母本集並加上閘門

母本集一旦定版，`game/assets/chapter01/` 就不該再出現非母本的圖。沒有這道閘門，任何人（包括未來的我）都可能繞過挑選直接塞圖進去，而 A3 訓練時仍以為母本集是那 33 張。

**Files:**
- Create: `tests/test_art_master_set.gd`
- Modify: `art/manifest/master_set.json`（複製一份到 `data/`，供 Godot 讀取）
- Create: `data/art_master_set.json`

**Interfaces:**
- Consumes: `art/manifest/master_set.json`
- Produces: `data/art_master_set.json`，結構為 `{"assets": ["<asset_id>", ...]}`

- [ ] **Step 1：把母本集清單輸出成 Godot 可讀的資料**

在 `art/scripts/select_masters.py` 的 `apply_selections()` 末尾加入：

```python
    # 同步一份給 Godot 測試讀。art/ 是產線、data/ 是遊戲資料，
    # 測試不該去讀產線目錄——那會讓 game 依賴 art 的內部結構。
    game_side = os.path.join(REPO, "data", "art_master_set.json")
    with open(game_side, "w", encoding="utf-8") as f:
        json.dump({
            "_doc": "母本集的資產 id 清單，由 art/scripts/select_masters.py --apply 產生。"
                    "權威是 art/manifest/master_set.json，本檔是給 tests/test_art_master_set.gd 用的副本。",
            "assets": sorted(data["selections"].keys()),
        }, f, ensure_ascii=False, indent=2)
```

- [ ] **Step 2：寫會失敗的測試**

建立 `tests/test_art_master_set.gd`：

```gdscript
extends GdUnitTestSuite

## 母本集閘門。美術聖經 §8：「A2 是閘門：母本集確立前不量產」。
##
## 母本集定版後，game/assets/chapter01/ 就不該再出現非母本的圖。沒有這道閘門，
## 任何人都可能繞過挑選直接塞圖進去，而 A3 訓練 LoRA 時仍以為母本集是原本那些。

const MASTER_PATH := "res://data/art_master_set.json"
const ASSETS_DIR := "res://game/assets/chapter01"

var _master: Array = []


func before_test() -> void:
	var text := FileAccess.get_file_as_string(MASTER_PATH)
	assert_str(text).override_failure_message("讀不到 %s" % MASTER_PATH).is_not_empty()
	var data: Variant = JSON.parse_string(text)
	assert_bool(data is Dictionary).override_failure_message("母本集 JSON 格式錯誤").is_true()
	_master = data.get("assets", [])


func _asset_names() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(ASSETS_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".png"):
			out.append(name.get_basename())
		name = dir.get_next()
	dir.list_dir_end()
	return out


func test_master_set_is_within_spec_size() -> void:
	# 美術聖經 §8：「20–30 張人工嚴格挑選的定調資產」。
	assert_int(_master.size()).override_failure_message(
		"母本集有 %d 個，規格要求 20–30 個" % _master.size()
	).is_between(20, 30)


func test_every_master_asset_is_shipped() -> void:
	# 方向是「母本 ⊆ 出貨」而不是反過來。母本集是**定調**用的 20–30 張，
	# 出貨資產是第一章全部 33 個——後者本來就多於前者，反過來寫必然失敗。
	# 這條要擋的是：母本集裡的圖被人從 game/assets/ 刪掉或換掉而沒人發現，
	# 因為 A3 會拿母本集去訓 LoRA，屆時檔案必須還在。
	var shipped := _asset_names()
	for asset_id: String in _master:
		assert_bool(shipped.has(asset_id)).override_failure_message(
			"母本集的 %s 不在 game/assets/chapter01/ 裡——A3 訓練 LoRA 時會找不到它" % asset_id
		).is_true()
```

- [ ] **Step 3：執行確認它失敗**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --ignoreHeadlessMode -a res://tests/test_art_master_set.gd
```

預期：`test_master_set_is_within_spec_size` 失敗（尚無 `data/art_master_set.json`，或數量不在 20–30）。

- [ ] **Step 4：處理 33 > 30 的問題**

現有 33 個資產超過規格上限 30。**這是規格與內容規模的真實衝突，必須明確處理而不是改門檻湊數。**

兩個選項，二選一並記錄理由：

- **選項 A**：母本集只收**定調用**的 20–30 個（各類別的代表：3 種塔各一級、5 種敵人、2 種平民、地形貼片、圖示各一），其餘資產不算母本但仍須通過色票與尺寸閘門。Step 2 的測試已依此方向撰寫（母本 ⊆ 出貨），不需修改。
- **選項 B**：提報規格修訂，把 A2 的「20–30 張」放寬到涵蓋第一章全部 33 個資產，理由是第一章的資產種類本來就是 33 種。

**建議選項 A**——規格說母本集是「定調」資產，用途是 A3 訓練 LoRA 的資料集，不是「全部資產」。20–30 張足以定調，全收反而稀釋。

- [ ] **Step 5：執行確認通過**

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --ignoreHeadlessMode -a res://tests
```

預期：`Exit code: 0`，全部測試通過。

- [ ] **Step 6：提交**

```bash
git add tests/test_art_master_set.gd data/art_master_set.json art/scripts/select_masters.py
git commit -m "test(art): 母本集閘門，非母本資產不得進 game/assets/"
```

---

## 完成判準

全部達成才算 A2 通過，才可解除 A5 量產的閘門：

- [ ] 母本集有 20–30 個資產，每個都經過 10 選 1 的人工挑選，選擇記錄在 `art/manifest/master_set.json`
- [ ] `check_lighting.py` 對母本集全部回報 `diagonal > 0`（光源自左上）
- [ ] `batch_stability.py` 對三批的最大 TV 距離已量測並記錄，門檻依實測值訂定
- [ ] 鐵人軍為札甲＋鐵面罩＋赤足，大熕船為中式硬帆的扇形剪影
- [ ] 剪影相似度超過 0.93 的配對不多於 1 對
- [ ] 色票與尺寸兩道 GdUnit4 閘門通過
- [ ] 母本集閘門通過：`game/assets/chapter01/` 的資產都出自母本集
- [ ] `docs/art/A2-master-set.md` 記錄：挑選原則、光源基線、三批距離、門檻依據、選項 A/B 的決定與理由
