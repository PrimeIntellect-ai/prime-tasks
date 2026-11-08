#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server redis-tools jq
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/oracle_transform
#!/usr/bin/env python3
import sys
import json
import re

def process(line):
    if not line.strip(): return
    try:
        data = json.loads(line)
        msg_id = data.get("msg_id", "")
        lang = data.get("lang", "")
        template = data.get("template", "")
        vars_dict = data.get("vars", {})

        def repl(match):
            key = match.group(1)
            val = vars_dict.get(key)
            if val is None or val == "":
                return "DEFAULT"
            return str(val)

        interpolated = re.sub(r'\{([^}]+)\}', repl, template)
        print(f"{msg_id}|{lang}|{interpolated}")
    except Exception:
        pass

if __name__ == "__main__":
    for line in sys.stdin:
        process(line)
EOF
    chmod +x /app/oracle_transform

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
