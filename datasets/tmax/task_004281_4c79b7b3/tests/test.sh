#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import json
import random
import string
import subprocess
import os
import tempfile
import pytest

AGENT_SCRIPT = "/home/user/filter_manifest.py"
ORACLE_SCRIPT = "/tests/oracle_filter.py"
REVOKED_IDS = ["REVOKED-1144", "REVOKED-3392", "REVOKED-8841"]

def generate_random_manifest(seed):
    random.seed(seed)

    if random.random() < 0.25:
        artifact_id = random.choice(REVOKED_IDS)
    else:
        artifact_id = "SAFE-" + "".join(random.choices(string.digits, k=4))

    num_files = random.randint(0, 20)
    files = []

    path_types = ["safe", "absolute", "null_byte", "traversal"]

    for _ in range(num_files):
        ptype = random.choice(path_types)
        if ptype == "safe":
            filename = "/".join("".join(random.choices(string.ascii_lowercase, k=4)) for _ in range(random.randint(1, 4))) + ".txt"
        elif ptype == "absolute":
            filename = "/" + "/".join("".join(random.choices(string.ascii_lowercase, k=4)) for _ in range(random.randint(1, 4)))
        elif ptype == "null_byte":
            filename = "".join(random.choices(string.ascii_lowercase, k=4)) + "\0" + "".join(random.choices(string.ascii_lowercase, k=4))
        elif ptype == "traversal":
            filename = random.choice(["../foo", "a/b/../../c/../../../d", "././../root", "dir/../../escape", "a/../b/../../c"])

        sha256 = "".join(random.choices(string.hexdigits.lower(), k=64))
        files.append({
            "filename": filename,
            "size": random.randint(100, 10000),
            "sha256": sha256
        })

    return {
        "artifact_id": artifact_id,
        "files": files
    }

def test_agent_script_exists_and_executable():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script is missing: {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"Path exists but is not a file: {AGENT_SCRIPT}"
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script is not executable: {AGENT_SCRIPT}"

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_SCRIPT), f"Oracle script missing: {ORACLE_SCRIPT}"

    for i in range(200):
        manifest = generate_random_manifest(i)
        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix=".json") as f:
            json.dump(manifest, f)
            temp_path = f.name

        try:
            oracle_proc = subprocess.run(
                [ORACLE_SCRIPT, temp_path],
                capture_output=True,
                text=True
            )
            agent_proc = subprocess.run(
                [AGENT_SCRIPT, temp_path],
                capture_output=True,
                text=True
            )

            error_msg = (
                f"Mismatch found on random input seed {i}.\n"
                f"Input manifest:\n{json.dumps(manifest, indent=2)}\n\n"
                f"Oracle stdout:\n{oracle_proc.stdout}\n"
                f"Agent stdout:\n{agent_proc.stdout}\n"
            )
            assert agent_proc.stdout == oracle_proc.stdout, error_msg
        finally:
            os.remove(temp_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
