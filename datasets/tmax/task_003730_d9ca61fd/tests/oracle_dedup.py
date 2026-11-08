import sys
import json
import hashlib

def process():
    seen = set()
    valid_count = 0
    dupe_count = 0

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            print("ERROR: Invalid JSON", file=sys.stderr)
            continue

        valid_count += 1

        config_str = record.get("config", "")
        pairs = config_str.split(",")
        norm_pairs = []
        for p in pairs:
            if "=" in p:
                k, v = p.split("=", 1)
                norm_pairs.append(f"{k.lower()}={v}")
            else:
                norm_pairs.append(p)
        norm_pairs.sort()
        normalized_config = ",".join(norm_pairs)

        host = record.get("host", "")
        hash_input = host + normalized_config
        h = hashlib.sha256(hash_input.encode('utf-8')).hexdigest()

        if h in seen:
            dupe_count += 1
            print(f"DUPLICATE: {h}", file=sys.stderr)
        else:
            seen.add(h)
            out = {
                "config": normalized_config,
                "config_hash": h,
                "host": host,
                "is_retry": record.get("is_retry", False),
                "timestamp": record.get("timestamp", "")
            }
            # sorted keys, no spaces
            print(json.dumps(out, separators=(',', ':'), sort_keys=True))

    print(f"SUMMARY: Processed {valid_count} valid records, {dupe_count} duplicates found.", file=sys.stderr)

if __name__ == "__main__":
    process()
