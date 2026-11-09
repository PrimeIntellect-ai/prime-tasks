import sys
import zlib

def main():
    if len(sys.argv) != 2:
        sys.exit(1)

    with open(sys.argv[1], 'rb') as f:
        data = f.read()

    if not data.startswith(b"BKP9"):
        sys.stderr.write("Invalid magic header\n")
        sys.exit(1)

    payload = data[4:]
    deobfuscated = bytes([b ^ 115 for b in payload])
    decompressed = zlib.decompress(deobfuscated)

    sys.stdout.buffer.write(decompressed)

if __name__ == "__main__":
    main()
