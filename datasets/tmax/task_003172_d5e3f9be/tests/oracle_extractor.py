import sys
import os
import struct
import json
import hashlib
import fcntl

def main():
    if len(sys.argv) != 4:
        sys.exit(1)
    sbk_path = sys.argv[1]
    out_dir = sys.argv[2]
    salt = sys.argv[3].encode('utf-8')

    try:
        with open(sbk_path, 'rb') as f:
            magic = f.read(4)
            if magic != b'SBK1':
                sys.exit(1)
            len_bytes = f.read(4)
            if len(len_bytes) != 4:
                sys.exit(1)
            manifest_len = struct.unpack('<I', len_bytes)[0]
            manifest_bytes = f.read(manifest_len)
            manifest = json.loads(manifest_bytes.decode('utf-8'))
            data_start = f.tell()
            data_section = f.read()
    except Exception:
        sys.exit(1)

    os.makedirs(out_dir, exist_ok=True)
    lock_path = os.path.join(out_dir, '.extraction_lock')

    with open(lock_path, 'w') as lock_file:
        fcntl.flock(lock_file, fcntl.LOCK_EX)
        try:
            for item in manifest:
                path = item['path']
                size = item['size']
                checksum = item['checksum']
                offset = item['offset']

                target_path = os.path.abspath(os.path.join(out_dir, path))
                out_dir_abs = os.path.abspath(out_dir)
                if not target_path.startswith(out_dir_abs + os.sep) and target_path != out_dir_abs:
                    continue

                file_data = data_section[offset:offset+size]
                computed_hash = hashlib.sha256(file_data + salt).hexdigest()
                if computed_hash != checksum:
                    continue

                os.makedirs(os.path.dirname(target_path), exist_ok=True)
                with open(target_path, 'wb') as out_f:
                    out_f.write(file_data)
        finally:
            fcntl.flock(lock_file, fcntl.LOCK_UN)

if __name__ == '__main__':
    main()
