#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak zip unzip
    pip3 install pytest

    mkdir -p /app

    # Create the audio file
    espeak -w /app/passphrase.wav "delta charlie niner"

    # Create the historical state archive
    mkdir -p /tmp/state
    echo "sample config" > /tmp/state/config.ini
    echo "sample wal" > /tmp/state/sample.wal
    cd /tmp
    echo "dummy part 1" > state.z01
    echo "dummy part 2" > state.z02
    echo "dummy part 3" > state.zip
    zip -P "delta charlie niner" /app/historical_state.zip state.z01 state.z02 state.zip

    # Create the oracle binary
    cat << 'EOF' > /app/oracle_applier
#!/usr/bin/env python3
import sys
import os
import json

def main():
    if len(sys.argv) != 4:
        sys.exit(1)
    passphrase = sys.argv[1]
    wal_file = sys.argv[2]
    target_dir = sys.argv[3]

    if passphrase != "delta charlie niner":
        sys.exit(42)

    with open(wal_file, 'r') as f:
        lines = f.readlines()

    for line in lines:
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        parts = line.split()
        cmd = parts[0]
        if cmd == "RENAME_EXT":
            old_ext = parts[1]
            new_ext = parts[2]
            for fname in os.listdir(target_dir):
                if fname.endswith(f".{old_ext}"):
                    base = fname[:-len(old_ext)-1]
                    os.rename(os.path.join(target_dir, fname), os.path.join(target_dir, f"{base}.{new_ext}"))
        elif cmd == "CHUNK_FILE":
            filename = parts[1]
            chunk_size = int(parts[2])
            filepath = os.path.join(target_dir, filename)
            if os.path.exists(filepath):
                with open(filepath, 'rb') as f:
                    data = f.read()
                if len(data) == 0:
                    continue
                for i in range(0, len(data), chunk_size):
                    chunk = data[i:i+chunk_size]
                    part_name = f"{filename}.part{i//chunk_size:03d}"
                    with open(os.path.join(target_dir, part_name), 'wb') as f:
                        f.write(chunk)
                os.remove(filepath)
        elif cmd == "CONVERT_KV_JSON":
            filename = parts[1]
            filepath = os.path.join(target_dir, filename)
            if os.path.exists(filepath):
                with open(filepath, 'r') as f:
                    lines = f.readlines()
                d = {}
                for l in lines:
                    if '=' in l:
                        k, v = l.strip().split('=', 1)
                        d[k] = v
                with open(filepath, 'w') as f:
                    json.dump(d, f, indent=2)

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/oracle_applier

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
