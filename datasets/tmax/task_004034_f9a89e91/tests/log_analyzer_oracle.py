import sys
import csv
import json
import re

def main():
    reader = csv.reader(sys.stdin)
    prev_messages = {}

    header_seen = False
    for row in reader:
        if not header_seen and row == ['timestamp', 'server_id', 'message']:
            header_seen = True
            continue

        if len(row) != 3:
            continue

        ts, srv, msg = row

        # Normalize
        msg = msg.lower()
        msg = re.sub(r'\s+', ' ', msg).strip()

        # Similarity
        sim = None
        if srv in prev_messages:
            prev_msg = prev_messages[srv]
            set1 = set(msg.split(' ')) if msg else set()
            set2 = set(prev_msg.split(' ')) if prev_msg else set()

            if not set1 and not set2:
                sim = 1.0
            else:
                intersection = len(set1.intersection(set2))
                union = len(set1.union(set2))
                sim = round(intersection / union, 4)

        prev_messages[srv] = msg

        out = {
            "timestamp": ts,
            "server_id": srv,
            "normalized_message": msg,
            "similarity": sim
        }
        print(json.dumps(out))

if __name__ == "__main__":
    main()
