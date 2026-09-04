# A0　美術軌環境建置與授權紀錄

- 日期：2026-09-04
- 對應規格：`docs/superpowers/specs/2026-09-04-art-direction-bible.md` §7、§8
- 階段判準（美術聖經 §8）：ComfyUI + SDXL + ControlNet + IP-Adapter 裝好並跑通；基礎模型授權確認並記錄；**能用 §4 的 prompt 規格產出可辨識的圖**

---

## 1. 硬體

| 項目 | 實測值 |
|---|---|
| GPU | NVIDIA GeForce RTX 4060（Ada） |
| VRAM | 8188 MiB |
| 驅動 | 610.88 |
| 系統 | Windows 11 Pro 10.0.26200 |
| C 槽可用空間 | 269 GB（建置前） |

符合美術聖經 §7.3 的預設。SDXL 生成可行；LoRA 訓練（A3）吃緊但可行。

## 2. 目錄配置

| 路徑 | 內容 | 版控 |
|---|---|---|
| `C:\Users\yinya\git\comfyui` | ComfyUI 本體、venv、模型權重 | 不進 git（與遊戲 repo 分離） |
| `guardians_of_formosa/art/workflows/` | API 格式節點圖 JSON | **進 git**——節點圖即管線，必須可重現 |
| `guardians_of_formosa/art/scripts/` | 出圖與後處理腳本 | **進 git** |
| `guardians_of_formosa/art_src/` | AI 生成原圖、中間檔 | 不進 git（美術聖經 §5.2），已在 `.gitignore` |
| `guardians_of_formosa/game/assets/` | 過完後處理的成品 | 進 git，走 LFS |

`art_src/` 子目錄：`01_raw`（生成原圖）→ `02_selected`（10 選 1 挑過的）→ `03_processed`（過完管線的）、`refs`（IP-Adapter 參考圖）、`workflows`（實驗用暫存節點圖）。

## 3. 安裝內容

以 `git clone` + `uv venv` 安裝，不用 portable 包——理由是 A4 的後處理管線同樣是 Python，共用一套工具鏈；且相依可版控。

| 元件 | 版本 |
|---|---|
| ComfyUI | `e80c157`（2026-09-03） |
| Python | 3.12.10（uv venv） |
| PyTorch | 2.11.0+cu128（`torch.cuda.is_available()` = True） |
| transformers | 5.16.1 |
| 自訂節點 | ComfyUI-Manager、ComfyUI_IPAdapter_plus、comfyui_controlnet_aux |

四個自訂節點全部載入成功，共註冊 1007 個節點。

**已知警告**：ComfyUI 提示 `You need pytorch with cu130 or higher to use optimized CUDA operations`，故 `comfy_kitchen` 的 cuda 後端停用、退回 eager。不影響出圖，僅損失部分量化算子加速。**待 A1 若遇效能瓶頸再評估升到 cu130**，現在不動——換 torch 版本有連帶風險，不值得為尚未量測到的問題冒險。

## 4. 模型與授權

**§7.5 要求動手前自行到官方頁面複查。以下為 2026-09-04 的查證結果。**

| 模型 | 檔案 | 大小 | 授權 | 商用 | 查證來源 |
|---|---|---|---|---|---|
| SDXL Base 1.0 | `checkpoints/sd_xl_base_1.0.safetensors` | 6.94 GB | CreativeML Open RAIL++-M | ✅ | huggingface.co/stabilityai/stable-diffusion-xl-base-1.0 |
| SDXL VAE fp16-fix | `vae/sdxl_vae_fp16_fix.safetensors` | 335 MB | MIT | ✅ | huggingface.co/madebyollin/sdxl-vae-fp16-fix |
| ControlNet Union SDXL 1.0 (promax) | `controlnet/controlnet-union-sdxl-1.0-promax.safetensors` | 2.51 GB | Apache 2.0 | ✅ | huggingface.co/xinsir/controlnet-union-sdxl-1.0 |
| IP-Adapter Plus SDXL | `ipadapter/ip-adapter-plus_sdxl_vit-h.safetensors` | 848 MB | Apache 2.0 | ✅ | huggingface.co/h94/IP-Adapter |
| CLIP-ViT-H-14 image encoder | `clip_vision/CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors` | 2.53 GB | Apache 2.0 | ✅ | huggingface.co/h94/IP-Adapter |

合計約 13.2 GB。

### 4.1 授權結論

**本作散布的是產出的圖，不是模型本身。** RAIL++-M 的第 5 節使用限制（Attachment A）只在「散布模型或其衍生模型」時必須隨附傳遞——遊戲上架 Steam 散布的是 PNG 資產，不觸發這項義務。授權對本專案的實質約束只有兩點：

1. **我們自己的使用**仍受 Attachment A 拘束（不得用於違法、騷擾、生成醫療建議等）。本作為歷史題材塔防，不涉及。
2. Stability 對產出物不主張權利，故資產著作權歸本專案。

