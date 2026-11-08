#!/bin/bash
set +e
mkdir -p /logs/verifier

DUMP=/home/user/data/dump.nt
BACKUP=/tmp/dump.nt.verifier-backup
ENGINE_TEST=/app/vendored/graph-etl-engine/verifier_deadlock_test.go
VERIFY_BIN=/tmp/etl-server-verifier

kill_listener() {
python3 - <<'PY'
import os, signal, time
inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        with open(table) as f:
            next(f)
            for line in f:
                cols = line.split()
                if cols[3] == '0A' and int(cols[1].split(':')[-1], 16) == 8080:
                    inodes.add(cols[9])
    except OSError:
        pass
pids = set()
for name in os.listdir('/proc'):
    if not name.isdigit():
        continue
    fd_dir = f'/proc/{name}/fd'
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f'{fd_dir}/{fd}')
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                pids.add(int(name))
                break
    except OSError:
        pass
for pid in pids:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
time.sleep(0.3)
for pid in pids:
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
PY
}

cleanup() {
    kill_listener >/dev/null 2>&1 || true
    rm -f "$ENGINE_TEST" "$VERIFY_BIN"
    if [ -f "$BACKUP" ]; then
        cp "$BACKUP" "$DUMP"
        rm -f "$BACKUP"
    fi
}
trap cleanup EXIT

