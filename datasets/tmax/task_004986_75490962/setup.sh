#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak-ng
    pip3 install pytest

    mkdir -p /app

    # Generate audio file
    espeak-ng -w /app/policy_brief.wav "The Content Security Policy max-age must be strictly greater than 31536000. Additionally, the binary auditor must flag any ELF file with an RWE segment as it violates CWE-511."

    # Create oracle auditor
    cat << 'EOF' > /app/oracle_auditor
#!/usr/bin/env python3
import sys
import json
import re

def main():
    if len(sys.argv) < 2:
        print("0")
        return
    try:
        data = json.loads(sys.argv[1])
        csp = data.get("csp_header", "")
        elf = data.get("elf_metadata", "")

        match = re.search(r'max-age=(\d+)', csp)
        if not match:
            print("0")
            return
        max_age = int(match.group(1))
        if max_age <= 31536000:
            print("0")
            return

        if "RWE" in elf:
            print("0")
            return

        print("1")
    except Exception:
        print("0")

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/oracle_auditor

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
