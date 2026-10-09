"""Generates the default full-body 'buddy' sticker character, one SVG per mood.

Every part is drawn twice: first as a thick white silhouette (the sticker edge),
then in colour with a dark outline on top.
"""
import os
import re

SKIN, HAIR, SHIRT, PANTS, SHOE, INK = "#f2c29b", "#2b2118", "#3aa7a3", "#2f3e5c", "#1d2433", "#1d2433"
LIMB = 16      # arm/leg thickness
EDGE = 14      # white sticker border

# Shoulders, hips and the head stay fixed; poses only move elbows, hands and feet.
L_SHOULDER, R_SHOULDER = (78, 128), (122, 128)
L_HIP, R_HIP = (90, 170), (110, 170)

POSES = {
    #          left elbow, left hand,  right elbow, right hand,  left foot,  right foot
    "idle":  [(66, 150), (64, 176), (146, 122), (156, 94),  (86, 232), (114, 232)],   # waving
    "happy": [(56, 116), (50, 90),  (144, 116), (150, 90),  (78, 230), (122, 230)],   # arms up, cheering
    "water": [(66, 150), (64, 176), (144, 150), (160, 136), (86, 232), (114, 232)],   # holding out a glass
    "warn":  [(56, 150), (78, 168), (144, 150), (122, 168), (84, 232), (118, 228)],   # hands on hips, tapping foot
    "angry": [(56, 150), (78, 168), (146, 130), (172, 120), (80, 232), (120, 232)],   # pointing at you
    "walk1": [(62, 150), (70, 174), (140, 148), (148, 168), (70, 230), (122, 234)],   # walk cycle, stride A
    "walk2": [(60, 148), (52, 168), (138, 150), (130, 174), (78, 234), (130, 230)],   # walk cycle, stride B
}

def limb(a, b, c):
    return f"M{a[0]} {a[1]} Q{b[0]} {b[1]} {c[0]} {c[1]}"

def leg(hip, foot):
    return f"M{hip[0]} {hip[1]} L{foot[0]} {foot[1] - 6}"

def body_parts(pose):
    le, lh, re, rh, lf, rf = pose
    limbs = {  # name -> [(path, colour)]
        "LEGS": [(leg(L_HIP, lf), PANTS), (leg(R_HIP, rf), PANTS)],
        "ARMS": [(limb(L_SHOULDER, le, lh), SHIRT), (limb(R_SHOULDER, re, rh), SHIRT)],
    }
    shapes = [  # drawn in order, back to front
        f'<ellipse cx="{lf[0] - 5}" cy="{lf[1]}" rx="15" ry="9" fill="{SHOE}"/>',
        f'<ellipse cx="{rf[0] + 5}" cy="{rf[1]}" rx="15" ry="9" fill="{SHOE}"/>',
        "LEGS",
        f'<rect x="72" y="116" width="56" height="62" rx="20" fill="{SHIRT}"/>',
        "ARMS",
        f'<circle cx="{lh[0]}" cy="{lh[1]}" r="9" fill="{SKIN}"/>',
        f'<circle cx="{rh[0]}" cy="{rh[1]}" r="9" fill="{SKIN}"/>',
        f'<circle cx="54" cy="78" r="9" fill="{SKIN}"/>',
        f'<circle cx="146" cy="78" r="9" fill="{SKIN}"/>',
        f'<circle cx="100" cy="74" r="46" fill="{SKIN}"/>',
        f'<path d="M55 74 Q50 26 100 24 Q150 26 145 74 Q140 52 120 46 Q102 60 78 50 Q62 56 55 74 Z" fill="{HAIR}"/>',
    ]
    return limbs, shapes

def silhouette(limbs, shapes, extra):
    out = []
    for s in shapes + extra:
        if s in limbs:
            out += [f'<path d="{d}" fill="none" stroke="#fff" stroke-width="{LIMB + EDGE}" stroke-linecap="round"/>' for d, _ in limbs[s]]
        else:
            white = re.sub(r'fill="[^"]*"', 'fill="#fff"', s)
            out.append(white.replace("/>", f' stroke="#fff" stroke-width="{EDGE}" stroke-linejoin="round"/>'))
    return "\n  ".join(out)

