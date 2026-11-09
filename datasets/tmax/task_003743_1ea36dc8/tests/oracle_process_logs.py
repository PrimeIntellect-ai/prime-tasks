#!/usr/bin/env python3
import sys
import re
import hashlib

regex = re.compile(r"^\[(?P<ts>.*?)\] (?P<job>[A-Z0-9]+): (?P<data>.*)$")
seen = {}

for line in sys.stdin:
    match = regex.match(line.rstrip('\n'))
    if match:
        job = match.group('job')
        data = match.group('data')

        # Normalize
        norm_data = re.sub(r'\s+', ' ', data).strip().lower()

        # Hash
        md5_hash = hashlib.md5(norm_data.encode('utf-8')).hexdigest()

        if job not in seen:
            seen[job] = set()

        if md5_hash not in seen[job]:
            seen[job].add(md5_hash)
            print(f"{job}\t{norm_data}\t{md5_hash}")
