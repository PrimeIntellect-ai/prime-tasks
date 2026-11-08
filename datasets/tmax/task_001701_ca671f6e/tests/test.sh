#!/bin/bash
set -u
mkdir -p /logs/verifier
reward=0
trap 'echo "$reward" > /logs/verifier/reward.txt' EXIT

run_verification() {
    # Derive the expected output independently before executing the submission.
    python3 - <<'PY'
source = '/app/access.log'
destination = '/tmp/.verifier_expected_filtered.log'
counts = {}
written = 0
with open(source, 'r') as src, open(destination, 'w') as dst:
    for line in src:
        fields = line.split()
        if len(fields) != 4:
            continue
        timestamp, ip = fields[0], fields[1]
        if ip == '10.0.5.22':
            continue
        try:
            minute = int(timestamp) // 60
        except ValueError:
            continue
        key = (ip, minute)
        counts[key] = counts.get(key, 0) + 1
        if counts[key] <= 5:
            dst.write(line)
            written += 1
if written == 0:
    raise SystemExit('Expected output unexpectedly empty')
PY
    chmod 600 /tmp/.verifier_expected_filtered.log || return 1

    rm -f /home/user/filtered.log
    timeout 60s runuser -u user -- /home/user/filter_logs.sh /app/access.log || return 1

    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os


def evaluate(agent_file, golden_file):
    try:
        with open(agent_file, 'r') as f:
            agent_lines = [l.strip() for l in f.readlines() if l.strip()]
    except FileNotFoundError:
        return 0.0

    with open(golden_file, 'r') as f:
        golden_lines = [l.strip() for l in f.readlines() if l.strip()]

    if not golden_lines:
        return 0.0

    agent_set = set(agent_lines)
    golden_set = set(golden_lines)
    correct = len(agent_set.intersection(golden_set))
    precision = correct / len(agent_set) if agent_set else 0
    recall = correct / len(golden_set) if golden_set else 0

    if precision + recall == 0:
        return 0.0

    f1 = 2 * (precision * recall) / (precision + recall)
    if agent_lines == golden_lines:
        f1 = 1.0
    elif f1 == 1.0:
        f1 = 0.99
    return f1


def test_filtered_log_accuracy():
    agent_file = '/home/user/filtered.log'
    golden_file = '/tmp/.verifier_expected_filtered.log'

    assert os.path.exists(agent_file), f"Agent output file not found: {agent_file}"
    assert os.path.exists(golden_file), f"Golden reference file not found: {golden_file}"

    score = evaluate(agent_file, golden_file)
    assert score >= 1.0, (
        f"Filtered log accuracy (F1 score) is {score:.4f}, expected 1.0 for an exact match. "
        "Ensure logs are filtered correctly and in the original order."
    )


def test_script_exists_and_executable():
    script_path = '/home/user/filter_logs.sh'
    assert os.path.isfile(script_path), f"Script not found: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
}

if run_verification 2>&1; then
    reward=1
fi
exit 0
