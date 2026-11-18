#!/bin/bash
set +e
mkdir -p /logs/verifier

verify_submission() {
    local original=/tmp/verifier_original_logs.jsonl
    local case1=/tmp/verifier_case1.jsonl
    local case2=/tmp/verifier_case2.jsonl
    local chosen=""

    cat > "$original" <<'EOF'
{"tx_id": "1", "src": "ROOT", "dst": "A", "amount": 50, "status": "SUCCESS"}
{"tx_id": "2", "src": "ROOT", "dst": "B", "amount": 30, "status": "SUCCESS"}
{"tx_id": "3", "src": "ROOT", "dst": "C", "amount": 10, "status": "SUCCESS"}
{"tx_id": "4", "src": "A", "dst": "D", "amount": 20, "status": "SUCCESS"}
{"tx_id": "5", "src": "A", "dst": "E", "amount": 10, "status": "FAILED"}
{"tx_id": "6", "src": "B", "dst": "D", "amount": 60, "status": "SUCCESS"}
{"tx_id": "7", "src": "B", "dst": "E", "amount": 80, "status": "SUCCESS"}
{"tx_id": "8", "src": "C", "dst": "F", "amount": 15, "status": "SUCCESS"}
{"tx_id": "9", "src": "C", "dst": "D", "amount": 90, "status": "SUCCESS"}
{"tx_id": "10", "src": "D", "dst": "G", "amount": 5, "status": "SUCCESS"}
{"tx_id": "11", "src": "ROOT", "dst": "X", "amount": 100, "status": "SUCCESS"}
{"tx_id": "12", "src": "X", "dst": "Y", "amount": 200, "status": "SUCCESS"}
{"tx_id": "13", "src": "Y", "dst": "Z", "amount": 300, "status": "SUCCESS"}
EOF

    cat > "$case1" <<'EOF'
{"tx_id":"a1","src":"ROOT","dst":"M","amount":7,"status":"SUCCESS"}
{"tx_id":"a2","src":"M","dst":"ALPHA","amount":11,"status":"SUCCESS"}
{"tx_id":"a3","src":"ROOT","dst":"N","amount":20,"status":"SUCCESS"}
{"tx_id":"a4","src":"N","dst":"ALPHA","amount":3,"status":"SUCCESS"}
{"tx_id":"a5","src":"N","dst":"BETA","amount":9,"status":"SUCCESS"}
{"tx_id":"a6","src":"M","dst":"IGNORED","amount":1000,"status":"FAILED"}
{"tx_id":"a7","src":"OTHER","dst":"BETA","amount":500,"status":"SUCCESS"}
EOF

    cat > "$case2" <<'EOF'
{"tx_id":"b1","src":"ROOT","dst":"P","amount":5,"status":"SUCCESS"}
{"tx_id":"b2","src":"ROOT","dst":"P","amount":40,"status":"SUCCESS"}
{"tx_id":"b3","src":"P","dst":"Q","amount":2,"status":"SUCCESS"}
{"tx_id":"b4","src":"P","dst":"Q","amount":8,"status":"SUCCESS"}
{"tx_id":"b5","src":"P","dst":"A_DEST","amount":1,"status":"SUCCESS"}
{"tx_id":"b6","src":"ROOT","dst":"R","amount":10,"status":"FAILED"}
{"tx_id":"b7","src":"R","dst":"Q","amount":100,"status":"SUCCESS"}
EOF

    # The raw input must still be the supplied data, not an agent-rewritten fixture.
    [ -f /home/user/data/logs.jsonl ] || return 1
    cmp -s /home/user/data/logs.jsonl "$original" || return 1

    cat > /tmp/validate_etl.py <<'PYEOF'
import csv
import json
import os
import sys

source, output = sys.argv[1], "/home/user/data/max_2hop.csv"
edges = []
with open(source) as f:
    for line in f:
        if line.strip():
            r = json.loads(line)
            if r.get("status") == "SUCCESS":
                edges.append((r["src"], r["dst"], r["amount"]))

best = {}
for src1, mid, amount1 in edges:
    if src1 != "ROOT":
        continue
    for src2, dst, amount2 in edges:
        if src2 == mid:
            total = amount1 + amount2
            if dst not in best or total > best[dst]:
                best[dst] = total

expected = [["Destination", "MaxTotalAmount"]]
expected += [[dst, str(best[dst])] for dst in sorted(best)]
if not os.path.isfile(output):
    raise SystemExit(1)
with open(output, newline="") as f:
    actual = [row for row in csv.reader(f) if row]
if actual != expected:
    raise SystemExit(1)
PYEOF

    mapfile -d '' candidates < <(find /home/user -type f \
        ! -path '/home/user/data/logs.jsonl' \
        ! -path '/home/user/data/max_2hop.csv' \
        ! -name '.*' -print0 2>/dev/null)

    for script in "${candidates[@]}"; do
        # It must be a syntactically valid Bash script and must not invoke the
        # explicitly prohibited Python or Perl interpreters.
        bash -n "$script" >/dev/null 2>&1 || continue
        if grep -Eiv '^[[:space:]]*#' "$script" 2>/dev/null | \
           grep -Eq '(^|[^[:alnum:]_])(python([0-9.]*)?|perl)([^[:alnum:]_]|$)'; then
            continue
        fi

        candidate_ok=1
        for input_case in "$case1" "$case2" "$original"; do
            cp "$input_case" /home/user/data/logs.jsonl || { candidate_ok=0; break; }
            rm -f /home/user/data/max_2hop.csv
            (cd /home/user && timeout 15 bash "$script") >/tmp/etl.stdout 2>/tmp/etl.stderr
            [ $? -eq 0 ] || { candidate_ok=0; break; }
            cmp -s /home/user/data/logs.jsonl "$input_case" || { candidate_ok=0; break; }
            python3 /tmp/validate_etl.py "$input_case" || { candidate_ok=0; break; }
        done

        if [ "$candidate_ok" -eq 1 ]; then
            chosen="$script"
            break
        fi
    done

    [ -n "$chosen" ] || return 1

    # Execute the discovered Bash ETL once more on the original supplied input.
    cp "$original" /home/user/data/logs.jsonl || return 1
    rm -f /home/user/data/max_2hop.csv
    (cd /home/user && timeout 15 bash "$chosen") >/tmp/etl.stdout 2>/tmp/etl.stderr || return 1
    cmp -s /home/user/data/logs.jsonl "$original" || return 1
    python3 /tmp/validate_etl.py "$original" || return 1

    # Preserve the original verifier's assertions.
    cat > /tmp/test_final_state.py <<'TEST_EOF'
import os
import json
import csv
from collections import defaultdict

def test_max_2hop_csv_exists_and_correct():
    logs_file = "/home/user/data/logs.jsonl"
    output_file = "/home/user/data/max_2hop.csv"

    assert os.path.exists(logs_file), f"Raw data file {logs_file} is missing."
    assert os.path.exists(output_file), f"Output file {output_file} was not created."

    edges = []
    with open(logs_file, "r") as f:
        for line in f:
            if not line.strip():
                continue
            record = json.loads(line)
            if record.get("status") == "SUCCESS":
                edges.append((record["src"], record["dst"], record["amount"]))

    root_edges = {dst: amount for src, dst, amount in edges if src == "ROOT"}
    max_2hop = defaultdict(int)
    for src, dst, amount in edges:
        if src in root_edges:
            total_amount = root_edges[src] + amount
            if total_amount > max_2hop[dst]:
                max_2hop[dst] = total_amount

    expected_rows = sorted([[dst, str(max_2hop[dst])] for dst in max_2hop.keys()], key=lambda x: x[0])
    expected_header = ["Destination", "MaxTotalAmount"]

    actual_data = []
    with open(output_file, "r") as f:
        reader = csv.reader(f)
        try:
            actual_header = next(reader)
        except StopIteration:
            actual_header = []
        for row in reader:
            if row:
                actual_data.append(row)

    assert actual_header == expected_header, f"Header is incorrect. Expected {expected_header}, got {actual_header}"
    assert actual_data == expected_rows, f"Data rows are incorrect. Expected {expected_rows}, got {actual_data}"
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
}

if verify_submission; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
