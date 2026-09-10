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
| **上色** | 向量平塗 + 硬邊漸層 | **簡化卡通平塗**：大面積平色、每色至多兩階明暗、無漸層 |
| **色相** | 高彩度全色相，藍紫奇幻 | **限定色域**：赭紅／濃綠／土黃／靛青。無螢光、無紫紅 |
| **光源** | 強 rim light，戲劇打光 | **亞熱帶正午的高強度平光**，短而硬的投影 |
| **頭身比** | 2–3 頭身，圓潤可愛 | **3.5–4 頭身**，肩背結實，帶李石樵的量感 |
| **背景** | 舞台化，景深模糊 | **郭雪湖式滿版密度**，遠景不虛化 |

> **2026-09-09 修訂：戰場單位、對話肖像、UI 圖示統一改為「扁平幾何、無五官」。**
>
> 依 `docs/art/A2x-shadow-puppet-experiment.md` §5 實測（四張肖像 + 一張全身，Klein 純文字一次到位）決定。要點：
> - **形**：扁平多邊形色塊，無描邊（管線描邊仍加，寬度 1）、無漸層、無材質；每個物件兩到三階平色。
> - **光**：左亮右暗的**垂直分光線**取代陰影——這是 §L2「光源自左上」的幾何化執行，`check_lighting.py` 的不一致問題結構上消失。
> - **臉**：一整塊膚色平面，無眼、無口、無鼻。四階膚色因此成為肖像上最大的視覺元素，§2.5 的敘事要求在美術上最清楚的落實。**無五官必須一視同仁**——揆一、陳澤、奴工全都沒有臉；一旦出現「歐洲人有五官、其他人沒有」的差別，§0 的判準就破了。
> - **動畫**：平面色塊最適合分件（架構規格 §4.7 修訂），與逐格路線亦相容。
> - **辨識度**：此風格與 Reigns 系卡牌肖像相近，靠色票、帽盔形制（笠形盔、寬邊氈帽、白翻領）、分光方向與紙紋背景拉開，不靠五官。
>
> 與 Kingdom Rush 的區隔點因此再減一項（彩色描邊變為極細），改由**無五官、分光線、限定色域、滿版地圖密度**承擔。實作：`art/manifest/chapter01_assets.json` 的 `shared.style` 與 `style_by_cat.unit`；舊的平塗卡通描述保留在 `_style_history`。

> **2026-09-04 修訂：「上色」一列原為「膠彩質感：可見礦物顆粒、色層堆疊、邊緣微暈」，改為簡化卡通平塗。**
>
> 這一項與 Kingdom Rush 的區隔因此變弱——兩者都是平塗。**其餘五項全部保留**，辨識度改由彩色描邊、限定色域、亞熱帶左上平光、3.5–4 頭身、滿版背景密度承擔。
>
> 改動理由有二。其一是產線現實：A1 實測顯示 SDXL 產不出可信的膠彩顆粒，加了 cartoon 相關詞就會收斂到平塗，硬要膠彩只會得到不穩定的假質感。其二是尺度：本作單位貼圖 ≤128×128，礦物顆粒在此尺寸下本來就會被縮掉——這正是 §6 待決策第 1 項要問的事。
>
> **必須誠實記錄：這等於繞過該題而非回答它。** 若日後恢復膠彩路線（例如只用在場景與 UI 大圖），該題仍待實測。詳見 `docs/art/A1-findings.md` §6。

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
| 強調暗 | 硃砂暗 | `#7A2A24` | 硃砂的陰影階。**2026-09-08 補**：色票原本沒有暗的紅，量化時陰影紅一律掉到深赭（褐），號衣在 128px 上讀成褐色，陣營識別色消失（`docs/art/A2x` §2.2、§6.3 三次實測） |
| 線稿 | 焦茶 | `#3A2A22` | 主描邊 |

**唯一的例外：膚色。**

| 角色 | 名稱 | Hex | 用途 |
|---|---|---|---|
| 膚色一 | 淺膚 | `#F2D6B8` | VOC 歐洲人 |
| 膚色二 | 中膚 | `#D9A97E` | 漢人、鄭軍 |
| 膚色三 | 深膚 | `#A87545` | 西拉雅（與鹿皮褐同值） |
| 膚色四 | 極深膚 | `#6B472E` | VOC 奴工（東南亞、南印度來源） |

本節開頭說「任何資產不得引入色票外的色相」。**膚色是必要的例外**——後處理管線的色票量化若把人臉映射到赭紅或沙洲黃，那不是風格化，是壞掉。

