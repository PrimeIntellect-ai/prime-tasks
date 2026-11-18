import sys
import shutil
import subprocess

def get_section_offset(elf_path, sec_name):
    res = subprocess.run(["readelf", "-S", elf_path], capture_output=True, text=True)
    for line in res.stdout.splitlines():
        if sec_name in line:
            parts = line.split()
            try:
                # readelf -S format varies slightly, but typically:
                # [Nr] Name Type Address Off Size ...
                # Find the index of sec_name
                idx = parts.index(sec_name)
                # Offset is typically 2 or 3 indices after the Name depending on type
                # For safety, let's parse robustly
                if parts[idx+1] == "PROGBITS" or parts[idx+1] == "NOBITS" or parts[idx+1] == "NOTE":
                    offset_hex = parts[idx+3]
                else:
                    offset_hex = parts[idx+3] # heuristic
                return int(offset_hex, 16)
            except:
                pass
    return None

def main():
    if len(sys.argv) != 4:
        sys.exit(1)
    in_elf, wal_path, out_elf = sys.argv[1], sys.argv[2], sys.argv[3]

    with open(wal_path, "r") as f:
        lines = f.read().splitlines()

    if not lines:
        shutil.copy(in_elf, out_elf)
        return

    if lines[0] != "REPO_ID 2947528371":
        shutil.copy(in_elf, out_elf)
        return

    with open(in_elf, "rb") as f:
        data = bytearray(f.read())

    for line in lines[1:]:
        if not line.strip(): continue
        parts = line.split()
        cmd = parts[0]
        if cmd == "APPEND":
            data.extend(bytes.fromhex(parts[1]))
        elif cmd == "TRUNCATE":
            data = data[:int(parts[1])]
        elif cmd == "PATCH_SEC":
            sec_name = parts[1]
            rel_off = int(parts[2])
            hdata = bytes.fromhex(parts[3])

            sec_off = get_section_offset(in_elf, sec_name)
            if sec_off is not None:
                start = sec_off + rel_off
                data[start:start+len(hdata)] = hdata

    with open(out_elf, "wb") as f:
        f.write(data)

if __name__ == "__main__":
    main()
