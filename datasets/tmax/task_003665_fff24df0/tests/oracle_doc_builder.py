import sys
import os
import gzip
import struct
import tempfile

def build_archive(input_dir, output_file):
    input_dir_real = os.path.realpath(input_dir)
    visited_dirs = set()
    md_files = []

    def walk(current_dir, current_rel):
        real_dir = os.path.realpath(current_dir)
        if real_dir in visited_dirs:
            return
        visited_dirs.add(real_dir)

        try:
            entries = sorted(os.listdir(current_dir))
        except OSError:
            return

        for entry in entries:
            full_path = os.path.join(current_dir, entry)
            rel_path = os.path.join(current_rel, entry) if current_rel else entry

            if os.path.isdir(full_path):
                walk(full_path, rel_path)
            elif os.path.isfile(full_path) and entry.endswith('.md'):
                md_files.append((rel_path, full_path))

    walk(input_dir, "")
    md_files.sort(key=lambda x: x[0])

    out_dir = os.path.dirname(os.path.abspath(output_file))
    fd, temp_path = tempfile.mkstemp(dir=out_dir)
    os.close(fd)

    try:
        with gzip.open(temp_path, 'wb') as f:
            for rel_path, full_path in md_files:
                path_bytes = rel_path.encode('utf-8')
                with open(full_path, 'rb') as in_f:
                    content_bytes = in_f.read()

                f.write(struct.pack('>H', len(path_bytes)))
                f.write(path_bytes)
                f.write(struct.pack('>I', len(content_bytes)))
                f.write(content_bytes)
        os.rename(temp_path, output_file)
    except Exception as e:
        if os.path.exists(temp_path):
            os.remove(temp_path)
        raise e

if __name__ == "__main__":
    build_archive(sys.argv[1], sys.argv[2])