四階的分野同時承擔章節規格 §2.5 與 §3.3 的敘事要求：城內 547 名奴隸不是背景，把 VOC 畫成純歐洲人前哨是美化殖民地，膚色分階是這件事在美術上的最低限度落實。

實作見 `art/scripts/postprocess.py` 的 `SKIN` 常數。

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

> **2026-09-05 補充：本規則凌駕 §3 各表的逐一單位配色。**
>
> 原 §3.2 給藤牌兵「藤黃盾面」，與本節牴觸。實作時依本節處理——藤牌改為自然藤色（近沙洲黃 `#C9A96B`），陳澤的「金」取青銅金而非藤黃 `#E0A93B`。
>
> 理由：藤黃在本作**不是裝飾色，是陣營標記**。一旦敵方也有，「玩家一眼看得出自己的人沒變」這個機制就失效了，而那是 §0.2 決定一的視覺載體。逐一單位的配色可以讓步，這條不行。
>
> 實作補充：藤黃寫在 prompt 的主體描述句尾**不會被畫出來**，必須獨立成一段 `FACTION MARK:`。見 `docs/art/A1-findings.md` §11。

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
| **藤牌兵** | 3.5 | 低姿前傾 + 圓盾佔剪影三分之一 | 硃砂 + **自然藤色**盾面 | 藤牌、腰刀、赤足 |
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

### 4.1 Prompt 的段落順序（比措辭更重要）

**順序固定為：構圖 → 主體 → 風格 → 色票 → 比例。**

本節原本把風格區塊放在最前面，A1 實測證實這是錯的：200 餘字的風格描述擺在句首會**稀釋掉後面的主體與構圖**，首次出圖得到的是半身、兩個人、灰底的插畫版畫，指定的火繩槍完全沒出現。

**`full body, head to toe fully visible` 必須是整段 prompt 的第一句。**

實際組裝已改為資料驅動，見 `art/manifest/chapter01_assets.json`（風格與色票共用、主體逐資產、構圖與比例依類別）。下方為風格與色票區塊的當前內容，**修改應改清單而非改此處**，否則兩邊會漂開。

