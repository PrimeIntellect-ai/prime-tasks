#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils
    pip3 install pytest pyinstaller

    mkdir -p /app
    cat << 'EOF' > /tmp/legacy_extract.py
import sys, struct, hashlib, os, json

def main():
    if len(sys.argv) < 2:
        sys.exit(1)

    try:
        with open(sys.argv[1], 'rb') as f:
            magic = f.read(4)
            if magic != b'ARC1':
                sys.exit(1)

            file_count_data = f.read(4)
            if not file_count_data:
                sys.exit(1)
            file_count = struct.unpack('<I', file_count_data)[0]

            manifest = []
            hash_map = {}

            for _ in range(file_count):
                fn_len_data = f.read(2)
                if not fn_len_data: break
                fn_len = struct.unpack('<H', fn_len_data)[0]

                filename = f.read(fn_len).decode('ascii')

                fs_data = f.read(4)
                file_size = struct.unpack('<I', fs_data)[0]

                content = f.read(file_size)

                sha256 = hashlib.sha256(content).hexdigest()

                if sha256 not in hash_map:
                    with open(filename, 'wb') as out_f:
                        out_f.write(content)
                    hash_map[sha256] = filename
                    manifest.append({
                        "path": filename,
                        "sha256": sha256,
                        "status": "original"
                    })
                else:
                    target = hash_map[sha256]
                    if os.path.exists(filename):
                        os.remove(filename)
                    os.link(target, filename)
                    manifest.append({
                        "path": filename,
                        "sha256": sha256,
                        "status": "hardlink",
                        "target": target
                    })

        sys.stdout.write(json.dumps({"manifest": manifest}, indent=2))
    except Exception as e:
        sys.exit(1)

if __name__ == '__main__':
    main()
EOF

    pyinstaller --onefile --distpath /app /tmp/legacy_extract.py
    strip /app/legacy_extract
    rm -rf /tmp/legacy_extract* build legacy_extract.spec

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
