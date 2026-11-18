from pathlib import Path
import struct
root = Path(__file__).resolve().parents[1]
entries = [('icp4','16x16'),('icp5','32x32'),('icp6','32x32@2x'),('ic07','128x128'),('ic08','256x256'),('ic09','512x512'),('ic10','512x512@2x')]
chunks = b''
for kind, size in entries:
    data = (root / '.build/AppIcon.iconset' / f'icon_{size}.png').read_bytes()
    chunks += kind.encode() + struct.pack('>I', len(data)+8) + data
(root / 'Resources/AppIcon.icns').write_bytes(b'icns'+struct.pack('>I', len(chunks)+8)+chunks)
