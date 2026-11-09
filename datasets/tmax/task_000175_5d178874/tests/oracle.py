import sys

def check():
    line = sys.stdin.read().strip()
    try:
        user, ip = line.split(' ')
    except ValueError:
        print("DENY")
        return

    if user == "root":
        print("DENY")
        return

    if len(user) < 5:
        print("DENY")
        return

    parts = ip.split('.')
    if len(parts) != 4:
        print("DENY")
        return

    for p in parts:
        if not p.isdigit() or not 0 <= int(p) <= 255:
            print("DENY")
            return

    if parts[-1] == '255':
        print("DENY")
        return

    print("ALLOW")

if __name__ == '__main__':
    check()