```
STYLE: simple flat cartoon game art, clean bold simplified shapes,
minimal internal detail, large readable areas of flat color, simple
shading with at most two tones per color, colored linework in dark
umber and deep green instead of black with slightly varying line
weight, strong warm-cool contrast of terracotta red against deep jade
green, light from the upper left with one short hard cast shadow.

PALETTE (strict): #B5442E terracotta, #8C3A22 deep ochre,
#2F5B3A banyan green, #1E4029 ink green, #C9A96B sand,
#E8DCC6 oyster-lime white, #2C5470 indigo, #E0A93B gamboge yellow,
#3A2A22 burnt umber linework.

PROPORTIONS: 4 heads tall, sturdy simplified build, clear shoulder
mass, bold readable silhouette at 128 pixels.
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

> **A1 實測補充：負面詞能趕走錯的答案，叫不出模型沒有的答案。**
>
> SDXL Base 沒有 17 世紀明鄭／西拉雅／亞洲 VOC 的服飾知識。缺乏知識時它退回一個泛用的「前現代非歐洲士兵」先驗，而**該先驗的落點會隨措辭漂移**：第一輪全部落在日本（和服、木屐、浮世繪），加了 `japanese, kimono, ronin, samurai, geta sandals, ukiyo-e` 之後日本消失了，**但換成波斯與中亞，不是換成明鄭**。
>
> 因此下表的負面詞是必要的，但在 SDXL 上**不足以產出正確的單位**。這是純文字 prompt 在 SDXL 上的硬上限。
>
> **2026-09-05 補充：換用 FLUX.2 Klein 4B 後此上限消失。** 同樣的 prompt、無參考圖、無 ControlNet，六張中五張服飾正確且全部赤足。**知識缺口是模型問題，不是提示詞問題**——換掉模型比補救提示詞有效得多。下表負面詞仍保留（成本為零、仍有防呆價值），但不再是關鍵。見 `docs/art/A1-findings.md` §8。

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

1. ~~**膠彩顆粒質感在 128×128 下是否還看得出來。**~~ **已繞過，非已回答。** 2026-09-04 改為簡化卡通平塗（見 §1.1 修訂註）。此題若要恢復膠彩路線（例如只用於場景與 UI 大圖）仍須實測。
2. **描邊用彩色是否會在複雜背景上損失可讀性。** 郭雪湖式的滿版背景密度高，彩色描邊可能糊在一起。備案是角色保留一圈極細的外輪廓光（非 rim light，而是淺一階的同色系描邊）。
3. **陳澄波的粗筆觸與 6–8 幀逐格動畫的相容性。** 筆觸位置若每幀跳動，動起來會有雜訊感。可能需要規定「筆觸紋理固定不動，只有形狀變化」。
4. ~~**1-1 的潮汐色溫位移要做成即時 shader 還是兩套貼圖。**~~ **2026-09-09 解掉，兩者都不用。** 地圖改為 TileMap 後，潮位變化＝換 `map.json` 指定的潮間帶格子（`GroundLayer.set_tide_high`），只重繪那幾格，沒有 shader 幀率成本，也沒有雙貼圖記憶體。全場景色溫位移若日後仍要，用 `paper_overlay` 的 `paper_tint` 參數即可。

---

## 7. 工具鏈與硬體

### 7.1 為何是本地 ComfyUI，而不是 Midjourney

§4 的 prompt 規格與 `visual-polish-pipeline.md` §2 的對策清單，其實已經隱含了工具需求：

| 已決定的做法 | 所需能力 | 排除了誰 |
|---|---|---|
| 一律用參考圖條件生成，不用純文字 | IP-Adapter 等參考圖條件機制 | Midjourney（`--sref` 控制力不足） |
| 母本集穩定後訓練 LoRA | 本地 LoRA 訓練 | 所有閉源雲端服務 |
| 後處理是一支腳本，不是手工 | 可程式化、可重現的管線 | 一切純 GUI 工具 |
| 零成本 | 免費且無訂閱 | Midjourney、Scenario |

四項合起來只剩一個答案。**這條推論要寫下來，否則日後容易被「Midjourney 出圖比較漂亮」動搖**——單張漂亮不是本專案的瓶頸，一致性才是。

### 7.2 工具清單

| 用途 | 工具 | 備註 |
|---|---|---|
| 生成主體 | ComfyUI + SDXL 系風格模型 | 節點圖本身就是可重現的管線 |
| 風格鎖定 | kohya_ss 訓 LoRA | 本地、零成本 |
| 參考圖條件 | IP-Adapter | 取代純文字 prompt，直接壓制漂移 |
| 姿勢與構圖控制 | ControlNet（depth / openpose） | 接 3D 粗模的輸出，見 §7.4 |
| 3D 粗模 | Blender | 解決幀間連貫，見 §7.4 |
| 局部修圖 | Krita + krita-ai-diffusion | 局部重繪比全圖重生成安全 |
| 後處理管線 | Python + Pillow / NumPy | 去背、色票量化、統一描邊、剪影檢查 |

### 7.3 硬體與其限制

本機為 **NVIDIA RTX 4060、8GB VRAM**（Ada）。由此得出的約束：

- **SDXL 生成可行**，速度足以支撐「大量生成、10 選 1」的策略
- **LoRA 訓練吃緊但可行**：768px + gradient checkpointing + 8-bit Adam + batch size 1，25–30 張的風格 LoRA 約需數小時
- ~~**不使用 Flux**。~~ **2026-09-05 修訂：改用 FLUX.2 Klein 4B 為主力。** 原判斷（`[dev]` 非商用、`[schnell]` 品質不足）在 FLUX.2 世代兩項都不成立——Klein 4B 為 **Apache 2.0**、7.22 GB 可在 8GB VRAM 上跑、768×1024 20 步 batch 2 約 54 秒。
  **關鍵是它解決了 SDXL 解決不了的事**：SDXL 沒有 17 世紀明鄭與西拉雅的服飾知識，兩輪加兩階段共 70 餘張單位可用數為 0；FLUX.2 純文字 prompt、無參考圖、無 ControlNet，六張中五張可用，且全部赤足（§3.2 的關鍵設計點）。剪影相似度也從 38 對超標降到 0 對。完整實測見 `docs/art/A1-findings.md` §8。
  SDXL 生態（ControlNet Union、IP-Adapter、風格 LoRA）仍保留，用於姿勢控制與日後的動作序列

一個尺度上的觀察：本作單位貼圖僅 ≤128×128、塔 ≤192×192，用 1024 生成再縮到 128 會丟掉約 98% 的像素，**SDXL 相對於較小模型的細節優勢在單位貼圖上幾乎不存在**。優勢主要體現在場景與 UI 大圖。因此不需為了單位貼圖追求更高解析度的模型。

### 7.4 幀間連貫：先做 3D 粗模

`visual-polish-pipeline.md` §2 第 4 點原本寫「同一單位的多個動作固定 seed，確保各幀之間是同一個角色」。**這個做法無效**：改變 prompt 或姿勢後，同一個 seed 產出的仍是不同角色——衣服細節、配件位置、臉都會跳。這是逐格動畫路線最大的技術風險。

可靠的解法是讓幀與幀之間共用**同一份幾何**：

```
Blender 粗模（不需精緻，體積與比例對即可）
  → 擺姿勢，輸出 6–8 幀序列（同時輸出 depth pass 供 ControlNet 使用）
  → 每幀 img2img 低重繪幅度 + 風格 LoRA + IP-Adapter 參考圖
  → §5 的後處理管線
