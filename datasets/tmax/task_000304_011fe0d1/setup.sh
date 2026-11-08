#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/expressions.txt
10 * 5
50.0 + 0
12 / 4
2 + 1
100 - 50
3 * 1
1.5 * 2.0
EOF

    python3 -c "
with open('/home/user/template.md', 'w') as f:
    f.write('# Math Deduplication Report\n\nTotal unique results: {' + '{UNIQUE_COUNT}' + '}\n\n## Unique Expressions\n{' + '{EXPRESSIONS_LIST}' + '}\n')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
