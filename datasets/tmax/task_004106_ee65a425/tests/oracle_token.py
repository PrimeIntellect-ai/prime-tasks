import sys

def gen(username):
    return ''.join(f'{((ord(c) ^ 0x42) + 0x07) & 0xFF:02x}' for c in username)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        print(gen(sys.argv[1]))
