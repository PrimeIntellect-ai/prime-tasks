#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip nodejs npm
pip3 install pytest

mkdir -p /home/user/legacy_router/legacy_router

cat << 'EOF' > /home/user/legacy_router/setup.py
from setuptools import setup, find_packages
import sys

if sys.version_info[0] > 2:
    print "Error: This package only runs on Python 2!"
    # The agent must fix this print statement and preferably remove the strict block.

setup(
    name='legacy_router',
    version='1.0',
    packages=find_packages(),
    entry_points={
        'console_scripts': [
            'legacy-router-cli=legacy_router.cli:main'
        ]
    }
)
EOF

touch /home/user/legacy_router/legacy_router/__init__.py

cat << 'EOF' > /home/user/legacy_router/legacy_router/router.py
import urlparse
from .emulator import run_condition

RULES = {
    "basic_user": "role 1 == points 100 < and",
    "premium_user": "role 2 == points 100 > and",
    "promoted_user": "role 1 == points 100 > and"
}

def route(url):
    parsed = urlparse.urlparse(url)
    params = dict(urlparse.parse_qsl(parsed.query))

    for route_name, condition in RULES.iteritems():
        if run_condition(condition, params):
            return route_name
    return "404_not_found"
EOF

cat << 'EOF' > /home/user/legacy_router/legacy_router/emulator.py
def run_condition(code, env):
    stack = []
    tokens = code.split()
    for token in tokens:
        if token in env:
            stack.append(int(env[token]))
        elif token.isdigit():
            stack.append(int(token))
        elif token == '<':
            b = stack.pop()
            a = stack.pop()
            stack.append(1 if a < b else 0)
        elif token == '>':
            b = stack.pop()
            a = stack.pop()
            stack.append(1 if a > b else 0)
        elif token == '==':
            b = stack.pop()
            a = stack.pop()
            stack.append(1 if a == b else 0)
        elif token == 'and':
            b = stack.pop()
            a = stack.pop()
            stack.append(1 if (a and b) else 0)

    return stack[0] == 1 if stack else False
EOF

cat << 'EOF' > /home/user/legacy_router/legacy_router/cli.py
import sys
from .router import route

def main():
    if len(sys.argv) < 2:
        print("Usage: legacy-router-cli <url>")
        sys.exit(1)
    url = sys.argv[1]
    matched = route(url)
    print(matched)

if __name__ == '__main__':
    main()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
