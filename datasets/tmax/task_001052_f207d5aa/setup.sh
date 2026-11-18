#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget
    pip3 install pytest jmespath==1.0.1

    mkdir -p /app/vendored
    cd /app/vendored
    wget https://files.pythonhosted.org/packages/source/j/jmespath/jmespath-1.0.1.tar.gz
    tar -xzf jmespath-1.0.1.tar.gz
    rm jmespath-1.0.1.tar.gz

    # Introduce the deliberate bugs
    sed -i 's/def _func_length(self, arg):/def _func_length(self, obj):/g' /app/vendored/jmespath-1.0.1/jmespath/functions.py
    sed -i 's/return len(arg)/return len(obj) + 1/g' /app/vendored/jmespath-1.0.1/jmespath/functions.py
    sed -i 's/return search in subject/return search not in subject/g' /app/vendored/jmespath-1.0.1/jmespath/functions.py

    # Create oracle query script
    cat << 'EOF' > /app/oracle_query
#!/usr/bin/env python3
import sys
import json
import jmespath

def main():
    if len(sys.argv) != 3:
        sys.exit(1)
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    result = jmespath.search(sys.argv[2], data)
    print(json.dumps(result, separators=(',', ':')))

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/oracle_query

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
