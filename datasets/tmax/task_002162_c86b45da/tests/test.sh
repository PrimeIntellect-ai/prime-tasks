#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import zipfile
import io
import random
import pytest

def generate_zips(seed=42, n=100):
    random.seed(seed)
    zips = []
    for i in range(n):
        r = random.random()
        buf = io.BytesIO()
        if r < 0.3:
            # Valid archives with random valid .json, .wal, and .txt files
            with zipfile.ZipFile(buf, 'w') as z:
                for j in range(random.randint(1, 5)):
                    z.writestr(f'valid_{j}.json', '{"key": "value", "id": ' + str(random.randint(1, 100)) + '}')
                for j in range(random.randint(0, 3)):
                    z.writestr(f'log_{j}.wal', 'binary log data ' * random.randint(1, 10))
                for j in range(random.randint(0, 3)):
                    z.writestr(f'text_{j}.txt', 'text data ' * random.randint(1, 10))
        elif r < 0.6:
            # Valid archives but contain malicious file paths
            with zipfile.ZipFile(buf, 'w') as z:
                z.writestr('../../../etc/passwd', 'root:x:0:0:root:/root:/bin/bash')
                z.writestr('some/dir/../../../../tmp/bad', 'bad stuff')
                z.writestr('safe.json', '{"safe": true}')
        elif r < 0.8:
            # Contain .json files that are syntactically invalid
            with zipfile.ZipFile(buf, 'w') as z:
                z.writestr('malformed.json', '{"key": "value" ')
                z.writestr('good.json', '{"valid": true}')
        else:
            # Completely corrupted / invalid zip files
            buf.write(b'PK\x03\x04' + bytes(random.getrandbits(8) for _ in range(50)))

        zips.append(buf.getvalue())
    return zips

def test_fuzz_equivalence():
    agent_script = "/home/user/extract_config.go"
    oracle_binary = "/tests/extract_config_oracle"
    go_bin = "/usr/local/go/bin/go"

    assert os.path.isfile(agent_script), f"Agent program missing at {agent_script}"
    assert os.path.isfile(oracle_binary), f"Oracle program missing at {oracle_binary}"
    assert os.path.isfile(go_bin), f"Go binary missing at {go_bin}"

    agent_cmd = [go_bin, "run", agent_script]
    oracle_cmd = [oracle_binary]

    zips = generate_zips(seed=1337, n=100)

    for i, z_data in enumerate(zips):
        p_agent = subprocess.run(agent_cmd, input=z_data, capture_output=True)
        p_oracle = subprocess.run(oracle_cmd, input=z_data, capture_output=True)

        out_agent = p_agent.stdout.decode('utf-8', errors='replace').strip()
        out_oracle = p_oracle.stdout.decode('utf-8', errors='replace').strip()

        err_msg = (
            f"Mismatch on fuzz input {i}:\n"
            f"Oracle Output: {out_oracle}\n"
            f"Agent Output:  {out_agent}\n"
            f"Agent Stderr:  {p_agent.stderr.decode('utf-8', errors='replace')}"
        )
        assert out_agent == out_oracle, err_msg
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
