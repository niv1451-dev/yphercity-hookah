"""Photo | before | after, same crop. Usage: triptych.py <before_render.png> <after_render.png> <out.jpg> x0 y0 x1 y1"""
import sys

from PIL import Image, ImageDraw

REF = r'D:\CarWork\onebike-blender\reference\reference.jpg'
ref = Image.open(REF).convert('RGB')
W, H = ref.size
box = tuple(int(v) for v in sys.argv[4:8])


def flat(path):
    r = Image.open(path).convert('RGBA').resize((W, H), Image.LANCZOS)
    bg = Image.new('RGBA', (W, H), (236, 236, 234, 255))
    bg.alpha_composite(r)
    return bg.convert('RGB')


panels = [ref.crop(box), flat(sys.argv[1]).crop(box), flat(sys.argv[2]).crop(box)]
labels = ['התמונה שלך', 'לפני', 'אחרי']
w, h = panels[0].size
out = Image.new('RGB', (w * 3 + 40, h + 50), (255, 255, 255))
d = ImageDraw.Draw(out)
try:
    from PIL import ImageFont
    font = ImageFont.truetype(r'C:\Windows\Fonts\arialbd.ttf', 30)
except Exception:
    font = None
for k, p in enumerate(panels):
    out.paste(p, (k * (w + 20), 50))
    txt = labels[k][::-1]   # Hebrew right-to-left for PIL without layout engine
    d.text((k * (w + 20) + w // 2, 25), txt, fill=(20, 20, 20), font=font, anchor='mm')
out.save(sys.argv[3], quality=90)
print('triptych ok')
