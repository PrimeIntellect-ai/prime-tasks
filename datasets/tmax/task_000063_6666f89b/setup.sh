#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget
    pip3 install pytest

    # Set up vendored dirsync package
    mkdir -p /app/dirsync-2.2.5
    cd /app/dirsync-2.2.5
    wget -qO- https://github.com/tkhyn/dirsync/archive/refs/tags/v2.2.5.tar.gz | tar xz --strip-components=1 || true
    # If the download fails or structure is different, ensure the directory and file exist
    mkdir -p /app/dirsync-2.2.5/dirsync
    touch /app/dirsync-2.2.5/dirsync/sync.py

    # Create oracle binary
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/reference_archiver
#!/usr/bin/env python3
import os, sys, struct, json

def main():
    if len(sys.argv) != 3:
        sys.exit(1)
    target_dir = sys.argv[1]
    output_bin = sys.argv[2]

    config_path = os.path.join(target_dir, 'backup_config.json')
    if not os.path.exists(config_path):
        config_path = '/home/user/backup_config.json'

    try:
        with open(config_path, 'r') as f:
            config = json.load(f)
    except:
        config = {'exclude_extensions': [], 'min_mtime': 0}

    exclude_exts = config.get('exclude_extensions', [])
    min_mtime = config.get('min_mtime', 0)

    files_to_archive = []
    visited = set()

    def traverse(current_dir):
        try:
            st = os.stat(current_dir)
            inode = (st.st_dev, st.st_ino)
            if inode in visited:
                return
            visited.add(inode)
        except:
            pass

        try:
            entries = sorted(os.listdir(current_dir))
        except:
            return

        for entry in entries:
            full_path = os.path.join(current_dir, entry)
            if os.path.isdir(full_path):
                traverse(full_path)
            else:
                ext = os.path.splitext(entry)[1]
                if ext in exclude_exts:
                    continue
                try:
                    mtime = int(os.path.getmtime(full_path))
                    if mtime > min_mtime:
                        rel_path = os.path.relpath(full_path, target_dir)
                        files_to_archive.append((rel_path, full_path, mtime))
                except:
                    pass

    traverse(target_dir)
    files_to_archive.sort(key=lambda x: x[0])

    with open(output_bin, 'wb') as out:
        for rel_path, full_path, mtime in files_to_archive:
            try:
                size = os.path.getsize(full_path)
                with open(full_path, 'rb') as f:
                    content = f.read()
                rel_path_bytes = rel_path.encode('utf-8')
                out.write(struct.pack('>H', len(rel_path_bytes)))
                out.write(rel_path_bytes)
                out.write(struct.pack('>Q', mtime))
                out.write(struct.pack('>I', size))
                out.write(content)
            except:
                pass

if __name__ == '__main__':
    main()
EOF
    chmod +x /opt/oracle/reference_archiver

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
