# 美術設計規格（Art Bible）— 第一章：熱蘭遮 1661

- 日期：2026-09-04
- 狀態：草案，待確認
- 對應規格：`2026-09-04-chapter-01-zeelandia-design.md`、`2026-09-04-tower-defense-architecture-design.md`
- 用途：AI 生成美術的風格憲法與 prompt 規格書

---

## 0. 一個必須先處理的問題：「地方色彩」是誰的眼睛

郭雪湖、陳澄波、李石樵活躍的年代，台灣畫壇的主流審美是**「地方色彩」（ローカルカラー／南國色彩）**——1927 年台展設立後成為官方展覽的主流意識形態。

**但這個框架本身是殖民視線的產物。** 所謂「台灣特色」的內容——熱帶風景、芭蕉、水牛、媽祖廟、原住民——很大程度出自日本審查員對殖民地的異國情調想像，是「帝國視線」為台灣規定的長相。

**這對本專案是直接的矛盾。** 第一章的敘事立場（章節規格 §0）明確站在被統治者這一邊，若美術照搬「地方色彩」的取景邏輯，等於用一套殖民凝視去畫一個反殖民凝視的故事。

### 0.1 處理方式

**取這三位畫家的技法與色彩語彙，不取帝國視線的取景邏輯。**

具體界線：

| 取 | 不取 |
|---|---|
| 郭雪湖的綿密線描與滿版構圖 | 把原住民、水牛、芭蕉當作「風情」擺設的取景 |
| 陳澄波的粗獷筆觸與紅綠冷暖對比 | 為了「南國感」而濫用的熱帶符號堆疊 |
| 李石樵的人物量感與群像結構 | 把庶民畫成田園牧歌式的無害背景 |
| 三人共有的亞熱帶強光與濃綠土赭色域 | 「異國情調」的觀光明信片視角 |

**判準很簡單：畫面裡的人是行動者，還是被觀看的風景？** 本作一律取前者。這也正好呼應李石樵所認同的「民眾美術」立場——美術應該屬於民眾。

---

## 1. 風格定位

> **膠彩的線與色 × 後印象的筆觸與光，經卡通化壓縮至 128 像素仍可辨識。**

三位畫家各自負責不同層級，不是把三種風格攪在一起：

| 畫家 | 貢獻層級 | 具體特徵 |
|---|---|---|
| **郭雪湖** | **建築與地圖** | 綿密線條取代皴擦筆法；平面化裝飾性；俯視構圖；《南街殷賑》式的滿版密度——招牌、人群、店面層層堆疊，遠景仍保有細節 |
| **陳澄波** | **場景色彩與光** | 短而有力、近似梵谷的直率扭曲筆觸；紅綠暖冷強對比；紅瓦屋頂以深淺紅褐勾勒，牆面橘紅磚或白粉牆，樹叢連綿翠綠；高地平線的俯瞰構圖 |
| **李石樵** | **角色造型** | 人物群像的結實量感；精確的骨架與明暗對比；冷理性的構圖；造型簡化但不失重量 |

### 1.1 與 Kingdom Rush 的區隔

架構規格 §1 明確要求「風格需明確區隔於 Kingdom Rush」。以下六項為**硬性區隔點**，任一項失守即失去辨識度：

| 面向 | Kingdom Rush | 本作 |
|---|---|---|
| **輪廓線** | 粗黑描邊，粗細均勻 | **彩色描邊**（深赭 `#3A2A22`／墨綠 `#1E4029`），粗細有變化，帶手繪抖動 |
| **上色** | 向量平塗 + 硬邊漸層 | **膠彩質感**：可見礦物顆粒、色層堆疊、邊緣微暈 |
| **色相** | 高彩度全色相，藍紫奇幻 | **限定色域**：赭紅／濃綠／土黃／靛青。無螢光、無紫紅 |
| **光源** | 強 rim light，戲劇打光 | **亞熱帶正午的高強度平光**，短而硬的投影 |
| **頭身比** | 2–3 頭身，圓潤可愛 | **3.5–4 頭身**，肩背結實，帶李石樵的量感 |
| **背景** | 舞台化，景深模糊 | **郭雪湖式滿版密度**，遠景不虛化 |

