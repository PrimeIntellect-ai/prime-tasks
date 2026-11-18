#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip xxd strace ltrace
pip3 install pytest pyinstaller

mkdir -p /app
cat << 'EOF' > /app/legacy_cfg_manager.py
import sys, os, struct

def pack(input_dir, output_file):
    files_to_pack = []
    for root, _, files in os.walk(input_dir):
        for f in files:
            full_path = os.path.join(root, f)
            rel_path = os.path.relpath(full_path, input_dir).replace('\\', '/')
            files_to_pack.append((rel_path, full_path))
    files_to_pack.sort(key=lambda x: x[0])

    with open(output_file, 'wb') as out:
        out.write(b'CCF\x01')
        out.write(struct.pack('<I', len(files_to_pack)))
        for rel_path, full_path in files_to_pack:
            rel_path_bytes = rel_path.encode('utf-8')
            out.write(struct.pack('<H', len(rel_path_bytes)))
            out.write(rel_path_bytes)

            with open(full_path, 'rb') as f_in:
                data = f_in.read()

            out.write(struct.pack('<I', len(data)))
            xor_data = bytes([b ^ 0x5A for b in data])
            out.write(xor_data)

def unpack(archive, output_dir):
    pass

if __name__ == '__main__':
    if len(sys.argv) < 4: sys.exit(1)
    if sys.argv[1] == 'pack':
        pack(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == 'unpack':
        unpack(sys.argv[2], sys.argv[3])
EOF

cd /app
pyinstaller --onefile legacy_cfg_manager.py --distpath /app --name legacy_cfg_manager
chmod +x /app/legacy_cfg_manager
rm -rf build legacy_cfg_manager.spec legacy_cfg_manager.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
