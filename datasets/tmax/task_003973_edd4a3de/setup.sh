#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/sysconf_parser

    cat << 'EOF' > /home/user/sysconf_parser/parser.py
def parse_config(text: str, env: dict) -> dict:
    result = {}
    for line in text.split('\n'):
        if line.startswith('#') or not line.strip():
            continue
        # Broken: splits on all equals and loses data
        parts = line.split('=') 
        if len(parts) >= 2:
            key = parts[0]
            value = parts[1]
            # Broken: doesn't replace all instances, fails if var not in env
            if '${' in value:
                start = value.find('${') + 2
                end = value.find('}', start)
                var_name = value[start:end]
                value = value.replace('${' + var_name + '}', env[var_name])
            result[key.strip()] = value.strip()
    return result
EOF

    cat << 'EOF' > /home/user/sysconf_parser/example.conf
# This is a test config
host=localhost
port=8080
db_path=${SYSTEM_ROOT}/db/data.sqlite
fallback_user=${USER}
complex_key=some=value=with=equals
missing_var=${NON_EXISTENT}/path
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