---

## 2. 色票

全遊戲共用一組限定色域。**任何資產不得引入色票外的色相**——這是限定調色盤能撐起風格統一的唯一保證，尤其在 AI 生成的情況下。

### 2.1 主色域

| 角色 | 名稱 | Hex | 用途 |
|---|---|---|---|
| 主色一 | 紅瓦赭 | `#B5442E` | 屋瓦、鄭軍號衣、警示 |
| 主色一暗 | 深赭 | `#8C3A22` | 陰影、描邊 |
| 主色二 | 榕蔭綠 | `#2F5B3A` | 樹叢、描邊、UI 底 |
| 主色二暗 | 墨綠 | `#1E4029` | 深陰影、夜景 |
| 主色二亮 | 翠綠 | `#5C8A4A` | 受光植被 |
| 中性一 | 沙洲黃 | `#C9A96B` | 沙洲、地面 |
| 中性一亮 | 曝曬沙 | `#D9C08E` | 強光地面 |
| 中性二 | 蚵殼灰 | `#E8DCC6` | 城牆三合土、粉牆 |
| 冷色 | 台江靛 | `#2C5470` | 水體（低潮） |
| 冷色亮 | 潮水青 | `#3E7A94` | 水體（高潮）、水花 |
| 強調 | 藤黃 | `#E0A93B` | 資源、金錢、可互動提示 |
| 強調 | 硃砂 | `#A8332B` | 明鄭旗幟、危險 |
| 線稿 | 焦茶 | `#3A2A22` | 主描邊 |

### 2.2 陣營識別色

依章節規格 §3.4 的剪影規格，各陣營在 128px 下靠**剪影 + 一個識別色塊**辨識：

| 陣營 | 識別色 | 位置 |
|---|---|---|
| VOC | 米白 `#E8DCC6` | 胸前斜掛彈藥帶的橫線 |
| 鄭軍 | 硃砂 `#A8332B` | 號衣軀幹 |
| 鐵人軍 | 鐵灰 `#5A5A5E` | 全身（無亮色） |
| 西拉雅 | 鹿皮褐 `#A87545` | 腰際與長鏢 |
| 島上的人（玩家塔） | 藤黃 `#E0A93B` | 一律有一塊藤黃 |

**最後一項是機制與美術的接點**：玩家的塔全都帶藤黃，敵人一律沒有。這讓「塔＝島上的人」（章節規格 §0.2 決定一）在視覺上直接成立——當來襲方更換陣營時，玩家一眼看得出自己的人沒變。

### 2.3 潮汐的色彩表現（1-1 核心機制）

潮位變化必須在**不看 HUD 的情況下**就能感覺到。做法是全場景色溫位移：

| 潮位 | 水色 | 沙洲 | 整體 |
|---|---|---|---|
| 低潮 | 台江靛 `#2C5470`，露出大片濕沙 | 曝曬沙 `#D9C08E` | 暖、乾、亮 |
| 漲潮中 | 過渡 | 濕潤加深 | 逐步降溫 |
| 高潮 | 潮水青 `#3E7A94` 覆蓋淺灘 | 沙洲面積顯著縮減 | 冷、濕、水面反光增強 |

---

## 3. 角色設計規格

技術上限依架構規格 §4.7：**單一敵人貼圖 ≤ 128×128，單一動作 6–8 幀**。

### 3.1 玩家方（塔＝島上的人）

