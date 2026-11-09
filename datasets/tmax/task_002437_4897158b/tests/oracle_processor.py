#!/usr/bin/env python3
import sys
import re

def process():
    input_text = sys.stdin.read()
    output_text = re.sub(r'[0-9]', '', input_text)
    sys.stdout.write(output_text)

if __name__ == '__main__':
    process()
