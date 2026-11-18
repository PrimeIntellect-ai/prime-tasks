#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/ticket
mkdir -p /home/user/app

head -c 1024 /dev/urandom > /home/user/ticket/core_dump.bin
echo -n "CRASH_CONTEXT: alias_name=group_omega" >> /home/user/ticket/core_dump.bin
head -c 512 /dev/urandom >> /home/user/ticket/core_dump.bin

cat << 'EOF' > /home/user/app/processor.py
def resolve_alias(alias_name):
    aliases = {
        "group_alpha": {"alias_of": "group_beta"},
        "group_beta": {"alias_of": "group_omega"},
        "group_omega": {"alias_of": "group_alpha"},
        "group_gamma": {"value": "data_gamma"}
    }
    return aliases.get(alias_name, {"value": alias_name})

def flatten_data(data):
    result = []
    stack = [data]
    while stack:
        current = stack.pop()
        if isinstance(current, list):
            for item in reversed(current):
                stack.append(item)
        elif isinstance(current, dict):
            if "alias_of" in current:
                resolved = resolve_alias(current["alias_of"])
                stack.append(resolved)
            else:
                result.append(current)
        else:
            result.append(current)
    return result
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