```

幾何連貫，故幀間必然連貫。附帶好處：3D 粗模是可以綁骨的，若日後想推翻「不做骨骼動畫」的決定，路是通的，不必從頭來過。

> **2026-09-08 修訂：Blender 粗模路線撤回，改用 FLUX.2 Klein 參考圖編輯。**
>
> 實測（`docs/art/A2x` §6.1）：`ReferenceLatent` 餵一張母本、逐幀改 prompt，帽、衣、槍、手、鏤空格紋逐幀完全同一個人——「同一角色換姿勢」在 Klein 上一個節點成立，不需要共用幾何。工作流見 `art/workflows/a2x_flux2_edit.api.json`、腳本 `art/scripts/walk_frames.py`。
>
> 仍未解決的是**姿勢品質**：接觸姿勢正確，經過姿勢（併腿、抬膝）不穩，每幀要挑。且戰場行走已改走平面分件（架構規格 §4.7 修訂），逐格只留給倒地、轉身。Klein 編輯的正式用途因此是：替代姿勢、拆件用的分件圖、肖像。

### 7.5 授權：動手前必須自己確認一次

基礎模型的商用條款直接影響 Steam 上架，且**條款會變**。以下為撰寫當下的認知，**必須在正式產出資產前自行到官方頁面複查**：

- SDXL（CreativeML Open RAIL++-M）— 允許商用
- Flux.1 `[dev]` — 非商用
- Flux.1 `[schnell]`（Apache 2.0）— 允許商用

社群微調模型（Civitai 等）各自帶有不同授權，**逐一確認，不要假設繼承基礎模型的條款**。

常見的失敗是產完一整套資產才發現不能商用。

---

## 8. 美術軌里程碑

美術**不是** M1 的前置條件（見架構規格 §11 的撤回說明）。M1 全程在灰盒上開發，美術是一條並行軌道，兩軌在 M1 收尾時匯合。

| 階段 | 交付物 | 完成判準 |
|---|---|---|
| **A0** 環境 | ComfyUI + SDXL + ControlNet + IP-Adapter 裝好並跑通；基礎模型授權確認並記錄 | 能用 §4 的 prompt 規格產出可辨識的圖 |
| **A1** 定調 | 3–5 張「風格試片」：一個單位、一個塔、一小塊場景 | §6 的四項待決策事項全部有實測答案 |
| **A1.5** 史料參考圖 | 各陣營服飾的史料圖像，整理進 `art_src/refs/` | 每個單位類型至少一張可直接餵 IP-Adapter 的服飾參考。**這是人工蒐集工作，無法自動化**。*2026-09-10 補：用途改為 Klein 參考圖編輯（`generate_batch --stage ref`）的輸入——鐵人軍、大熕船靠它第一次做對* |
| **A2** 黃金母本集 | 20–30 張人工嚴格挑選的定調資產 | 連續三批風格穩定；並排檢視時光源方向一致 |
| **A3** 風格鎖定 | ~~以母本集訓練的風格 LoRA~~ **2026-09-10 結案：不訓 LoRA。** 第三批（肖像 6＋過場 3）與母本集並排無批次差，三批共 42 個資產、7 個類別。一致性的實際承擔者是扁平幾何風格本身與 Klein 參考圖編輯——多參考圖編輯在三個角色同框時仍能各自跟對參考圖，見 `docs/art/A2-master-set.md` 第三批 | ✅ 已達成 |
| **A4** 後處理管線 | 去背、色票量化、統一描邊、剪影檢查的腳本 + 色票一致性測試 | 測試能抓出刻意混入的色票外資產 |
| **A5** 量產 | 第一章所需的全部資產 | 全部通過 A4 的自動檢查 |

**A1.5 是 A2 的前置。** A1 實測（`docs/art/A1-findings.md`）證實：沒有史料服飾參考圖，單位資產做不出來——這不是 prompt 調校問題，是模型知識缺口。場景、地形、聚落不受此限，模型畫得出來，可先行。

**A2 是閘門**：母本集確立前不量產。理由與 M2 的效能閘門相同——風格漂移在單張圖上看不出來，要累積到十幾張才顯現，屆時已產出一批廢圖。

**A4 應優先於 A5**，且 A4 的腳本本身是程式碼，需要一份獨立的實作計畫（TDD、可測試）。色票量化與統一描邊正是 AI 畫不穩的兩件事，交給程式做即可根除。
