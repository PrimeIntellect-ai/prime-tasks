#!/usr/bin/env python3
import sys
import re

def main():
    raw_data = sys.stdin.buffer.read()
    try:
        text = raw_data.decode('utf-8')
    except UnicodeDecodeError:
        text = raw_data.decode('iso-8859-1')

    records = []
    current_record = []
    for line in text.splitlines(keepends=True):
        if re.match(r'^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]', line):
            if current_record:
                records.append("".join(current_record))
                current_record = []
        current_record.append(line)
    if current_record:
        records.append("".join(current_record))

    for record in records:
        # Check if the header contains [TRACE]
        header = record.split('\n')[0] if record else ""
        if "[TRACE]" not in header:
            sys.stdout.buffer.write(record.encode('utf-8'))

if __name__ == "__main__":
    main()
