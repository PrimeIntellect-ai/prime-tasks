#!/usr/bin/env python3
import sys, re
for line in sys.stdin:
    if 'interactive-prompt>' in line:
        continue
    match = re.search(r'([a-fA-F0-9\.\:]+)\s*:\s*xmt/rcv/%loss\s*=\s*\d+/\d+/(\d+)%', line)
    if match:
        print(f"{match.group(1)},{match.group(2)}")
