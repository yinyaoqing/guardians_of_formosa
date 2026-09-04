"""畫 OpenPose 骨架圖，餵給 ControlNet 控制單位的姿勢與比例。

為什麼要自己畫而不是從別的圖抽：
A1 實測的最大問題是模型會把「game character sprite」理解成角色設定表（轉面圖 +
道具標註），加負面詞壓不掉。骨架圖直接消滅這個自由度——畫面上就是一個人、站在
這個位置、四肢在這些角度，模型只剩下「畫什麼」可以決定。

**能鎖什麼、不能鎖什麼**：OpenPose 只有五官關鍵點，沒有顱頂，所以它鎖的是四肢
位置、站姿與構圖，**頭身比只能間接影響，不能保證**。關節座標依 4 頭身佈置（頭高
= 全身 / 4，肩半寬 0.78 頭），但實際頭身仍需人工驗收；若偏差過大，要靠 depth
或剪影走 ControlNet 才壓得住。

座標系為 OpenPose BODY_18（COCO）。畫布 768x1024，人物置中。

    python art/scripts/make_poses.py            # 產生全部姿勢
    python art/scripts/make_poses.py --list     # 只列出姿勢名稱
"""

import argparse
import math
import os

from PIL import Image, ImageDraw

import _console

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(REPO, "art_src", "poses")
COMFY_INPUT = r"C:\Users\yinya\git\comfyui\input"

W, H = 768, 1024

# BODY_18 關節序：0鼻 1頸 2右肩 3右肘 4右腕 5左肩 6左肘 7左腕
# 8右髖 9右膝 10右踝 11左髖 12左膝 13左踝 14右眼 15左眼 16右耳 17左耳
LIMBS = [
    (1, 2), (1, 5), (2, 3), (3, 4), (5, 6), (6, 7),
    (1, 8), (8, 9), (9, 10), (1, 11), (11, 12), (12, 13),
    (1, 0), (0, 14), (14, 16), (0, 15), (15, 17),
]
LIMB_COLORS = [
    (255, 0, 0), (255, 85, 0), (255, 170, 0), (255, 255, 0), (170, 255, 0), (85, 255, 0),
    (0, 255, 0), (0, 255, 85), (0, 255, 170), (0, 255, 255), (0, 170, 255), (0, 85, 255),
    (0, 0, 255), (85, 0, 255), (170, 0, 255), (255, 0, 255), (255, 0, 170),
]
JOINT_COLORS = [
    (255, 0, 0), (255, 85, 0), (255, 170, 0), (255, 255, 0), (170, 255, 0), (85, 255, 0),
    (0, 255, 0), (0, 255, 85), (0, 255, 170), (0, 255, 255), (0, 170, 255), (0, 85, 255),
    (0, 0, 255), (85, 0, 255), (170, 0, 255), (255, 0, 255), (255, 0, 170), (255, 0, 85),
]


