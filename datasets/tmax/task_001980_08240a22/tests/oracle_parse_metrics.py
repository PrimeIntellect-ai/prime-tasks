import sys
import re
import unicodedata

def normalize_digits(s):
    return ''.join(str(unicodedata.decimal(c, c)) if unicodedata.category(c) == 'Nd' else c for c in s)

def main():
    pattern = re.compile(r"(?:\[|【)([^\]】]+)(?:\]|】)\s+([A-Z_]+)\s+([0-9.\u0660-\u0669\uFF10-\uFF19]+)")
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        match = pattern.search(line)
        if match:
            ts, metric, val = match.groups()
            ts = normalize_digits(ts)
            val = normalize_digits(val)
            print(f"{ts},{metric},{val}")

if __name__ == "__main__":
    main()