| 單位 | 頭身 | 剪影關鍵 | 主色 | 道具 | 動作 |
|---|---|---|---|---|---|
| **銃樓** 火繩槍手 | 4 | 寬邊帽 + 胸前彈藥帶橫線 + 長槍斜舉 | 米白／焦茶 + 藤黃臂章 | 火繩槍、木製藥管×12、燃燒的火繩（**發光點，重要辨識**） | 待機/裝填/射擊 各 6 幀 |
| **銃樓** 排槍齊射 | 4 | 三人並列剪影 | 同上 | 三支槍錯開高度 | 同上 |
| **獵寮** 新港社鏢手 | 4 | 裸身修長 + 長鏢斜持過肩 | 鹿皮褐 + 藤黃腕飾 | 竹柄鐵鏃長鏢（五尺餘，**應明顯長於身高一半**）、束髮、耳飾 | 待機/擲鏢 各 6 幀 |
| **獵寮** 鹿陷阱 | — | 地面裝置 | 沙洲黃 | 竹製、鹿骨標記 | 待機 4 幀 / 觸發 8 幀 |
| **柵欄** 大員街民壯丁 | 3.5 | 矮壯 + 刀盾 | 靛藍短褂 + 藤黃腰帶 | 竹柵、腰刀、藤牌 | 待機/揮砍/受擊 各 6 幀 |
| **稜堡砲位** | — | 稜堡角的斜面剪影 | 蚵殼灰 | 24 磅前膛砲、砲車、彈堆 | 待機 4 幀 / 開火 8 幀 |
| **平民撤離單位** | 3.5 | 背包袱、彎腰、小孩牽手 | 雜色低彩度 | 包袱、竹籃、幼兒 | 行走 6 幀 |

**平民單位的設計要點**：他們是玩家真正在守的東西（章節規格 §4.6），必須**一眼看出是平民而非兵**——彎腰、負重、步伐慢、沒有任何武器輪廓。族群混雜：漢人、西拉雅、VOC 奴工都要有。

### 3.2 鄭軍（第一章敵方）

| 單位 | 頭身 | 剪影關鍵 | 主色 | 道具 |
|---|---|---|---|---|
| **銃卒** | 4 | 笠形盔三角剪影 + 赤足 | 硃砂號衣 | 鳥銃、布纏腿 |
| **藤牌兵** | 3.5 | 低姿前傾 + 圓盾佔剪影三分之一 | 硃砂 + 藤黃盾面 | 藤牌、腰刀、赤足 |
| **弓箭手** | 4 | 拉滿弓的三角張力 | 深藍號衣 | 明式角弓、箭壺 |
| **鐵人** | 4 | **全包覆的厚重方形剪影** + 過肩長刀 | 鐵灰（無亮色） | 全身鐵甲、鐵面罩、斬馬刀、**赤足** |
| **掘壕隊** | 3.5 | 扛工具、無武器 | 土黃 | 鋤、籃、土袋 |
| **大熕船** | — | 中式硬帆的扇形剪影 | 焦茶 + 硃砂旗 | 側舷砲門、明字旗 |
| **陳澤**（Boss） | 4.5 | 盔纓 + 披風 | 硃砂 + 金 | 明制山文甲、指揮旗 |

> **鐵人的赤足是關鍵設計點**：全身鐵甲卻赤腳，是荷方紀錄特別提到的視覺特徵，也是本作最容易被記住的一個角色設計。**不要讓 AI 幫它加靴子。**

### 3.3 VOC

| 單位 | 頭身 | 剪影關鍵 | 主色 |
|---|---|---|---|
| 火槍手 | 4 | 寬邊帽 + 彈藥帶 | 米白／暗紅 |
| 砲手 | 3.5 | 無帽、捲袖、通條 | 米白 |
| 揆一 | 4 | 黑衣白翻領的方形肩線 | 黑／白 |
| **奴工** | 3.5 | 纏腰布、赤裸上身、負重 | 深褐膚色 |

> **奴工必須出現。** 城內 547 名奴隸是荷蘭殖民地的真實構成（章節規格 §2.5）。把 VOC 畫成純歐洲人前哨是美化殖民地。

### 3.4 西拉雅

