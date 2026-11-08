#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sys
import struct
import random
import tempfile
import subprocess
import pytest

AGENT_SCRIPT = "/home/user/parse_backup.py"
ORACLE_SCRIPT = "/tests/reference_parser.py"

PATHS_POOL = [
    "src/utils.py", "Makefile", "docs/index.md", "tests/test_core.py",
    "README.md", "src/main.py", "src/config.json", "src/db/models.py",
    "src/db/migrations.sql", "tests/conftest.py", "scripts/deploy.sh",
    "docker-compose.yml", "Dockerfile", "requirements.txt",
    "src/api/routes.py", "src/api/auth.py", "static/css/style.css",
    "static/js/app.js", "templates/index.html", "logs/app.log"
]

def generate_wal_file(filepath, num_records):
    with open(filepath, 'wb') as f:
        f.write(b'BKP1')
        for _ in range(num_records):
            op = random.choice([0x01, 0x02, 0x03])
            path = random.choice(PATHS_POOL)
            path_bytes = path.encode('utf-8')
            path_len = len(path_bytes)
            checksum = random.randint(0, 0xFFFFFFFF)

            f.write(struct.pack('B', op))
            f.write(struct.pack('>H', path_len))
            f.write(path_bytes)
            f.write(struct.pack('>I', checksum))

def test_agent_script_exists():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_SCRIPT), f"Oracle script missing at {ORACLE_SCRIPT}"

    random.seed(42)
    N = 50

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(N):
            wal_path = os.path.join(tmpdir, f"test_{i}.wal")
            num_records = random.randint(10, 500)
            generate_wal_file(wal_path, num_records)

            # Run oracle
            oracle_cmd = [sys.executable, ORACLE_SCRIPT, wal_path]
            oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
            assert oracle_res.returncode == 0, f"Oracle failed on run {i}"

            # Run agent
            agent_cmd = [sys.executable, AGENT_SCRIPT, wal_path]
            agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)

            assert agent_res.returncode == 0, (
                f"Agent script failed on run {i} with {num_records} records.\n"
                f"STDERR: {agent_res.stderr}"
            )

            assert agent_res.stdout == oracle_res.stdout, (
                f"Output mismatch on run {i} with {num_records} records.\n"
                f"--- EXPECTED (Oracle) ---\n{oracle_res.stdout}\n"
                f"--- ACTUAL (Agent) ---\n{agent_res.stdout}\n"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
