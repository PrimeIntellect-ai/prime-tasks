import sys
import os

def check_path(base_dir, untrusted_path):
    try:
        abs_base = os.path.abspath(base_dir)
        if os.path.isabs(untrusted_path):
            untrusted_path = untrusted_path.lstrip('/')

        resolved_path = os.path.abspath(os.path.join(abs_base, untrusted_path))

        common = os.path.commonpath([abs_base, resolved_path])
        if common == abs_base and resolved_path != abs_base:
            print(resolved_path)
        else:
            print("ERR_ZIP_SLIP_VIOLATION")
    except Exception:
        print("ERR_ZIP_SLIP_VIOLATION")

if __name__ == "__main__":
    if len(sys.argv) == 3:
        check_path(sys.argv[1], sys.argv[2])