def coloured(limbs, shapes, extra):
    out = []
    for s in shapes + extra:
        if s in limbs:
            for d, col in limbs[s]:
                out.append(f'<path d="{d}" fill="none" stroke="{INK}" stroke-width="{LIMB + 6}" stroke-linecap="round"/>')
                out.append(f'<path d="{d}" fill="none" stroke="{col}" stroke-width="{LIMB}" stroke-linecap="round"/>')
        else:
            out.append(s.replace("/>", f' stroke="{INK}" stroke-width="3.5" stroke-linejoin="round"/>'))
    return "\n  ".join(out)

def eyes(look=0):
    return f'''<ellipse cx="{84 + look}" cy="78" rx="6" ry="8" fill="{INK}"/>
  <ellipse cx="{116 + look}" cy="78" rx="6" ry="8" fill="{INK}"/>
  <circle cx="{86 + look}" cy="75" r="2.2" fill="#fff"/>
  <circle cx="{118 + look}" cy="75" r="2.2" fill="#fff"/>'''

BLUSH = '''<ellipse cx="72" cy="92" rx="8" ry="4.5" fill="#ff8fa3" opacity=".6"/>
  <ellipse cx="128" cy="92" rx="8" ry="4.5" fill="#ff8fa3" opacity=".6"/>'''

def stroke(d, w=4):
    return f'<path d="{d}" stroke="{INK}" stroke-width="{w}" fill="none" stroke-linecap="round"/>'

FACES = {
    "walk1": eyes(look=3) + BLUSH + stroke("M88 96 Q100 106 112 96"),
    "walk2": eyes(look=3) + BLUSH + stroke("M88 96 Q100 106 112 96"),
    "idle": eyes() + BLUSH + stroke("M88 96 Q100 106 112 96"),
    "happy": stroke("M76 80 Q84 70 92 80", 4.5) + stroke("M108 80 Q116 70 124 80", 4.5) + BLUSH
             + f'<path d="M86 94 Q100 116 114 94 Z" fill="{INK}"/><path d="M93 104 Q100 112 107 104 Z" fill="#ff6b81"/>',
    "water": eyes() + BLUSH + stroke("M76 62 Q84 56 92 60") + stroke("M108 60 Q116 56 124 62")
             + f'<ellipse cx="100" cy="100" rx="5" ry="6.5" fill="{INK}"/>',
    "warn": eyes(look=5) + stroke("M76 64 L92 66") + stroke("M108 62 Q116 54 124 60") + stroke("M90 100 L110 98"),
    "angry": eyes() + stroke("M74 60 L93 70", 5) + stroke("M126 60 L107 70", 5)
             + '<ellipse cx="72" cy="92" rx="9" ry="5" fill="#ff4d4d" opacity=".55"/>'
             + '<ellipse cx="128" cy="92" rx="9" ry="5" fill="#ff4d4d" opacity=".55"/>'
             + stroke("M88 104 Q100 94 112 104")
             + stroke("M150 24 q7 -7 0 -14 q-7 -7 0 -14", 4).replace(INK, "#9aa5b8")
             + stroke("M166 36 q7 -7 0 -14 q-7 -7 0 -14", 4).replace(INK, "#9aa5b8"),
}

def props(mood, pose):
    rh = pose[3]
    if mood == "water":  # glass of water in the right hand
        x, y = rh[0] - 4, rh[1] - 40
        return [f'<path d="M{x} {y} L{x + 26} {y} L{x + 23} {y + 40} L{x + 3} {y + 40} Z" fill="#ffffff"/>',
                f'<path d="M{x + 3} {y + 12} L{x + 23} {y + 12} L{x + 21} {y + 37} L{x + 5} {y + 37} Z" fill="#6ec6ff"/>',
                f'<circle cx="{rh[0]}" cy="{rh[1]}" r="9" fill="{SKIN}"/>']
    if mood == "angry":  # pointing finger
        return [f'<rect x="{rh[0] + 2}" y="{rh[1] - 4}" width="16" height="7" rx="3.5" fill="{SKIN}"/>']
    return []

def svg(mood):
    pose = POSES[mood]
    limbs, shapes = body_parts(pose)
    extra = props(mood, pose)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="400" height="520" viewBox="0 0 200 260">
  <ellipse cx="100" cy="248" rx="48" ry="7" fill="#000" opacity=".12"/>
  {silhouette(limbs, shapes, extra)}
  {coloured(limbs, shapes, extra)}
  {FACES[mood]}
</svg>
'''

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "stickers", "buddy")
os.makedirs(out, exist_ok=True)
for mood in POSES:
    with open(os.path.join(out, f"{mood}.svg"), "w") as f:
        f.write(svg(mood))
print("stickers written to", out)
