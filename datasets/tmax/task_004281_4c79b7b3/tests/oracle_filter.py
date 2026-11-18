#!/usr/bin/env python3
import sys
import json
import os

REVOKED_IDS = {"REVOKED-1144", "REVOKED-3392", "REVOKED-8841"}

def is_safe(path):
    if path.startswith('/'): return False
    if '\0' in path: return False
    norm = os.path.normpath(path)
    if norm == '..' or norm.startswith('../'):
        return False
    return True

def main():
    if len(sys.argv) < 2:
        sys.exit(1)

    try:
        with open(sys.argv[1], 'r') as f:
            manifest = json.load(f)
    except Exception:
        sys.exit(1)

    artifact_id = manifest.get("artifact_id", "")
    if artifact_id in REVOKED_IDS:
        print("STATUS: REVOKED")
        return

    print("STATUS: APPROVED")

    for f in manifest.get("files", []):
        filename = f.get("filename", "")
        sha256 = f.get("sha256", "")
        if is_safe(filename):
            print(f"SAFE: {filename} - {sha256}")

if __name__ == '__main__':
    main()
