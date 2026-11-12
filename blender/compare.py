"""Side-by-side of the reference photo and a render. Usage: python compare.py <render.jpg> <out.jpg>"""
import os
import sys

from PIL import Image

REF = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'reference', 'reference.jpg')
ref = Image.open(REF).convert('RGB')
ren = Image.open(sys.argv[1]).convert('RGB')
h = 700
ref = ref.resize((int(ref.width * h / ref.height), h))
ren = ren.resize((int(ren.width * h / ren.height), h))
out = Image.new('RGB', (ref.width + ren.width + 20, h), (255, 255, 255))
out.paste(ref, (0, 0))
out.paste(ren, (ref.width + 20, 0))
out.save(sys.argv[2], quality=90)
