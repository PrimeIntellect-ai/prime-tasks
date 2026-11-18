#!/usr/bin/env python3
import sys

def main():
    text = sys.stdin.read().strip()
    if not text:
        return
    words = text.split()

    chunks = []
    for i in range(0, len(words), 3):
        chunk = words[i:i+3]
        while len(chunk) < 3:
            chunk.append("SILENCE")
        chunks.append("-".join(chunk))

    for c in chunks:
        print(c)

if __name__ == "__main__":
    main()
