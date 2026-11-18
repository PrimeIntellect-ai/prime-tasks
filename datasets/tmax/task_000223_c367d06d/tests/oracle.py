import sys
import json
import re

def process(line):
    try:
        data = json.loads(line)
        msg = data.get("message", "")
    except Exception:
        return ""

    # 1. Decode double-escaped unicode
    msg = re.sub(r'\\u([0-9a-fA-F]{4})', lambda m: chr(int(m.group(1), 16)), msg)

    # 2 & 3. Replacements
    msg = msg.replace('@', 'AT').replace('#', 'HASH')

    # 4. Lowercase
    msg = msg.lower()

    # 5. Split on whitespace
    tokens = msg.split()

    # 6. Filter alphanumeric
    valid_tokens = [t for t in tokens if t.isalnum()]

    # 7. Unique and sort
    sorted_tokens = sorted(list(set(valid_tokens)))

    # 8. Join
    return '|'.join(sorted_tokens)

if __name__ == "__main__":
    input_data = sys.stdin.read().strip()
    if input_data:
        print(process(input_data), end="")