| 單位 | 剪影關鍵 | 道具 |
|---|---|---|
| 鏢手 | 裸身修長 + 長鏢 | 竹柄鐵鏃鏢、竹弓 |
| **頭目** | 立姿 + **手持藤杖** | **VOC 頒發的藤杖，銀質杖頭刻公司徽記** |
| 女性 | 短衣圍裙 | 織籃 |

> **藤杖是全章最重要的單一道具。** 它是 1636 年起「地方會議」制度的權力信物，也是荷蘭間接統治的具象化——一根由殖民者發給的權杖。它應該在過場中被特寫至少一次，並在 1662 年鄭氏接管後，出現同一個頭目手上換成另一種信物的畫面。

---

## 4. AI 生成 Prompt 規格

圖像模型對英文的反應顯著優於中文，故 prompt 以英文撰寫。

### 4.1 固定風格區塊（每張圖都要前置）

```
2D hand-painted game sprite, full body, 3/4 front view, centered,
transparent background.

STYLE: Taiwanese colonial-era painting adapted to cartoon. Gouache /
nihonga (膠彩) mineral pigment texture with visible granulation.
Dense fine linework in dark umber and deep green — NOT black outlines,
line weight varies, slight hand-drawn wobble. Flat decorative color
fields with subtle layered washes. Short bold brushstrokes.
Strong warm-cool complementary contrast: terracotta red against deep
jade green. Harsh subtropical noon light, short hard shadows.
Earthy restrained palette.

PALETTE (strict): #B5442E terracotta, #8C3A22 deep ochre,
#2F5B3A banyan green, #1E4029 ink green, #C9A96B sand,
#E8DCC6 oyster-lime white, #2C5470 indigo, #E0A93B gamboge yellow,
#3A2A22 burnt umber linework.

PROPORTIONS: 4 heads tall, solid weighty build, clear shoulder mass,
readable silhouette at 128 pixels.
```

### 4.2 通用負面 prompt

```
chibi, 2-head-tall proportions, thick uniform black outline,
vector flat cel shading, glossy plastic rendering, rim lighting,
anime, manga, western fantasy, Kingdom Rush style, neon colors,
purple, magenta, teal, pastel, blurred background, bokeh,
photorealism, 3D render, watermark, text
```

### 4.3 各陣營的專屬負面 prompt

**這一節是本規格投報率最高的部分。** AI 對 17 世紀東亞的預設輸出錯誤率極高，且錯誤都集中在固定幾處。

| 陣營 | 必加負面詞 | 原因 |
|---|---|---|
| **鄭軍** | `queue hairstyle, braid, shaved forehead, Qing dynasty uniform, samurai armor, ashigaru, boots` | 辮髮是清制——鄭軍恰恰是反清的一方，畫成辮子是史實硬傷。且鄭軍赤足 |
| **VOC** | `full plate armor, cuirassier, morion helmet, breastplate, matching uniform, winter wool coat, musketeer tabard` | 1661 年板甲與莫里恩盔已過時；VOC 在亞洲無制式軍服；此地是亞熱帶 |
| **西拉雅** | `feather headdress, native american, war paint, tribal mask, Polynesian tattoo, generic tribal` | 羽毛頭飾是北美刻板印象；亦須避免套用泰雅、排灣等其他族群紋樣 |

### 4.4 主體區塊範例

**鄭軍銃卒**
```
A 17th-century Ming loyalist musketeer of Koxinga's army. Conical
lacquered iron helmet, vermillion Ming-style military tunic, cloth
leg wraps, BARE FEET. Holds a matchlock arquebus. Hair tied in a
topknot under the helmet, NOT braided.
```

**鐵人**
```
A 17th-century Ming loyalist heavy infantryman. Fully enclosed iron
lamellar armor covering torso, arms and legs, iron face mask.
Enormous two-handed horse-cutting sabre over the shoulder.
Rattan shield on back. BARE FEET despite the heavy armor.
Bulky rectangular silhouette, iron grey, no bright colors.
```

