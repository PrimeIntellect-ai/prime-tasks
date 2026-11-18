#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/system_manifest.conf
# System Component Manifest
# Format: Component_Name, Version, Dependencies
core_kernel, 1.0.4, none
lib_network, 2.1.0, core_kernel
malformed_package_missing_fields
gui_module, 3.0.0, lib_network, extra_unexpected_field
audio_driver, 1.1.2, core_kernel
EOF

    cat << 'EOF' > /home/user/build_tool.py
import sys
import argparse

def parse_manifest(filepath):
    valid_entries = []
    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.read().splitlines()

    i = 0
    # BUG 1: Off-by-one error (<= instead of <)
    while i <= len(lines):
        line = lines[i]
        if not line or line.startswith('#'):
            i += 1
            continue

        # BUG 2: No corrupted input handling. 
        # Crashing on lines without enough fields.
        parts = line.split(',')

        name = parts[0].strip()
        version = parts[1].strip()
        deps = parts[2].strip()

        valid_entries.append(f"{name}:{version} [{deps}]")
        i += 1

    return valid_entries

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    try:
        results = parse_manifest(args.manifest)
        with open(args.output, 'w') as f:
            for r in results:
                f.write(r + '\n')
        print(f"Build successful. Output written to {args.output}")
    except Exception as e:
        print(f"Build failed: {e}")
        sys.exit(1)
EOF

    chmod -R 777 /home/user
