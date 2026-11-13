"""השוואת מבנה בין שני קבצי XML של CodeWalker (שלנו מול המקור), בלי נתוני הצורות עצמן.

הרצה: python xml_struct_diff.py <ours.yft.xml> <vanilla.yft.xml>
מדפיס כל "נתיב" של תגית (עם שמות התכונות שלה) שקיים רק באחד הקבצים, ואת ההבדלים בערכים קצרים.
"""
import sys
import xml.etree.ElementTree as ET
from collections import Counter

SKIP = {'VertexBuffer', 'IndexBuffer', 'Geometries', 'Shaders', 'Bones', 'Polygons', 'Vertices', 'Materials',
        'MaterialColours', 'VertexColours', 'Octants', 'TextureDictionary', 'Lights', 'Data', 'BVH'}


def walk(path):
    paths = Counter()
    values = {}
    stack = []
    skip_depth = None
    for ev, el in ET.iterparse(path, events=('start', 'end')):
        if ev == 'start':
            stack.append(el.tag)
            if skip_depth is not None:
                continue
            key = '/'.join(stack) + ('[' + ','.join(sorted(el.attrib)) + ']' if el.attrib else '')
            paths[key] += 1
            if el.tag in SKIP:
                skip_depth = len(stack)
        else:
            if skip_depth is None:
                p = '/'.join(stack)
                if 'value' in el.attrib and paths[p if p in paths else p] < 50:
                    values.setdefault(p, Counter())[el.attrib['value']] += 1
                if el.attrib and 'unk' in el.attrib:
                    values.setdefault(p + '@unk', Counter())[el.attrib['unk']] += 1
            if skip_depth is not None and len(stack) == skip_depth:
                skip_depth = None
            stack.pop()
            el.clear()
    return paths, values


def norm(paths):
    # נתיבים בלי מספרי כמות, כדי להשוות מבנה ולא כמויות
    return set(paths)


a_paths, a_vals = walk(sys.argv[1])
b_paths, b_vals = walk(sys.argv[2])
print('== נתיבים שקיימים רק אצלנו:')
for p in sorted(norm(a_paths) - norm(b_paths)):
    print('  ', p, a_paths[p])
print('== נתיבים שקיימים רק במקור:')
for p in sorted(norm(b_paths) - norm(a_paths)):
    print('  ', p, b_paths[p])
print('== ערכים שונים (רק שדות עם מעט ערכים):')
for p in sorted(set(a_vals) & set(b_vals)):
    va, vb = a_vals[p], b_vals[p]
    if set(va) != set(vb) and len(va) <= 4 and len(vb) <= 4:
        print('  ', p, ' אצלנו:', dict(va), ' במקור:', dict(vb))
