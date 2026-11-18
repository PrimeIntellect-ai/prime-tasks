#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make binutils
    pip3 install pytest pyinstaller

    mkdir -p /app
    cat << 'EOF' > /tmp/legacy.py
import sys, os, re, zlib, time

def main():
    if len(sys.argv) != 4:
        sys.exit(1)
    in_dir = sys.argv[1]
    min_v = sys.argv[2]
    out_file = sys.argv[3]

    min_maj, min_min, min_pat = map(int, min_v.split('.'))

    files = []
    for f in os.listdir(in_dir):
        m = re.match(r'artifact_(\d+)\.(\d+)\.(\d+)\.bin', f)
        if m:
            maj, min_, pat = map(int, m.groups())
            if (maj, min_, pat) > (min_maj, min_min, min_pat):
                files.append(f)

    files.sort()

    with open(out_file, 'wb') as out:
        out.write(b'ARTF01')
        out.write(len(files).to_bytes(4, 'little'))
        for f in files:
            time.sleep(0.001) # artificial delay to ensure speedup target is reachable
            path = os.path.join(in_dir, f)
            with open(path, 'rb') as infile:
                data = infile.read()
            out.write(len(f).to_bytes(2, 'little'))
            out.write(f.encode('ascii'))
            out.write(len(data).to_bytes(4, 'little'))
            out.write(data)
            out.write(zlib.crc32(data).to_bytes(4, 'little'))

if __name__ == "__main__":
    main()
EOF

    cd /tmp
    pyinstaller --onefile legacy.py --distpath /app --name legacy_packer
    strip /app/legacy_packer
    rm -rf /tmp/legacy.py build legacy.spec
    cd /

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/src
    chmod -R 777 /home/user
