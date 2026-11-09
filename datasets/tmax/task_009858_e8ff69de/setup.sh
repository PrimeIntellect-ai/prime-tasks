#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/legacy_parser.py
import sys
import urllib
import urlparse

def evaluate(expr):
    if expr.startswith('add('):
        parts = expr[4:-1].split(',')
        return int(parts[0]) + int(parts[1])
    elif expr.startswith('sub('):
        parts = expr[4:-1].split(',')
        return int(parts[0]) - int(parts[1])
    return 0

for line in sys.stdin:
    line = line.strip()
    if not line: continue

    parsed = urlparse.urlparse(line)
    if parsed.scheme != 'emu': continue

    qs = urlparse.parse_qs(parsed.query)
    expr = qs.get('expr', [''])[0]
    ctx = qs.get('context', [''])[0]

    val = evaluate(expr)

    print "result {"
    print '  context_id: "%s"' % ctx
    print "  value: %d" % val
    print "}"
EOF

    cat << 'EOF' > /home/user/data.txt
emu://math/?expr=add(15,25)&context=alpha
http://google.com/?q=test
emu://math/?expr=sub(100,42)&context=beta
invalid_log_line_here
emu://math/?expr=add(0,7)&context=gamma
EOF

    chmod -R 777 /home/user
