import sys

def process_fstab_line(line):
    line = line.strip()
    if not line or line.startswith('#'):
        return line

    parts = line.split()
    if len(parts) >= 4:
        fstype = parts[2]
        options = parts[3]
        if fstype == 'ext4':
            opts_list = options.split(',')
            if 'errors=remount-ro' not in opts_list:
                parts[3] = options + ',errors=remount-ro' if options else 'errors=remount-ro'

    return ' '.join(parts)

if __name__ == '__main__':
    if len(sys.argv) > 1:
        print(process_fstab_line(sys.argv[1]))
