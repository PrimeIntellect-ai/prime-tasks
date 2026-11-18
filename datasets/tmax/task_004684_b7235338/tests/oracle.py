#!/usr/bin/env python3
import sys
import json

def process():
    line = sys.stdin.read().strip()
    if not line: return
    data = json.loads(line)

    name = data.get("name", "")
    strings = data.get("strings", {})

    total_keys = len(strings)
    null_keys = sum(1 for v in strings.values() if v is None)

    sys.stderr.write(f"[INFO] Processed user: {name}, nulls: {null_keys}\n")

    for k, v in strings.items():
        if v is None:
            if k == "greeting":
                strings[k] = f"Bonjour, {name}!"
            elif k == "error":
                strings[k] = f"Erreur de connexion pour {name}"
        else:
            # Encoding fixes
            v = v.replace("Ã©", "é").replace("Ã¨", "è").replace("Ã§", "ç")
            strings[k] = v

    data["stats"] = {
        "total_keys": total_keys,
        "null_keys": null_keys
    }

    print(json.dumps(data, separators=(',', ':')))

if __name__ == "__main__":
    process()
