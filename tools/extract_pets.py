"""Copy the Codex app's built-in pet spritesheets out of its app.asar (local use only)."""
import json, os, re, struct, sys

ASAR = '/Applications/ChatGPT.app/Contents/Resources/app.asar'
dest = sys.argv[1]
with open(ASAR, 'rb') as f:
    _, hsize, _, jlen = struct.unpack('<4I', f.read(16))
    header = json.loads(f.read(jlen))
    base = 8 + hsize

    def walk(node, path=''):
        for name, v in node.get('files', {}).items():
            if 'files' in v:
                yield from walk(v, path + '/' + name)
            else:
                yield name, v

    for name, v in walk(header):
        m = re.match(r'(.+?)-spritesheet-v\d+-[0-9a-f]+\.webp$', name)
        if not m or v.get('unpacked'):
            continue
        f.seek(base + int(v['offset']))
        with open(os.path.join(dest, m.group(1) + '.webp'), 'wb') as out:
            out.write(f.read(v['size']))
        print('pet:', m.group(1))
