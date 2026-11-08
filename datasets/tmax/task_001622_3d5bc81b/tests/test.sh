#!/bin/bash
set +e
mkdir -p /logs/verifier

ORACLE_DIR="$(mktemp -d /root/verifier-oracle.XXXXXX)"
ORACLE_HIDDEN="$ORACLE_DIR/legacy_parser"
PREPARED=0

cleanup() {
    if [ "$PREPARED" -eq 1 ] && [ -f "$ORACLE_HIDDEN" ]; then
        mv "$ORACLE_HIDDEN" /app/legacy_parser 2>/dev/null || true
        chmod +x /app/legacy_parser 2>/dev/null || true
    fi
    rm -rf "$ORACLE_DIR" 2>/dev/null || true
}
trap cleanup EXIT

RESULT=0
chmod 700 "$ORACLE_DIR"
if [ -x /app/legacy_parser ] && mv /app/legacy_parser "$ORACLE_HIDDEN"; then
    PREPARED=1
    chmod 700 "$ORACLE_HIDDEN"

    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import random
import subprocess
import tempfile
import pytest

ORACLE_PATH = os.environ["VERIFIER_ORACLE_PATH"]
AGENT_PATH = "/home/user/process_data.py"


def generate_random_csv(num_rows):
    departments = ["Engineering", "Sales", "HR", "Marketing", "Finance"]

    # Generate unique employee IDs
    all_ids = random.sample(range(1, 1001), num_rows)

    rows = []
    generated_ids = []

    for i, emp_id in enumerate(all_ids):
        if i == 0:
            manager_id = ""
        else:
            # Pick a manager from previously generated to ensure valid tree/DAG
            manager_id = random.choice(generated_ids)

        dept = random.choice(departments)
        score = round(random.uniform(0.0, 100.0), 2)

        rows.append([emp_id, manager_id, dept, score])
        generated_ids.append(emp_id)

    # Shuffle rows so they are not strictly topologically sorted in the CSV
    random.shuffle(rows)
    return rows


@pytest.mark.parametrize("seed", range(50))
def test_fuzz_equivalence(seed):
    random.seed(seed)

    assert os.path.isfile(ORACLE_PATH), f"Oracle missing at protected verifier path"
    assert os.path.isfile(AGENT_PATH), f"Agent script missing at {AGENT_PATH}"
    assert not os.path.islink(AGENT_PATH), "Agent submission must be a regular Python script"

    with open(ORACLE_PATH, "rb") as oracle_file, open(AGENT_PATH, "rb") as agent_file:
        assert agent_file.read() != oracle_file.read(), "Agent submission is identical to the legacy executable"

    num_rows = random.randint(10, 200)
    csv_data = generate_random_csv(num_rows)

    with tempfile.NamedTemporaryFile(mode='w', suffix='.csv', delete=False) as tmp:
        writer = csv.writer(tmp)
        writer.writerows(csv_data)
        tmp_path = tmp.name
    os.chmod(tmp_path, 0o644)

    try:
        # Run the oracle from a root-only verifier directory. The original
        # /app/legacy_parser path is absent while the submitted script runs.
        oracle_cmd = [ORACLE_PATH, tmp_path]
        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_res.returncode == 0, f"Oracle failed on seed {seed}:\n{oracle_res.stderr}"

        # Run the submitted script as the unprivileged agent user with a clean
        # environment so it cannot access the protected verifier oracle.
        agent_cmd = [
            "runuser", "-u", "user", "--",
            "env", "-i",
            "HOME=/home/user", "USER=user", "LOGNAME=user",
            "PATH=/usr/local/bin:/usr/bin:/bin",
            "python3", AGENT_PATH, tmp_path,
        ]
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True, cwd="/home/user")
        assert agent_res.returncode == 0, f"Agent failed on seed {seed}:\n{agent_res.stderr}"

        # Parse JSON
        try:
            oracle_json = json.loads(oracle_res.stdout)
        except json.JSONDecodeError:
            pytest.fail(f"Oracle output is not valid JSON on seed {seed}:\n{oracle_res.stdout}")

        try:
            agent_json = json.loads(agent_res.stdout)
        except json.JSONDecodeError:
            pytest.fail(f"Agent output is not valid JSON on seed {seed}:\n{agent_res.stdout}")

        # Compare
        assert agent_json == oracle_json, (
            f"Output mismatch on seed {seed}.\n"
            f"Input CSV:\n{csv_data}\n"
            f"Oracle JSON:\n{json.dumps(oracle_json, indent=2)}\n"
            f"Agent JSON:\n{json.dumps(agent_json, indent=2)}"
        )

    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)
TEST_EOF

    if VERIFIER_ORACLE_PATH="$ORACLE_HIDDEN" python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
        RESULT=1
    fi
fi

echo "$RESULT" > /logs/verifier/reward.txt
exit 0
