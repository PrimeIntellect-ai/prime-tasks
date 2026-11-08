#!/bin/bash
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

CSV_BACKUP="/tmp/transfers.csv.verifier.$$"
SQLITE_REAL="/tmp/sqlite3.real.verifier.$$"
SQLITE_LOG="/tmp/sqlite3.trace.verifier.$$"

cleanup() {
    if [ -f "$CSV_BACKUP" ]; then
        cp "$CSV_BACKUP" /home/user/transfers.csv
        rm -f "$CSV_BACKUP"
    fi
    if [ -f "$SQLITE_REAL" ]; then
        rm -f /usr/bin/sqlite3
        mv "$SQLITE_REAL" /usr/bin/sqlite3
    fi
    rm -f "$SQLITE_LOG"
}
trap cleanup EXIT

if ! cp /home/user/transfers.csv "$CSV_BACKUP"; then
    exit 0
fi
if [ ! -x /usr/bin/sqlite3 ] || ! mv /usr/bin/sqlite3 "$SQLITE_REAL"; then
    exit 0
fi

cat > /usr/bin/sqlite3 <<WRAPPER_EOF
#!/bin/bash
capture=\$(mktemp /tmp/sqlite3.stdin.XXXXXX) || exit 125
cat > "\$capture"
{
    printf '%s\\n' '--- sqlite3 invocation ---'
    printf 'ARG: %s\\n' "\$@"
    cat "\$capture"
} >> "$SQLITE_LOG"
"$SQLITE_REAL" "\$@" < "\$capture"
status=\$?
rm -f "\$capture"
exit \$status
WRAPPER_EOF
chmod 755 /usr/bin/sqlite3
: > "$SQLITE_LOG"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import json
import csv
import secrets
import subprocess
from collections import defaultdict

CSV_PATH = '/home/user/transfers.csv'
OUTPUT_PATH = '/home/user/audit_results.json'
SCRIPT_PATH = '/home/user/run_audit.sh'
SQLITE_LOG = os.environ['SQLITE_LOG']


def compute_expected_results(csv_path):
    transactions = []
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            transactions.append({
                'tx_id': int(row['tx_id']),
                'sender': row['sender'],
                'receiver': row['receiver'],
                'amount': float(row['amount'])
            })

    # Build graph
    graph = defaultdict(set)
    degrees = defaultdict(int)

    for tx in transactions:
        u = tx['sender']
        v = tx['receiver']
        graph[u].add(v)
        degrees[u] += 1
        degrees[v] += 1

    # Find 3-cycles
    cycle_accounts = set()
    for u in graph:
        for v in graph[u]:
            for w in graph[v]:
                if u in graph[w]:
                    cycle_accounts.update([u, v, w])

    cycle_accounts_sorted = sorted(list(cycle_accounts))

    # Find highest degree cycle account
    highest_degree_account = None
    max_degree = -1
    for acc in cycle_accounts_sorted:
        if degrees[acc] > max_degree:
            max_degree = degrees[acc]
            highest_degree_account = acc

    # Find top 2 transactions between cycle accounts
    cycle_txs = [tx for tx in transactions if tx['sender'] in cycle_accounts and tx['receiver'] in cycle_accounts]
    cycle_txs_sorted = sorted(cycle_txs, key=lambda x: x['amount'], reverse=True)
    top_cycle_transactions = [tx['tx_id'] for tx in cycle_txs_sorted[:2]]

    return {
        "cycle_accounts": cycle_accounts_sorted,
        "highest_degree_cycle_account": highest_degree_account,
        "top_cycle_transactions": top_cycle_transactions
    }


def read_and_assert_output(expected):
    assert os.path.isfile(OUTPUT_PATH), "The output file /home/user/audit_results.json is missing."
    with open(OUTPUT_PATH, 'r') as f:
        try:
            actual = json.load(f)
        except json.JSONDecodeError:
            assert False, "/home/user/audit_results.json is not a valid JSON file."

    assert "cycle_accounts" in actual, "Missing 'cycle_accounts' in JSON output."
    assert "highest_degree_cycle_account" in actual, "Missing 'highest_degree_cycle_account' in JSON output."
    assert "top_cycle_transactions" in actual, "Missing 'top_cycle_transactions' in JSON output."
    assert actual["cycle_accounts"] == expected["cycle_accounts"], f"Expected cycle_accounts to be {expected['cycle_accounts']}, but got {actual['cycle_accounts']}."
    assert actual["highest_degree_cycle_account"] == expected["highest_degree_cycle_account"], f"Expected highest_degree_cycle_account to be {expected['highest_degree_cycle_account']}, but got {actual['highest_degree_cycle_account']}."
    assert actual["top_cycle_transactions"] == expected["top_cycle_transactions"], f"Expected top_cycle_transactions to be {expected['top_cycle_transactions']}, but got {actual['top_cycle_transactions']}."


