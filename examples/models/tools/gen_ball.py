"""
Writes examples/models/resources/source/props/ball/ball.glb: one object `ball` with three LOD
levels (a 32x16 uv sphere, a 12x6 sphere, an octahedron) and two materials (`model.ball` for the
sphere, `model.ball_far` for the octahedron), plus a checker albedo and a roughness map.
Run from the visu repo root: python3 examples/models/tools/gen_ball.py
"""
import json, math, struct, zlib, os

OUT = os.path.join(os.path.dirname(__file__), '..', 'resources', 'source', 'props', 'ball')

def sphere(rings, segments, radius=0.5):
    pos, nrm, uv, idx = [], [], [], []
    for r in range(rings + 1):
        v = r / rings
        phi = v * math.pi
        for s in range(segments + 1):
            u = s / segments
            theta = u * 2 * math.pi
            x = math.sin(phi) * math.cos(theta)
            y = math.cos(phi)
            z = math.sin(phi) * math.sin(theta)
            pos += [x * radius, y * radius, z * radius]
            nrm += [x, y, z]
            uv += [u, v]
    for r in range(rings):
        for s in range(segments):
            a = r * (segments + 1) + s
            b = a + segments + 1
            idx += [a, b, a + 1, a + 1, b, b + 1]
    return pos, nrm, uv, idx

def octahedron(radius=0.5):
    p = [(1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)]
    faces = [(0,2,4),(2,1,4),(1,3,4),(3,0,4),(2,0,5),(1,2,5),(3,1,5),(0,3,5)]
    pos, nrm, uv, idx = [], [], [], []
    for f in faces:
        n = [0,0,0]
        for i in f:
            n = [n[k] + p[i][k] for k in range(3)]
        l = math.sqrt(sum(c*c for c in n)); n = [c / l for c in n]
        for i in f:
            idx.append(len(pos)//3)
            pos += [c * radius for c in p[i]]
            nrm += n
            uv += [0.5 + 0.5 * p[i][0], 0.5 + 0.5 * p[i][2]]
    return pos, nrm, uv, idx

def png(width, height, rgba):
    def chunk(t, d):
        c = struct.pack('>I', len(d)) + t + d
        return c + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    raw = b''.join(b'\x00' + bytes(rgba[y*width*4:(y+1)*width*4]) for y in range(height))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))

meshes = [('lod0', sphere(16, 32)), ('lod1', sphere(6, 12)), ('lod2', octahedron())]
bin_ = bytearray(); views = []; accessors = []; gmeshes = []
def view(data, target):
    off = len(bin_); bin_.extend(data)
    while len(bin_) % 4: bin_.append(0)
    views.append({'buffer': 0, 'byteOffset': off, 'byteLength': len(data), 'target': target}); return len(views) - 1
def accessor(v, ctype, count, atype, mn=None, mx=None):
    a = {'bufferView': v, 'componentType': ctype, 'count': count, 'type': atype}
    if mn is not None: a['min'] = mn; a['max'] = mx
    accessors.append(a); return len(accessors) - 1
for i, (name, (pos, nrm, uv, idx)) in enumerate(meshes):
    n = len(pos) // 3
    ap = accessor(view(struct.pack('<%df' % len(pos), *pos), 34962), 5126, n, 'VEC3',
                  [min(pos[k::3]) for k in range(3)], [max(pos[k::3]) for k in range(3)])
    an = accessor(view(struct.pack('<%df' % len(nrm), *nrm), 34962), 5126, n, 'VEC3')
    au = accessor(view(struct.pack('<%df' % len(uv), *uv), 34962), 5126, n, 'VEC2')
    ai = accessor(view(struct.pack('<%dH' % len(idx), *idx), 34963), 5123, len(idx), 'SCALAR')
    gmeshes.append({'name': name, 'primitives': [{'attributes': {'POSITION': ap, 'NORMAL': an, 'TEXCOORD_0': au},
                                                   'indices': ai, 'material': 1 if i == 2 else 0}]})
gltf = {
    'asset': {'version': '2.0', 'generator': 'visu examples/models/tools/gen_ball.py'},
    'scene': 0, 'scenes': [{'nodes': [0]}],
    'nodes': [
        {'name': 'ball', 'mesh': 0, 'children': [1, 2]},
        {'name': '_L1_ball', 'mesh': 1},
        {'name': '_L2_ball', 'mesh': 2},
    ],
    'meshes': gmeshes,
    'materials': [{'name': 'model.ball'}, {'name': 'model.ball_far'}],
    'accessors': accessors, 'bufferViews': views, 'buffers': [{'byteLength': len(bin_)}],
}
js = json.dumps(gltf, separators=(',', ':')).encode()
while len(js) % 4: js += b' '
glb = b'glTF' + struct.pack('<II', 2, 12 + 8 + len(js) + 8 + len(bin_))
glb += struct.pack('<II', len(js), 0x4E4F534A) + js + struct.pack('<II', len(bin_), 0x004E4942) + bytes(bin_)
os.makedirs(OUT, exist_ok=True)
open(os.path.join(OUT, 'ball.glb'), 'wb').write(glb)

W = 64
albedo = []; rough = []
for y in range(W):
    for x in range(W):
        check = ((x // 8) + (y // 8)) % 2
        albedo += ([230, 120, 40, 255] if check else [40, 90, 200, 255])
        r = 40 + int(215 * (x / (W - 1)))
        rough += [r, r, r, 255]
open(os.path.join(OUT, 'ball_albedo.png'), 'wb').write(png(W, W, albedo))
open(os.path.join(OUT, 'ball_rough.png'), 'wb').write(png(W, W, rough))
open(os.path.join(OUT, 'ball.vmat'), 'w').write(json.dumps({
    'ball_rough': {'srgb': False},
    'model.ball': {'albedo': 'ball_albedo', 'rough': 'ball_rough', 'metallicFactor': 0.0},
    'model.ball_far': {'fallback': [0.9, 0.3, 0.1], 'roughnessFactor': 0.6},
    'ball': {'lod': [6, 14], 'cullDistance': 60},
}, indent=4) + '\n')
print('wrote', OUT, len(glb), 'bytes glb')
