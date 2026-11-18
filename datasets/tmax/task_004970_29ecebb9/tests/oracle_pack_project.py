import sys
import os
import struct

def pack_directory(input_dir, output_archive):
    temp_archive = output_archive + ".tmp"
    with open(temp_archive, 'wb') as f:
        # Magic bytes
        f.write(b'PACK')
        # Version
        f.write(struct.pack('<I', 1))

        # Get all files and their relative paths
        files = []
        for root, _, filenames in os.walk(input_dir):
            for filename in filenames:
                full_path = os.path.join(root, filename)
                rel_path = os.path.relpath(full_path, input_dir)
                # Normalize path separators to forward slash just in case, though Linux is default
                files.append((rel_path, full_path))

        # Sort by case-sensitive alphabetical order of relative paths
        files.sort(key=lambda x: x[0])

        for rel_path, full_path in files:
            rel_path_encoded = rel_path.encode('utf-8')
            # 16-bit unsigned little-endian for relative path length
            f.write(struct.pack('<H', len(rel_path_encoded)))
            # UTF-8 encoded relative path
            f.write(rel_path_encoded)

            # File size
            file_size = os.path.getsize(full_path)
            # 64-bit unsigned little-endian for file size
            f.write(struct.pack('<Q', file_size))

            # Raw file contents
            with open(full_path, 'rb') as in_f:
                f.write(in_f.read())

    os.rename(temp_archive, output_archive)

if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(1)
    pack_directory(sys.argv[1], sys.argv[2])
