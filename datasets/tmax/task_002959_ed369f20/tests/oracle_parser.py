import sys
import json
import os

BASE_DIR = os.path.abspath("/app/artifact_repo/safe_zone")

def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    for item in data:
        if not isinstance(item, dict) or "path" not in item:
            continue
        original_path = item["path"]
        resolved_path = os.path.abspath(os.path.join(BASE_DIR, original_path))
        try:
            common = os.path.commonpath([BASE_DIR, resolved_path])
        except ValueError:
            common = ""
        if common == BASE_DIR and resolved_path != BASE_DIR:
            print(resolved_path)
        else:
            print(f"REJECTED: {original_path}")

if __name__ == "__main__":
    main()
