#!/usr/bin/env python3
import sys

def main():
    if len(sys.argv) != 2:
        sys.exit(1)

    with open(sys.argv[1], 'rb') as f:
        f.seek(512)
        payload = f.read()

    decoded = payload.decode('cp037')
    cleaned = decoded.replace('ERROR', 'RESOLVED')
    print(cleaned, end='')

if __name__ == '__main__':
    main()