run_checks() (
set -e

# Preserve the original API assertions against the server the agent started.
cat > /tmp/test_original_api.py <<'PY'
import requests
import pytest

BASE_URL = "http://127.0.0.1:8080"
AUTH_HEADER = {"Authorization": "Bearer SecureGraphETL2024"}

def test_api_unauthorized():
    try:
        response = requests.get(f"{BASE_URL}/summary?dept=Sales", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API server at {BASE_URL}: {e}")
    assert response.status_code == 401, (
        f"Expected HTTP 401 Unauthorized when no token is provided, but got "
        f"{response.status_code}. Response: {response.text}"
    )

def test_api_sales_summary():
    try:
        response = requests.get(f"{BASE_URL}/summary?dept=Sales", headers=AUTH_HEADER, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API server at {BASE_URL}: {e}")
    assert response.status_code == 200, (
        f"Expected HTTP 200 OK for Sales summary, but got {response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response, but failed to parse: {response.text}")
    assert data.get("department") == "Sales", f"Expected department 'Sales', got {data.get('department')}"
    assert data.get("manager") == "Bob", f"Expected manager 'Bob', got {data.get('manager')}"
    assert data.get("employee_count") == 2, f"Expected employee_count 2, got {data.get('employee_count')}"
    assert data.get("total_salary") == 140000, f"Expected total_salary 140000, got {data.get('total_salary')}"

def test_api_engineering_summary():
    try:
        response = requests.get(f"{BASE_URL}/summary?dept=Engineering", headers=AUTH_HEADER, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API server at {BASE_URL}: {e}")
    assert response.status_code == 200, (
        f"Expected HTTP 200 OK for Engineering summary, but got {response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response, but failed to parse: {response.text}")
    assert data.get("department") == "Engineering", f"Expected department 'Engineering', got {data.get('department')}"
    assert data.get("manager") == "Alice", f"Expected manager 'Alice', got {data.get('manager')}"
    assert data.get("employee_count") == 3, f"Expected employee_count 3, got {data.get('employee_count')}"
    assert data.get("total_salary") == 280000, f"Expected total_salary 280000, got {data.get('total_salary')}"
PY
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_original_api.py -x --tb=short

# Check that the requested project and local module replacement are real and buildable.
test -f /home/user/etl-server/go.mod
test -f /app/vendored/graph-etl-engine/transaction.go
cd /home/user/etl-server
go mod edit -json >/tmp/etl_go_mod.json
REPLACE_DIR=$(go list -m -f '{{if .Replace}}{{.Replace.Dir}}{{end}}' graphetl)
test -n "$REPLACE_DIR"
test "$(readlink -f "$REPLACE_DIR")" = "$(readlink -f /app/vendored/graph-etl-engine)"
go list -deps . | grep -Fx graphetl >/dev/null

# Require actual engine edge loading and a goroutine in the ETL implementation.
python3 - <<'PY'
from pathlib import Path
import re
root = Path('/home/user/etl-server')
files = [p for p in root.rglob('*.go') if not p.name.endswith('_test.go')]
assert files, 'No Go implementation files found in /home/user/etl-server'
src = '\n'.join(p.read_text(errors='replace') for p in files)
assert re.search(r'["`]graphetl["`]', src), 'The ETL server does not import graphetl'
assert re.search(r'\.AddEdge\s*\(', src), 'The ETL server does not load relationships through Engine.AddEdge'
assert re.search(r'\bgo\s+(?:func\s*\(|[A-Za-z_][\w.]*\s*\()', src), 'No concurrent goroutine-based loading was found'
PY

go build -o "$VERIFY_BIN" .

# Exercise the repaired engine in the lock ordering that deterministically deadlocks
# the original implementation: each reciprocal call is queued on its first lock.
cat > "$ENGINE_TEST" <<'GO'
package graphetl

import (
    "testing"
    "time"
)

func TestVerifierReciprocalEdgesDoNotDeadlock(t *testing.T) {
    a := &Node{ID: "A"}
    b := &Node{ID: "B"}
    e := &Engine{nodes: map[string]*Node{"A": a, "B": b}}

    a.mu.Lock()
    b.mu.Lock()
    done := make(chan struct{}, 2)

    go func() { e.AddEdge("B", "A"); done <- struct{}{} }()
    time.Sleep(100 * time.Millisecond)
    go func() { e.AddEdge("A", "B"); done <- struct{}{} }()
    time.Sleep(100 * time.Millisecond)

    a.mu.Unlock()
    time.Sleep(100 * time.Millisecond)
    b.mu.Unlock()

    for i := 0; i < 2; i++ {
        select {
        case <-done:
        case <-time.After(2 * time.Second):
            t.Fatal("reciprocal concurrent AddEdge calls deadlocked")
        }
    }
}
GO
cd /app/vendored/graph-etl-engine
go test -run '^TestVerifierReciprocalEdgesDoNotDeadlock$' -count=1 -timeout=8s
rm -f "$ENGINE_TEST"

# Replace the dump with randomized data unknown to the submitted server, then
# rebuild and restart it. This rejects fixed Sales/Engineering response tables.
cp "$DUMP" "$BACKUP"
python3 - <<'PY'
import json, secrets, random
suffix = secrets.token_hex(6)
d1, d2, d3 = [f'Dept{i}_{suffix}' for i in range(1, 4)]
people = [f'Person{i}_{suffix}' for i in range(7)]
salaries = [secrets.randbelow(50000) + 60000 for _ in people]
triples = []
def edge(s, p, o): triples.append(f'<{s}> <{p}> <{o}> .')
def salary(person, amount): triples.append(f'<{person}> <HAS_SALARY> "{amount}" .')

# Department 1: manager is also one of three workers.
edge(people[0], 'MANAGES', d1)
for p in people[0:3]: edge(p, 'WORKS_IN', d1)
# Department 2: manager is also one of two workers.
edge(people[3], 'MANAGES', d2)
for p in people[3:5]: edge(p, 'WORKS_IN', d2)
# Department 3: its manager has a salary but does not work in that department.
edge(people[5], 'MANAGES', d3)
edge(people[6], 'WORKS_IN', d3)
for p, amount in zip(people, salaries): salary(p, amount)
random.SystemRandom().shuffle(triples)
with open('/home/user/data/dump.nt', 'w') as f:
    f.write('\n'.join(triples) + '\n')
expected = {
    d1: {'department': d1, 'manager': people[0], 'employee_count': 3, 'total_salary': sum(salaries[0:3])},
    d2: {'department': d2, 'manager': people[3], 'employee_count': 2, 'total_salary': sum(salaries[3:5])},
    d3: {'department': d3, 'manager': people[5], 'employee_count': 1, 'total_salary': salaries[6]},
}
with open('/tmp/dynamic_expected.json', 'w') as f: json.dump(expected, f)
PY

kill_listener
cd /home/user/etl-server
"$VERIFY_BIN" >/tmp/etl-server-verifier.log 2>&1 &
SERVER_PID=$!

READY=0
for _ in $(seq 1 50); do
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        cat /tmp/etl-server-verifier.log
        exit 1
    fi
    if curl -sS --max-time 1 -o /dev/null -H 'Authorization: Bearer SecureGraphETL2024' 'http://127.0.0.1:8080/summary?dept=probe'; then
        READY=1
        break
    fi
    sleep 0.1
done
test "$READY" = 1

cat > /tmp/test_dynamic_api.py <<'PY'
import json
import requests

BASE = 'http://127.0.0.1:8080'
GOOD = {'Authorization': 'Bearer SecureGraphETL2024'}
with open('/tmp/dynamic_expected.json') as f:
    EXPECTED = json.load(f)

def test_authentication_for_dynamic_request():
    dept = next(iter(EXPECTED))
    assert requests.get(f'{BASE}/summary', params={'dept': dept}, timeout=5).status_code == 401
    assert requests.get(f'{BASE}/summary', params={'dept': dept}, headers={'Authorization': 'Bearer wrong'}, timeout=5).status_code == 401

def test_summaries_are_derived_from_replacement_dump():
    for dept, expected in EXPECTED.items():
        response = requests.get(f'{BASE}/summary', params={'dept': dept}, headers=GOOD, timeout=5)
        assert response.status_code == 200, response.text
        assert response.json() == expected
PY
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_dynamic_api.py -x --tb=short
)

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
