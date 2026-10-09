"""Generates the default 'Drop' sticker character, one SVG per mood."""
import os

BODY = "M100 18 C100 18 36 96 36 132 A64 64 0 0 0 164 132 C164 96 100 18 100 18 Z"

def eyes_open(look=0):
    return f'''
  <ellipse cx="{80+look}" cy="122" rx="8" ry="11" fill="#1d2433"/>
  <ellipse cx="{120+look}" cy="122" rx="8" ry="11" fill="#1d2433"/>
  <circle cx="{83+look}" cy="117" r="3" fill="#fff"/>
  <circle cx="{123+look}" cy="117" r="3" fill="#fff"/>'''

EYES_HAPPY = '''
  <path d="M70 124 Q80 110 90 124" stroke="#1d2433" stroke-width="5" fill="none" stroke-linecap="round"/>
  <path d="M110 124 Q120 110 130 124" stroke="#1d2433" stroke-width="5" fill="none" stroke-linecap="round"/>'''

BLUSH = '''
  <ellipse cx="66" cy="142" rx="9" ry="5" fill="#ff8fa3" opacity=".7"/>
  <ellipse cx="134" cy="142" rx="9" ry="5" fill="#ff8fa3" opacity=".7"/>'''

MOODS = {
    "idle": eyes_open() + BLUSH + '''
  <path d="M86 146 Q100 158 114 146" stroke="#1d2433" stroke-width="5" fill="none" stroke-linecap="round"/>''',
    "happy": EYES_HAPPY + BLUSH + '''
  <path d="M82 142 Q100 172 118 142 Z" fill="#1d2433"/>
  <path d="M90 155 Q100 166 110 155 Z" fill="#ff6b81"/>''',
    "water": eyes_open() + BLUSH + '''
  <path d="M68 102 Q80 94 92 100" stroke="#1d2433" stroke-width="4" fill="none" stroke-linecap="round"/>
  <path d="M108 100 Q120 94 132 102" stroke="#1d2433" stroke-width="4" fill="none" stroke-linecap="round"/>
  <ellipse cx="100" cy="152" rx="7" ry="9" fill="#1d2433"/>
  <g transform="translate(150 120) rotate(12)">
    <path d="M0 0 L30 0 L26 46 L4 46 Z" fill="#fff" stroke="#1d2433" stroke-width="4" stroke-linejoin="round"/>
    <path d="M3 14 L27 14 L25 43 L5 43 Z" fill="#6ec6ff"/>
  </g>''',
    "warn": eyes_open(look=6) + '''
  <path d="M68 104 L92 108" stroke="#1d2433" stroke-width="4" stroke-linecap="round"/>
  <path d="M108 100 Q120 90 132 98" stroke="#1d2433" stroke-width="4" fill="none" stroke-linecap="round"/>
  <path d="M86 152 L114 150" stroke="#1d2433" stroke-width="5" stroke-linecap="round"/>''',
    "angry": eyes_open() + '''
  <path d="M66 100 L92 112" stroke="#1d2433" stroke-width="6" stroke-linecap="round"/>
  <path d="M134 100 L108 112" stroke="#1d2433" stroke-width="6" stroke-linecap="round"/>
  <ellipse cx="66" cy="142" rx="10" ry="6" fill="#ff4d4d" opacity=".6"/>
  <ellipse cx="134" cy="142" rx="10" ry="6" fill="#ff4d4d" opacity=".6"/>
  <path d="M84 160 Q100 144 116 160" stroke="#1d2433" stroke-width="5" fill="none" stroke-linecap="round"/>
  <path d="M150 40 q8 -8 0 -16 q-8 -8 0 -16" stroke="#9aa5b8" stroke-width="5" fill="none" stroke-linecap="round"/>
  <path d="M168 54 q8 -8 0 -16 q-8 -8 0 -16" stroke="#9aa5b8" stroke-width="5" fill="none" stroke-linecap="round"/>''',
}

BODY_FILL = {"angry": "#ff9a8b", "warn": "#ffd27a"}

def svg(mood, face):
    fill = BODY_FILL.get(mood, "#5ab8ff")
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="400" height="400" viewBox="0 0 200 200">
  <path d="{BODY}" fill="#fff" stroke="#fff" stroke-width="16" stroke-linejoin="round" transform="translate(2 4)" opacity=".25"/>
  <path d="{BODY}" fill="#fff" stroke="#fff" stroke-width="16" stroke-linejoin="round"/>
  <path d="{BODY}" fill="{fill}" stroke="#1d2433" stroke-width="4" stroke-linejoin="round"/>
  <ellipse cx="76" cy="84" rx="9" ry="16" fill="#fff" opacity=".55" transform="rotate(25 76 84)"/>{face}
</svg>
'''

out = os.path.join(os.path.dirname(__file__), "stickers", "drop")
for mood, face in MOODS.items():
    with open(os.path.join(out, f"{mood}.svg"), "w") as f:
        f.write(svg(mood, face))
print("stickers written to", out)
