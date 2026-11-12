"""Small procedural textures for the game model, written as uncompressed DDS."""
import os
import random
import struct

from PIL import Image, ImageDraw, ImageFilter


def write_dds(img, path):
    """Write an RGBA PIL image as an A8R8G8B8 DDS with a full mip chain."""
    img = img.convert('RGBA')
    w, h = img.size
    mips = [img]
    while mips[-1].size != (1, 1):
        mw, mh = mips[-1].size
        mips.append(mips[-1].resize((max(1, mw // 2), max(1, mh // 2)), Image.Resampling.BOX))
    header = struct.pack(
        '<4sIIIIIII44sIIIIIIIIIIIII',
        b'DDS ', 124, 0x2100F, h, w, w * 4, 0, len(mips), b'\0' * 44,
        32, 0x41, 0, 32, 0x00FF0000, 0x0000FF00, 0x000000FF, 0xFF000000,
        0x401008, 0, 0, 0, 0)
    with open(path, 'wb') as f:
        f.write(header)
        for m in mips:
            r, g, b, a = m.split()
            f.write(Image.merge('RGBA', (b, g, r, a)).tobytes())
    return len(mips)


def solid(rgb, size=8):
    return Image.new('RGBA', (size, size), rgb + (255,))


def noise(rgb, amount, size=128, blur=0.6, seed=1):
    rnd = random.Random(seed)
    img = Image.new('RGBA', (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            d = rnd.randint(-amount, amount)
            px[x, y] = tuple(max(0, min(255, c + d)) for c in rgb) + (255,)
    return img.filter(ImageFilter.GaussianBlur(blur))


def weave(rgb, size=128):
    img = noise(rgb, 6, size, 0.3, 7)
    d = ImageDraw.Draw(img)
    for i in range(0, size, 4):
        d.line([(i, 0), (i, size)], fill=tuple(max(0, c - 7) for c in rgb) + (255,))
        d.line([(0, i + 2), (size, i + 2)], fill=tuple(min(255, c + 6) for c in rgb) + (255,))
    return img


def mesh_net(rgb, size=128):
    img = Image.new('RGBA', (size, size), tuple(max(0, c - 14) for c in rgb) + (255,))
    d = ImageDraw.Draw(img)
    for y in range(0, size, 8):
        for x in range(0, size, 8):
            off = 4 if (y // 8) % 2 else 0
            d.ellipse([x + off + 1, y + 1, x + off + 6, y + 6], fill=tuple(min(255, c + 10) for c in rgb) + (255,))
    return img


FONT_DIR = '/usr/share/fonts/truetype/dejavu/'
# Windows has no DejaVu; Verdana is the closest match (same Vera-style wide sans).
WIN_FONTS = {'DejaVuSans.ttf': 'verdana.ttf', 'DejaVuSans-Bold.ttf': 'verdanab.ttf'}


def _font(name, px):
    from PIL import ImageFont
    path = FONT_DIR + name
    if not os.path.exists(path) and name in WIN_FONTS:
        path = os.path.join(os.environ.get('WINDIR', r'C:\Windows'), 'Fonts', WIN_FONTS[name])
    return ImageFont.truetype(path, px)


def display_image(size=512, speed=25, pas=3, battery=4, odo='1248.6', trip='12.4', clock='18:42'):
    """Round colour TFT e-bike display: speed gauge, PAS level, battery, odometer."""
    import math
    s = size
    c = s / 2
    img = Image.new('RGBA', (s, s), (0, 0, 0, 255))
    d = ImageDraw.Draw(img)
    for r in range(int(c), 0, -2):
        k = 1 - r / c
        d.ellipse([c - r, c - r, c + r, c + r], fill=(int(8 + 16 * k), int(10 + 18 * k), int(14 + 22 * k), 255))

    yellow, grey, white = (242, 194, 0, 255), (52, 56, 62, 255), (240, 242, 244, 255)
    rad = s * 0.425
    w = int(s * 0.05)
    box = [c - rad, c - rad, c + rad, c + rad]
    d.arc(box, 135, 405, fill=grey, width=w)
    d.arc(box, 135, 135 + 270 * speed / 45, fill=yellow, width=w)
    small = _font('DejaVuSans-Bold.ttf', int(s * 0.035))
    for k in range(10):
        a = math.radians(135 + 270 * k / 9)
        r0, r1 = rad - w * 0.65, rad - w * 1.05 - (s * 0.01 if k % 2 == 0 else 0)
        d.line([(c + r0 * math.cos(a), c + r0 * math.sin(a)), (c + r1 * math.cos(a), c + r1 * math.sin(a))],
               fill=(150, 156, 162, 255), width=max(2, s // 170))
        if k % 2 == 0:
            rl = rad - w * 1.85
            d.text((c + rl * math.cos(a), c + rl * math.sin(a)), str(k * 5), font=small, fill=(120, 126, 132, 255),
                   anchor='mm')

    d.text((c, c - s * 0.255), clock, font=_font('DejaVuSans.ttf', int(s * 0.045)), fill=(190, 196, 202, 255),
           anchor='mm')
    d.text((c + s * 0.02, c - s * 0.02), str(speed), font=_font('DejaVuSans-Bold.ttf', int(s * 0.27)), fill=white,
           anchor='mm')
    d.text((c + s * 0.02, c + s * 0.115), 'km/h', font=_font('DejaVuSans.ttf', int(s * 0.05)),
           fill=(170, 176, 182, 255), anchor='mm')
    d.text((c - s * 0.228, c - s * 0.07), 'PAS', font=small, fill=(150, 156, 162, 255), anchor='mm')
    d.text((c - s * 0.228, c + s * 0.0), str(pas), font=_font('DejaVuSans-Bold.ttf', int(s * 0.1)), fill=yellow,
           anchor='mm')
    # headlight indicator
    lx, ly = c + s * 0.255, c - s * 0.03
    d.chord([lx - s * 0.035, ly - s * 0.03, lx + s * 0.005, ly + s * 0.03], 90, 270, fill=(60, 220, 110, 255))
    for dy in (-0.02, 0.0, 0.02):
        d.line([(lx + s * 0.005, ly + s * dy), (lx + s * 0.04, ly + s * dy)], fill=(60, 220, 110, 255),
               width=max(2, s // 128))
    # battery
    bw, bh = s * 0.30, s * 0.07
    bx, by = c - bw / 2, c + s * 0.18
    d.rounded_rectangle([bx, by, bx + bw, by + bh], radius=s * 0.012, outline=(200, 205, 210, 255), width=max(2, s // 170))
    d.rectangle([bx + bw, by + bh * 0.3, bx + bw + s * 0.014, by + bh * 0.7], fill=(200, 205, 210, 255))
    seg = (bw - s * 0.024) / 5
    for k in range(5):
        x0 = bx + s * 0.012 + k * seg
        col = (70, 210, 100, 255) if k < battery else (40, 44, 48, 255)
        d.rectangle([x0 + 2, by + s * 0.012, x0 + seg - 3, by + bh - s * 0.012], fill=col)
    d.text((c, by + bh + s * 0.045), f'ODO {odo} km   TRIP {trip}', font=_font('DejaVuSans.ttf', int(s * 0.036)),
           fill=(165, 171, 177, 255), anchor='mm')
    return img


def display_wide():
    """The rectangular colour display: round gauge centred on a 2:1 black screen (power-of-two for the game)."""
    sq = display_image(512)
    wide = Image.new('RGBA', (1024, 512), (0, 0, 0, 255))
    wide.paste(sq, (256, 0))
    return wide


TEXTURES = {
    'onebike_display': display_wide,
    'onebike_white': lambda: solid((255, 255, 255)),
    'onebike_spec': lambda: solid((190, 190, 190)),
    'onebike_dirt': lambda: noise((118, 104, 86), 30, 64, 1.2, 3),
    'onebike_damage': lambda: solid((128, 128, 128)),
    'onebike_nrm': lambda: solid((128, 128, 255)),
    'onebike_alloy': lambda: noise((26, 26, 26), 3, 32, 0.5, 4),
    'onebike_plastic': lambda: noise((20, 20, 20), 4, 32, 0.5, 5),
    'onebike_gloss': lambda: solid((14, 14, 14)),
    'onebike_steel': lambda: noise((150, 150, 150), 8, 32, 0.5, 6),
    'onebike_steeldark': lambda: solid((70, 70, 70)),
    'onebike_chain': lambda: noise((85, 85, 85), 10, 32, 0.5, 8),
    'onebike_rotor': lambda: noise((180, 180, 180), 10, 64, 0.4, 9),
    'onebike_refl': lambda: solid((238, 238, 238)),
    'onebike_red': lambda: solid((200, 16, 16)),
    'onebike_lens': lambda: solid((255, 244, 214)),
    'onebike_screen': lambda: solid((27, 43, 51)),
    'onebike_screentext': lambda: solid((190, 232, 255)),
    'onebike_green': lambda: solid((48, 224, 96)),
    'onebike_tyre': lambda: noise((24, 24, 24), 7, 128, 0.5, 10),
    'onebike_rubber': lambda: noise((22, 22, 22), 6, 64, 0.4, 11),
    'onebike_leather': lambda: noise((16, 16, 16), 5, 128, 0.8, 12),
    'onebike_fabric': lambda: weave((22, 22, 22)),
    'onebike_mesh': lambda: mesh_net((32, 32, 32)),
}


def generate(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    info = {}
    for name, fn in TEXTURES.items():
        img = fn()
        mips = write_dds(img, os.path.join(out_dir, name + '.dds'))
        info[name] = (img.size[0], img.size[1], mips)
    return info


def write_ytd_xml(info, path):
    lines = ['<?xml version="1.0" encoding="UTF-8"?>', '<TextureDictionary>']
    for name, (w, h, mips) in info.items():
        lines += [' <Item>', f'  <Name>{name}</Name>', '  <Unk32 value="0" />', '  <Usage>UNKNOWN</Usage>',
                  '  <UsageFlags>0</UsageFlags>', '  <ExtraFlags value="0" />', f'  <Width value="{w}" />',
                  f'  <Height value="{h}" />', f'  <MipLevels value="{mips}" />', '  <Format>D3DFMT_A8R8G8B8</Format>',
                  f'  <FileName>{name}.dds</FileName>', ' </Item>']
    lines.append('</TextureDictionary>')
    with open(path, 'w') as f:
        f.write('\n'.join(lines) + '\n')
