"""Windows 主控台編碼修正。

Windows 的預設 codepage 是 cp950，印得出「銃」印不出「熕」，也印不出「↔」。
輸出重導向到檔案時會直接拋 UnicodeEncodeError 中斷整支腳本——這在跑了半小時的
批次途中發生過兩次。本專案的資產名與訊息一律含中文，故所有腳本都要先呼叫 fix()。
"""

import sys


def fix() -> None:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")
