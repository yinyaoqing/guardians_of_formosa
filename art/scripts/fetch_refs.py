"""從 Wikimedia Commons 下載史料服飾參考圖，並記錄出處與授權。

為什麼需要這些圖：A1 實測證實 SDXL 沒有 17 世紀明鄭／西拉雅／亞洲 VOC 的服飾
知識，缺乏知識時會退回泛用的「前現代非歐洲士兵」先驗，落點在日本與波斯之間跳動。
負面詞能趕走錯的答案，叫不出模型沒有的答案——只能餵圖。見 docs/art/A1-findings.md §2。

下載時一併寫出 _provenance.json，記錄每張圖的出處 URL、授權、作者。
**參考圖只用於生成條件，不直接進遊戲**，但出處仍須留存以備查。

    python art/scripts/fetch_refs.py                  # 全部
    python art/scripts/fetch_refs.py --group siraya_formosan
    python art/scripts/fetch_refs.py --list           # 只列清單與缺口
"""

import argparse
import json
import os
import ssl
import time
import urllib.error
import urllib.parse
import urllib.request

import _console

# 本機 Python 的內建 CA bundle 已過期，直接 urlopen 會拿到 CERTIFICATE_VERIFY_FAILED。
# 改用 certifi 的憑證；若連 certifi 都沒有就退回預設，讓錯誤訊息自己說話。
try:
    import certifi

    SSL_CTX: ssl.SSLContext | None = ssl.create_default_context(cafile=certifi.where())
except ImportError:  # pragma: no cover
    SSL_CTX = None

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MANIFEST = os.path.join(REPO, "art", "manifest", "reference_images.json")
OUT = os.path.join(REPO, "art_src", "refs")
API = "https://commons.wikimedia.org/w/api.php"
UA = "guardians-of-formosa-art-pipeline/1.0 (research reference collection)"

# Commons 對大圖提供縮圖服務。參考圖只餵 IP-Adapter，1024px 綽綽有餘，
# 原圖動輒數十 MB（有張手卷是 24894px 寬），沒必要下載。
#
# **必須用標準尺寸**：Commons 只快取固定幾種寬度，指定 1600 這種非標準值會強迫
# 伺服器即時算圖，連抓十幾張就被限流回 429（錯誤訊息本身也是這樣建議的）。
THUMB_WIDTH = 1024


def api(params: dict) -> dict:
    url = API + "?" + urllib.parse.urlencode({**params, "format": "json"})
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60, context=SSL_CTX) as resp:
        return json.loads(resp.read())


def resolve(titles: list[str]) -> dict[str, dict]:
    """一次查多個檔名，回傳 title -> {url, thumb, license, artist, width, height}。"""
    out: dict[str, dict] = {}
    for i in range(0, len(titles), 10):
        chunk = titles[i : i + 10]
        d = api({
            "action": "query",
            "titles": "|".join(chunk),
            "prop": "imageinfo",
            "iiprop": "url|size|extmetadata",
            "iiurlwidth": THUMB_WIDTH,
        })
        for p in (d.get("query", {}).get("pages") or {}).values():
            if "imageinfo" not in p:
                continue
            ii = p["imageinfo"][0]
            em = ii.get("extmetadata", {})
            out[p["title"]] = {
                "url": ii.get("url"),
                "thumb": ii.get("thumburl") or ii.get("url"),
                "descriptionurl": ii.get("descriptionurl"),
                "license": em.get("LicenseShortName", {}).get("value", "?"),
                "artist": _strip(em.get("Artist", {}).get("value", "")),
                "credit": _strip(em.get("Credit", {}).get("value", "")),
                "width": ii.get("width"),
                "height": ii.get("height"),
            }
    return out


def _strip(html: str) -> str:
    out, depth = [], 0
    for ch in html:
        if ch == "<":
            depth += 1
        elif ch == ">":
            depth -= 1
        elif depth == 0:
            out.append(ch)
    return " ".join("".join(out).split())[:200]


def safe_name(title: str) -> str:
    base = title[len("File:"):] if title.startswith("File:") else title
    base = base.rsplit(".", 1)[0]
    keep = "".join(c if (c.isalnum() or c in " -_") else "_" for c in base)
    return " ".join(keep.split())[:70].replace(" ", "_")


def download(url: str, dest: str, attempts: int = 4) -> bool:
    """Commons 的縮圖服務會限流回 429，連抓十幾張必中，故退避重試。"""
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    for n in range(attempts):
        try:
            with urllib.request.urlopen(req, timeout=180, context=SSL_CTX) as resp:
                data = resp.read()
        except urllib.error.HTTPError as exc:
            if exc.code == 429 and n < attempts - 1:
                wait = 5 * (n + 1)
                print(f"    429 限流，{wait}s 後重試")
                time.sleep(wait)
                continue
            print(f"    下載失敗：{exc}")
            return False
        except Exception as exc:  # noqa: BLE001 — 單張失敗不該中斷整批
            print(f"    下載失敗：{exc}")
            return False
        with open(dest + ".part", "wb") as f:
            f.write(data)
        os.replace(dest + ".part", dest)
        return True
    return False


def main() -> int:
    _console.fix()
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--group", action="append", help="只做這些組")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()

    with open(MANIFEST, encoding="utf-8") as f:
        m = json.load(f)
    groups = {k: v for k, v in m["groups"].items() if not args.group or k in args.group}

    if args.list:
        for k, g in groups.items():
            print(f"\n=== {k} — {g['zh']}（{len(g['titles'])} 張）")
            print(f"    {g['note']}")
            for t in g["titles"]:
                print(f"    - {t[:80]}")
        print("\n=== 已知缺口（無法從 Commons 取得，需另尋來源）")
        for k, v in m["_gaps"].items():
            print(f"  [{k}] {v}")
        return 0

    provenance: dict[str, dict] = {}
    total = ok = 0
    for gname, g in groups.items():
        d = os.path.join(OUT, gname)
        os.makedirs(d, exist_ok=True)
        print(f"\n=== {gname} — {g['zh']}")
        info = resolve(g["titles"])
        for t in g["titles"]:
            total += 1
            meta = info.get(t)
            if meta is None:
                print(f"  找不到：{t[:70]}")
                continue
            ext = os.path.splitext(urllib.parse.urlparse(meta["thumb"]).path)[1] or ".jpg"
            dest = os.path.join(d, safe_name(t) + ext)
            if os.path.exists(dest):
                print(f"  SKIP {os.path.basename(dest)}")
                ok += 1
            elif (time.sleep(1.5), download(meta["thumb"], dest))[1]:
                print(f"  OK   {os.path.basename(dest)}  [{meta['license']}]")
                ok += 1
            else:
                continue
            provenance[os.path.relpath(dest, OUT).replace("\\", "/")] = {
                "commons_title": t,
                "source": meta["descriptionurl"],
                "license": meta["license"],
                "artist": meta["artist"],
                "credit": meta["credit"],
                "original_size": f"{meta['width']}x{meta['height']}",
            }

    if provenance:
        pp = os.path.join(OUT, "_provenance.json")
        old = {}
        if os.path.exists(pp):
            with open(pp, encoding="utf-8") as f:
                old = json.load(f)
        old.update(provenance)
        with open(pp, "w", encoding="utf-8") as f:
            json.dump(old, f, ensure_ascii=False, indent=2)
        print(f"\n出處已寫入 {pp}（{len(old)} 筆）")

    print(f"=== 完成 {ok}/{total}")
    return 0 if ok == total else 1


if __name__ == "__main__":
    raise SystemExit(main())
