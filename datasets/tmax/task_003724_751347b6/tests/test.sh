#!/bin/bash
set -u
mkdir -p /logs/verifier

INPUT=/home/user/transactions.jsonl
CSV=/home/user/top_nodes.csv
PROJECT=/home/user/graph_etl
MAIN=/home/user/graph_etl/src/main.rs
ORIGINAL=/tmp/verifier_original_transactions.jsonl
HIDDEN=/tmp/verifier_hidden_transactions.jsonl
STATUS=0

cp "$INPUT" "$ORIGINAL" || STATUS=1

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
from collections import Counter

def test_top_nodes_csv():
    jsonl_path = "/home/user/transactions.jsonl"
    csv_path = "/home/user/top_nodes.csv"

    assert os.path.exists(jsonl_path), f"Input file missing: {jsonl_path}"
    assert os.path.exists(csv_path), f"Output file missing: {csv_path}"

    # Recompute the expected top 3 nodes from the input data
    receivers = Counter()
    with open(jsonl_path, 'r') as f:
        for line in f:
            if line.strip():
                try:
                    data = json.loads(line)
                    if 'receiver' in data:
                        receivers[data['receiver']] += 1
                except json.JSONDecodeError:
                    continue

    # Sort by in_degree (descending), then node_id (ascending)
    sorted_nodes = sorted(receivers.items(), key=lambda x: (-x[1], x[0]))
    top_3 = sorted_nodes[:3]

    expected_lines = [f"{node},{count}" for node, count in top_3]

    # Read actual output
    with open(csv_path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} rows in CSV, got {len(actual_lines)}"

    for i, (expected, actual) in enumerate(zip(expected_lines, actual_lines)):
        assert actual == expected, f"Row {i+1} mismatch: expected '{expected}', got '{actual}'"
TEST_EOF

cat << 'HIDDEN_TEST_EOF' > /tmp/test_hidden_case.py
import json
from collections import Counter

INPUT = "/home/user/transactions.jsonl"
FIXTURE = "/tmp/verifier_hidden_transactions.jsonl"
CSV = "/home/user/top_nodes.csv"

def test_program_handles_changed_input():
    with open(INPUT, "rb") as actual, open(FIXTURE, "rb") as expected:
        assert actual.read() == expected.read(), "Program modified the transaction input"

    receivers = Counter()
    with open(FIXTURE, encoding="utf-8") as f:
        for line in f:
            if line.strip():
                receivers[json.loads(line)["receiver"]] += 1

    expected_lines = [f"{node},{count}" for node, count in sorted(
        receivers.items(), key=lambda item: (-item[1], item[0])
    )[:3]]

    with open(CSV, encoding="utf-8") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines
HIDDEN_TEST_EOF

run_program() {
    rm -f "$CSV" || return 1
    (cd "$PROJECT" && timeout 240 cargo run --quiet) || return 1
    test -f "$CSV" && test ! -L "$CSV"
}

verify_submission() {
    test -f "$MAIN" && test ! -L "$MAIN" && test -s "$MAIN" || return 1

    timeout 240 cargo metadata --manifest-path "$PROJECT/Cargo.toml" --no-deps --format-version 1 > /tmp/cargo_metadata.json || return 1
    python3 - << 'PY' || return 1
import json, os
with open('/tmp/cargo_metadata.json') as f:
    metadata = json.load(f)
main = os.path.realpath('/home/user/graph_etl/src/main.rs')
assert any(
    target.get('kind') == ['bin'] and os.path.realpath(target['src_path']) == main
    for package in metadata['packages']
    for target in package['targets']
), 'Cargo project does not compile src/main.rs as a binary target'
PY

    (cd "$PROJECT" && timeout 240 cargo clean && timeout 240 cargo build --quiet) || return 1

    run_program || return 1
    cmp -s "$INPUT" "$ORIGINAL" || return 1
    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1

    cat << 'DATA_EOF' > "$HIDDEN"
{"tx_id":"h1","sender":"S1","receiver":"Z","amount":1}
{"tx_id":"h2","sender":"S2","receiver":"A","amount":2}
{"tx_id":"h3","sender":"S3","receiver":"B","amount":3}
{"tx_id":"h4","sender":"S4","receiver":"Z","amount":4}
{"tx_id":"h5","sender":"S5","receiver":"A","amount":5}
{"tx_id":"h6","sender":"S6","receiver":"B","amount":6}
{"tx_id":"h7","sender":"S7","receiver":"Z","amount":7}
{"tx_id":"h8","sender":"S8","receiver":"A","amount":8}
{"tx_id":"h9","sender":"S9","receiver":"B","amount":9}
{"tx_id":"h10","sender":"S10","receiver":"Z","amount":10}
{"tx_id":"h11","sender":"S11","receiver":"Q","amount":11}
DATA_EOF
    cp "$HIDDEN" "$INPUT" || return 1
    run_program || return 1
    python3 -m pytest /tmp/test_hidden_case.py -x --tb=short || return 1
}

verify_submission || STATUS=1

# Restore the supplied input and leave the requested CSV generated from it.
cp "$ORIGINAL" "$INPUT" || STATUS=1
if test -f "$MAIN" && test ! -L "$MAIN"; then
    run_program || STATUS=1
    cmp -s "$INPUT" "$ORIGINAL" || STATUS=1
    python3 -m pytest /tmp/test_final_state.py -x --tb=short || STATUS=1
else
    STATUS=1
fi

if [ "$STATUS" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
