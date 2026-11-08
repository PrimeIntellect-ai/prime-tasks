#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import random
import string
import subprocess
import gzip
import tempfile
import urllib.request

def test_services_running():
    # Check Redis
    try:
        import socket
        with socket.create_connection(("127.0.0.1", 6379), timeout=2):
            pass
    except Exception as e:
        assert False, f"Redis does not appear to be running on port 6379: {e}"

    # Check Nginx
    try:
        req = urllib.request.urlopen("http://127.0.0.1:8080/schema.json", timeout=2)
        assert req.getcode() == 200, "Nginx did not return 200 OK for schema.json"
    except Exception as e:
        assert False, f"Nginx does not appear to be serving schema.json on port 8080: {e}"

    # Check Log Generator
    log_file = "/tmp/project_logs/live.log"
    assert os.path.exists(log_file), f"Log generator does not appear to be running, {log_file} missing."

def generate_random_payload(encoding):
    length = random.randint(10, 100)
    text = ''.join(random.choices(string.ascii_letters + string.digits + " \n\t", k=length))
    if encoding == 'utf-16le':
        return text.encode('utf-16le').hex() + '\n'
    else:
        return text + '\n'

def generate_fuzz_file(filepath, is_gzip):
    num_blocks = random.randint(0, 50)
    content = ""
    for _ in range(num_blocks):
        txn_id = ''.join(random.choices(string.digits, k=8))
        encoding = 'utf-16le' if random.random() < 0.3 else 'utf-8'
        is_truncated = random.random() < 0.1

        content += f"[WAL_START] TXN={txn_id}\n"
        content += f"ENCODING={encoding}\n"
        content += generate_random_payload(encoding)
        if not is_truncated:
            content += f"[WAL_END] {txn_id}\n"

        # Add some random noise
        if random.random() < 0.2:
            content += "NOISE LINE\n"

    if is_gzip:
        with gzip.open(filepath, 'wt', encoding='utf-8') as f:
            f.write(content)
    else:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)

def test_fuzz_equivalence():
    agent_script = "/home/user/wal_parser.py"
    oracle_bin = "/tests/oracle_parser"

    assert os.path.isfile(agent_script), f"Agent script missing at {agent_script}"
    assert os.path.isfile(oracle_bin), f"Oracle binary missing at {oracle_bin}"

    random.seed(42)

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(100):
            is_gzip = random.random() < 0.5
            ext = ".log.gz" if is_gzip else ".log"
            filepath = os.path.join(tmpdir, f"fuzz_{i}{ext}")
            generate_fuzz_file(filepath, is_gzip)

            # Run oracle
            try:
                oracle_res = subprocess.run(["python3", oracle_bin, filepath], capture_output=True, text=True, check=True)
                oracle_json = json.loads(oracle_res.stdout)
            except Exception:
                # If oracle fails, preserve the original verifier behavior.
                oracle_json = None

            # Run agent
            try:
                agent_res = subprocess.run(["python3", agent_script, filepath], capture_output=True, text=True, check=True)
                agent_json = json.loads(agent_res.stdout)
            except Exception as e:
                agent_json = {"error": str(e)}

            assert agent_json == oracle_json, f"Mismatch on file {filepath}. Agent: {agent_json}, Oracle: {oracle_json}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