**新港社鏢手**
```
A Siraya hunter of 17th-century Formosa. Lean athletic build, bare
torso, deerskin wrap at the waist, no shoes, no hat. Hair tied up,
simple shell ear ornaments. Holds a long bamboo-shafted javelin with
an iron head, longer than half his body height, carried over the
shoulder. Calm, alert, upright posture.
```

**VOC 火槍手**
```
A Dutch East India Company soldier in tropical Formosa, 1661. Loose
worn linen shirt, knee breeches, wide-brimmed felt hat, leather
shoes. Bandolier across the chest with twelve wooden powder
containers. Matchlock musket with a visibly lit glowing slow match.
Sun-worn, mismatched, no uniform.
```

**西拉雅頭目（關鍵道具）**
```
A Siraya village elder of 17th-century Formosa holding a rattan staff
of office with an engraved silver head bearing a Dutch East India
Company monogram. Bare torso, deerskin wrap, dignified upright
stance. The staff is the visual focus.
```

### 4.5 場景 prompt（1-1 鹿耳門）

```
Top-down 3/4 isometric tower defense battle map. Two sandbars
enclosing a shallow lagoon in 17th-century Formosa. A Dutch bastioned
brick fort with oyster-lime mortar walls on the southern sandbar.
Dense grid of tiled-roof shophouses. Deep green banyan and bamboo
clumps. Shallow water channels in indigo.

STYLE: painted like Kuo Hsueh-hu's dense decorative gouache
cityscapes crossed with Chen Cheng-po's thick warm-cool
post-impressionist brushwork. High horizon, bird's-eye view.
Every area keeps detail — NO depth-of-field blur.
```

---

## 5. 技術規格與產線

### 5.1 產出規格

| 項目 | 規格 |
|---|---|
| 敵人／士兵貼圖 | ≤ 128×128 |
| 單一動作幀數 | 6–8 |
| 塔（含底座） | ≤ 192×192 |
| 輸出格式 | PNG 帶 alpha，打包進 Sprite Atlas |
| 色彩 | sRGB，**必須通過色票檢查** |

### 5.2 產線與版控

依架構規格 §8.2：

- `art_src/` — AI 生成原始檔、修圖中間檔。**不進 git**，本地 + 雲端備份
- `game/assets/` — 已裁切壓縮的圖集。進 git，走 LFS

### 5.3 建議增加的自動化檢查

架構規格 §5.3 已有資料完整性測試。建議在同一支測試中**加入色票驗證**：掃描 `game/assets/` 的 PNG，若出現色票外的色相（容差內），測試失敗。

理由與資料完整性測試相同——AI 生成的資產風格漂移是必然發生的，而人眼在單張圖上看不出漂移，要到十幾張放在一起才發現。此時已經產出一批廢圖。自動檢查把這個回饋迴圈從「幾週」縮短到「一次 CI」。

---

## 6. 待決策事項

1. **膠彩顆粒質感在 128×128 下是否還看得出來。** 若看不出，質感只能靠場景與 UI 大圖承載，角色改走純線描平塗。**建議 M1 先做一張實測再決定**，不要等三十隻敵人畫完。
2. **描邊用彩色是否會在複雜背景上損失可讀性。** 郭雪湖式的滿版背景密度高，彩色描邊可能糊在一起。備案是角色保留一圈極細的外輪廓光（非 rim light，而是淺一階的同色系描邊）。
3. **陳澄波的粗筆觸與 6–8 幀逐格動畫的相容性。** 筆觸位置若每幀跳動，動起來會有雜訊感。可能需要規定「筆觸紋理固定不動，只有形狀變化」。
4. **1-1 的潮汐色溫位移要做成即時 shader 還是兩套貼圖。** 前者省記憶體但需寫 shader；後者簡單但貼圖翻倍。與架構規格 §4.7 的記憶體風險直接相關，應併入 M2 實機驗證。