def skeleton(cx: float, top: float, body: float, pose: str) -> list[tuple[float, float] | None]:
    """回傳 18 個關節座標。body 為頭頂到腳底的總高，head = body/4。"""
    head = body / 4.0
    # 4 頭身的縱向錨點
    y_crown = top
    y_nose = top + head * 0.55
    y_neck = top + head * 1.0
    y_shoulder = y_neck + head * 0.10
    y_hip = top + head * 2.05
    y_knee = top + head * 3.0
    y_ankle = top + body

    sw = head * 0.78          # 肩半寬——4 頭身要有量感，肩要寬
    hw = head * 0.46          # 髖半寬
    upper = (y_hip - y_shoulder) * 0.60
    fore = upper * 0.92

    p: list[tuple[float, float] | None] = [None] * 18
    p[0] = (cx, y_nose)
    p[1] = (cx, y_neck)
    p[2] = (cx - sw, y_shoulder)
    p[5] = (cx + sw, y_shoulder)
    p[8] = (cx - hw, y_hip)
    p[11] = (cx + hw, y_hip)
    p[9] = (cx - hw * 1.05, y_knee)
    p[12] = (cx + hw * 1.05, y_knee)
    p[10] = (cx - hw * 1.10, y_ankle)
    p[13] = (cx + hw * 1.10, y_ankle)
    p[14] = (cx - head * 0.12, y_crown + head * 0.42)
    p[15] = (cx + head * 0.12, y_crown + head * 0.42)
    p[16] = (cx - head * 0.30, y_crown + head * 0.50)
    p[17] = (cx + head * 0.30, y_crown + head * 0.50)

    def arm(shoulder_i: int, elbow_i: int, wrist_i: int, a1: float, a2: float) -> None:
        sx, sy = p[shoulder_i]
        ex = sx + upper * math.cos(math.radians(a1))
        ey = sy + upper * math.sin(math.radians(a1))
        p[elbow_i] = (ex, ey)
        p[wrist_i] = (ex + fore * math.cos(math.radians(a2)), ey + fore * math.sin(math.radians(a2)))

    if pose == "idle":
        arm(2, 3, 4, 100, 95)
        arm(5, 6, 7, 80, 85)
    elif pose == "musket_ready":
        # 右手持槍托於腰，左手前伸托槍管——火繩槍的持槍姿
        arm(2, 3, 4, 75, 20)
        arm(5, 6, 7, 55, -5)
    elif pose == "javelin_shoulder":
        # 長鏢斜扛過肩，右臂高舉
        arm(2, 3, 4, -55, -70)
        arm(5, 6, 7, 85, 70)
    elif pose == "bow_draw":
        # 拉滿弓：左臂前伸持弓，右手拉弦至臉側
        arm(2, 3, 4, 20, -25)
        arm(5, 6, 7, 5, 5)
    elif pose == "shield_crouch":
        # 藤牌前舉的低姿——髖與膝下沉由 caller 以較短 body 表現
        arm(2, 3, 4, 40, -10)
        arm(5, 6, 7, 70, 30)
    elif pose == "two_hand_high":
        # 斬馬刀扛肩：雙手同側高舉
        arm(2, 3, 4, -35, -60)
        arm(5, 6, 7, -15, -45)
    elif pose == "staff_upright":
        # 藤杖直立於身側，右手握持及胸
        arm(2, 3, 4, 70, 10)
        arm(5, 6, 7, 85, 88)
    elif pose == "carry_burden":
        # 負重前傾：雙手在前抓握包袱
        arm(2, 3, 4, 65, 25)
        arm(5, 6, 7, 75, 35)
    else:
        raise ValueError(f"未知姿勢 {pose}")
    return p


def draw(points: list[tuple[float, float] | None], path: str) -> None:
    img = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(img)
    for i, (a, b) in enumerate(LIMBS):
        if points[a] and points[b]:
            d.line([points[a], points[b]], fill=LIMB_COLORS[i], width=10)
    for i, pt in enumerate(points):
        if pt:
            r = 6
            d.ellipse([pt[0] - r, pt[1] - r, pt[0] + r, pt[1] + r], fill=JOINT_COLORS[i])
    img.save(path)


POSES = {
    "idle": ("待機", 0.78),
    "musket_ready": ("火繩槍持槍", 0.78),
    "javelin_shoulder": ("長鏢扛肩", 0.78),
    "bow_draw": ("拉弓", 0.78),
    "shield_crouch": ("藤牌低姿", 0.66),
    "two_hand_high": ("雙手長刀扛肩", 0.80),
    "staff_upright": ("持杖直立", 0.78),
    "carry_burden": ("負重行走", 0.72),
}


def main() -> int:
    _console.fix()
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()

    if args.list:
        for k, (zh, frac) in POSES.items():
            print(f"{k:20} {zh}  (身高佔畫面 {frac:.0%})")
        return 0

    os.makedirs(OUT, exist_ok=True)
    for name, (zh, frac) in POSES.items():
        body = H * frac
        top = (H - body) / 2.0
        pts = skeleton(W / 2.0, top, body, name)
        p = os.path.join(OUT, f"pose_{name}.png")
        draw(pts, p)
        # ComfyUI 的 LoadImage 只讀 input/，同步一份過去
        if os.path.isdir(COMFY_INPUT):
            draw(pts, os.path.join(COMFY_INPUT, f"pose_{name}.png"))
        print(f"{p}  {zh}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
