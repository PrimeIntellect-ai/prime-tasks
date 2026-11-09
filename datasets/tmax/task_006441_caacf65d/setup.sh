#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 nginx
    pip3 install pytest

    mkdir -p /home/user/math-ws-proxy/src/math_ws

    cat << 'EOF' > /home/user/math-ws-proxy/pyproject.toml
[build-system]
requires = ["setuptools>=61.0"]
build-backend = "setuptools.build_meta"

[project]
name = "math-ws-proxy"
version = "0.1.0"
dependencies = [
  # missing dependency
]

[tool.setuptools.packages.find]
where = ["src"]
EOF

    touch /home/user/math-ws-proxy/src/math_ws/__init__.py

    cat << 'EOF' > /home/user/math-ws-proxy/src/math_ws/solver.py
def solve_diophantine(a: int, b: int, c: int):
    # TODO: Implement constraint satisfaction for positive integer x, y where a*x + b*y = c
    # Return (x, y) with smallest positive x, or None
    return (0, 0)
EOF

    sqlite3 /home/user/math-ws-proxy/legacy.db "CREATE TABLE requests (id INTEGER PRIMARY KEY, equation TEXT);"
    sqlite3 /home/user/math-ws-proxy/legacy.db "INSERT INTO requests (equation) VALUES ('3x + 4y = 25');"
    sqlite3 /home/user/math-ws-proxy/legacy.db "INSERT INTO requests (equation) VALUES ('5x + 2y = 12');"
    sqlite3 /home/user/math-ws-proxy/legacy.db "INSERT INTO requests (equation) VALUES ('10x + 15y = 100');"

    cat << 'EOF' > /home/user/math-ws-proxy/migrate.py
import sqlite3
import re

# TODO: Implement migration from legacy.db to v2.db
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