def execute_script():
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    open(SQLITE_LOG, 'w').close()
    result = subprocess.run(
        [SCRIPT_PATH], cwd='/home/user', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, f"run_audit.sh failed with exit code {result.returncode}: {result.stderr}"
    with open(SQLITE_LOG, 'r', errors='replace') as f:
        trace = f.read()
    assert '--- sqlite3 invocation ---' in trace, "run_audit.sh did not invoke sqlite3."
    assert re.search(r'(?i)(select|with|create|insert|\\.import|\\.read)', trace), \
        "No SQL query or SQLite import activity was supplied to sqlite3."


def write_csv(rows):
    with open(CSV_PATH, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['tx_id', 'sender', 'receiver', 'amount'])
        writer.writerows(rows)


def generated_cases():
    tag = secrets.token_hex(5).upper()
    a, b, c = [f'{tag}_{x}' for x in ('A', 'B', 'C')]
    d, e, f = [f'{tag}_{x}' for x in ('D', 'E', 'F')]
    x, y = f'{tag}_OUT1', f'{tag}_OUT2'
    base = secrets.randbelow(5000) + 100
    rows1 = [
        (101, a, b, base + 1), (102, b, c, base + 2), (103, c, a, base + 3),
        (104, d, e, base + 4), (105, e, f, base + 5), (106, f, d, base + 6),
        (107, a, x, base + 7), (108, x, a, base + 8), (109, a, y, base + 9),
        (1701, a, d, base + 50000), (1702, d, b, base + 40000),
    ]

    tag2 = secrets.token_hex(5).upper()
    p, q, r, s, t, u, v, w = [f'{tag2}_{x}' for x in ('P','Q','R','S','T','U','V','W')]
    outsider = f'{tag2}_OUT'
    base2 = secrets.randbelow(5000) + 200
    rows2 = [
        (301, p, q, base2 + 1), (302, q, r, base2 + 2), (303, r, p, base2 + 3),
        (304, p, s, base2 + 4), (305, s, t, base2 + 5), (306, t, p, base2 + 6),
        (307, u, v, base2 + 7), (308, v, w, base2 + 8), (309, w, u, base2 + 9),
        (310, t, outsider, base2 + 10), (311, outsider, t, base2 + 11),
        (2301, q, u, base2 + 70000), (2302, w, s, base2 + 60000),
    ]
    return [rows1, rows2]


def test_script_artifact_and_execution():
    assert os.path.isfile(SCRIPT_PATH), "The required /home/user/run_audit.sh script is missing."
    assert not os.path.islink(SCRIPT_PATH), "run_audit.sh must be a regular script, not a symbolic link."
    assert os.access(SCRIPT_PATH, os.X_OK), "run_audit.sh is not executable."
    with open(SCRIPT_PATH, 'rb') as f:
        first_line = f.readline(256).decode('utf-8', errors='replace')
    assert re.match(r'^#!.*\\bbash\\b', first_line), "run_audit.sh must be a Bash script with a Bash shebang."
    execute_script()


def test_audit_results_exists():
    assert os.path.isfile('/home/user/audit_results.json'), "The output file /home/user/audit_results.json is missing."


def test_audit_results_content():
    csv_path = '/home/user/transfers.csv'
    assert os.path.isfile(csv_path), f"The input file {csv_path} is missing."

    expected = compute_expected_results(csv_path)

    with open('/home/user/audit_results.json', 'r') as f:
        try:
            actual = json.load(f)
        except json.JSONDecodeError:
            assert False, "/home/user/audit_results.json is not a valid JSON file."

    assert "cycle_accounts" in actual, "Missing 'cycle_accounts' in JSON output."
    assert "highest_degree_cycle_account" in actual, "Missing 'highest_degree_cycle_account' in JSON output."
    assert "top_cycle_transactions" in actual, "Missing 'top_cycle_transactions' in JSON output."

    assert actual["cycle_accounts"] == expected["cycle_accounts"], f"Expected cycle_accounts to be {expected['cycle_accounts']}, but got {actual['cycle_accounts']}."
    assert actual["highest_degree_cycle_account"] == expected["highest_degree_cycle_account"], f"Expected highest_degree_cycle_account to be {expected['highest_degree_cycle_account']}, but got {actual['highest_degree_cycle_account']}."
    assert actual["top_cycle_transactions"] == expected["top_cycle_transactions"], f"Expected top_cycle_transactions to be {expected['top_cycle_transactions']}, but got {actual['top_cycle_transactions']}."


def test_script_on_unseen_inputs():
    for rows in generated_cases():
        write_csv(rows)
        expected = compute_expected_results(CSV_PATH)
        execute_script()
        read_and_assert_output(expected)
TEST_EOF

if SQLITE_LOG="$SQLITE_LOG" python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
