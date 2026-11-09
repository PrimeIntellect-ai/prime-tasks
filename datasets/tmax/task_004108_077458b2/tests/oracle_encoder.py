#!/usr/bin/env python3
import sys
import binascii

def encode(data: bytes, key: str) -> str:
    res = []
    for i in range(len(data)):
        res.append(data[i] ^ ord(key[i % len(key)]))
    return binascii.hexlify(bytes(res)).decode('utf-8')

if __name__ == '__main__':
    data = sys.stdin.read().encode('utf-8')
    # Key extracted from audio
    print(encode(data, "73914"), end='')