### 4.2 尚未觸發但將來要複查的項目

- **社群微調模型**：本階段刻意只裝 SDXL Base，授權最乾淨。A1 若引入 Civitai 等社群模型，**須逐一確認授權，不得假設繼承基礎模型條款**（§7.5）。
- **LoRA（A3）**：以自有母本集訓練，產物授權歸本專案；但底模仍為 SDXL，結論同 §4.1。
- **不使用 Flux**：`[dev]` 非商用直接出局；`[schnell]` 雖 Apache 2.0，但 8GB 需量化且品質不及 SDXL 生態（§7.3）。

### 4.3 ControlNet 為何選 Union 而非分開的 depth / openpose

美術聖經 §7.4 的幀間連貫流程要 Blender 粗模輸出 depth pass 走 ControlNet，同時也可能需要 openpose。Union promax 一個 2.5GB 檔涵蓋 depth、openpose、canny、lineart、scribble、seg 等十餘種控制，且支援多條件並用（openpose + depth）——在 8GB VRAM 上只載一個 ControlNet 比載兩個省得多。授權 Apache 2.0，比逐個下載的 diffusers ControlNet 乾淨。

## 5. 啟動與出圖

```bash
# 啟動 ComfyUI（Web UI 在 http://127.0.0.1:8188）
cd /c/Users/yinya/git/comfyui && .venv/Scripts/python.exe main.py

# 另開一個 shell，把節點圖送進去出圖
cd /c/Users/yinya/git/guardians_of_formosa
python art/scripts/run_workflow.py art/workflows/a0_smoke_test.api.json
```

`--seed` 可覆寫。注意美術聖經 §7.4 已明確指出**固定 seed 無法保證幀間是同一個角色**，seed 只在其他條件完全不變時才有意義。

## 6. A0 驗收

判準（美術聖經 §8）：**能用 §4 的 prompt 規格產出可辨識的圖**。

| 檢查 | 結果 |
|---|---|
| ComfyUI 啟動、API 可用 | ✅ `/system_stats` HTTP 200 |
| SDXL / VAE / ControlNet / IP-Adapter / CLIP-Vision 全被辨識 | ✅ 五個模型皆出現在對應 loader 的下拉選單 |
| 用 §4 prompt 規格出圖 | ✅ 見 `art_src/02_selected/a0_acceptance_zheng_musketeer.png` |
| 出圖速度 | 1024² 單張 30 步約 32 秒；832×1216 batch 4 約 80 秒 |
| VRAM | 8GB 足夠，未 OOM |

驗收圖為鄭軍銃卒：東亞臉孔、明制赭紅號衣、笠形盔、赤足、未畫成辮髮——§4.3 的專屬負面詞有效。色票的赭紅與墨綠確實落地。

### 6.1 過程中修正的 prompt 順序問題

§4.1 把 200 餘字的固定風格區塊放在最前面，實測會**把後面的主體與構圖描述稀釋掉**：首次出圖得到的是半身、兩個人、灰底的插畫版畫，火繩槍完全沒出現。

有效的順序是**構圖 → 主體 → 風格 → 色票 → 比例**，且「full body, head to toe fully visible」必須是整段 prompt 的第一句。這一點應回填 §4.1。

### 6.2 A0 通過，但暴露了一個 A1 必須先解決的問題

**SDXL Base 1.0 產不出膠彩顆粒質感，也產不出美術聖經要的手繪抖動線描。** 加了 cartoon 相關詞之後，它收斂到的是**平塗向量風**——而這正是 §1.1 明列要與 Kingdom Rush 區隔的第二項（「向量平塗 + 硬邊漸層」）。

另一個穩定的失敗模式是：只要 prompt 出現 game character sprite 一類詞，SDXL 有很強的先驗會產出**角色設定表**（轉面圖 + 道具標註 + 假中文字），batch 4 裡有 3 張如此，加負面詞壓不掉。

這與 §7.2 原本寫的「SDXL **系風格模型**」一致——原規格指的就是風格微調模型，而非裸的 base。A0 為了授權乾淨刻意只裝 base，這個取捨現在有了實測代價。**A1 開始前需要決定**：引入社群風格微調模型（須逐一確認授權，§7.5），或改以少量人工定調圖提早走 IP-Adapter 參考圖條件生成。裸 base 打不出美術聖經的風格。

## 7. 下一步（A1）

A1 要出 3–5 張風格試片（一個單位、一個塔、一小塊場景），並對美術聖經 §6 的四項待決策事項給出實測答案。其中最該先做的是第 1 項：**膠彩顆粒質感在 128×128 下是否還看得出來**——因為答案若是否定的，角色要改走純線描平塗，整套 prompt 規格要改。這一張圖應該在畫任何其他東西之前先做。
