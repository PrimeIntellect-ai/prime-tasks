#!/bin/bash
set +e
mkdir -p /logs/verifier

APP_DIR=/home/user/app
SO_FILE="$APP_DIR/libuserhash.so"
SERVER_PID=""
ORIGINAL_BACKUP=""
SELECTED_SERVER=""

kill_listener() {
    python3 - <<'PY' >/dev/null 2>&1
import os, signal
inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                if fields[1].rsplit(':', 1)[-1].upper() == '1F90' and fields[3] == '0A':
                    inodes.add(fields[9])
    except OSError:
        pass
for entry in os.listdir('/proc'):
    if not entry.isdigit() or int(entry) == os.getpid():
        continue
    fd_dir = f'/proc/{entry}/fd'
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f'{fd_dir}/{fd}')
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                try:
                    os.kill(int(entry), signal.SIGTERM)
                except (ProcessLookupError, PermissionError):
                    pass
                break
    except OSError:
        pass
PY
    sleep 0.3
}

stop_server() {
    if [ -n "$SERVER_PID" ]; then
        kill -- -"$SERVER_PID" >/dev/null 2>&1 || kill "$SERVER_PID" >/dev/null 2>&1 || true
        wait "$SERVER_PID" >/dev/null 2>&1 || true
        SERVER_PID=""
    fi
    kill_listener
}

cleanup() {
    stop_server
    if [ -n "$ORIGINAL_BACKUP" ] && [ -f "$ORIGINAL_BACKUP" ]; then
        mv -f "$ORIGINAL_BACKUP" "$SO_FILE"
    fi
}
trap cleanup EXIT

launch_server() {
    local candidate="$1"
    stop_server
    cd "$APP_DIR" || return 1
    case "$candidate" in
        *.py)
            setsid python3 "$candidate" >/tmp/submission-server.log 2>&1 &
            ;;
        *.js)
            command -v node >/dev/null 2>&1 || return 1
            setsid node "$candidate" >/tmp/submission-server.log 2>&1 &
            ;;
        *)
            if [ -x "$candidate" ]; then
                setsid "$candidate" >/tmp/submission-server.log 2>&1 &
            else
                setsid python3 "$candidate" >/tmp/submission-server.log 2>&1 &
            fi
            ;;
    esac
    SERVER_PID=$!
    for _ in $(seq 1 100); do
        if curl -fsS --max-time 1 http://127.0.0.1:8080/api/employees/1 >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.1
    done
    stop_server
    return 1
}

candidates=()
[ -f "$APP_DIR/server" ] && candidates+=("$APP_DIR/server")
for candidate in "$APP_DIR"/server.*; do
    [ -f "$candidate" ] && candidates+=("$candidate")
done

kill_listener
for candidate in "${candidates[@]}"; do
    if launch_server "$candidate"; then
        SELECTED_SERVER="$candidate"
        break
    fi
done

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import sqlite3
import urllib.error
import urllib.request
import pytest

APP_DIR = "/home/user/app"
SO_FILE = os.path.join(APP_DIR, "libuserhash.so")
DB_FILE = os.path.join(APP_DIR, "data.db")
RESULT_JSON = "/home/user/result.json"
BASE_URL = "http://127.0.0.1:8080/api/employees"


def load_hash_function():
    library = ctypes.CDLL(SO_FILE)
    function = library.compute_hash
    function.argtypes = [ctypes.c_int]
    function.restype = ctypes.c_int
    return function


def test_shared_library_exists():
    assert os.path.isfile(SO_FILE), f"Shared library {SO_FILE} does not exist."
    with open(SO_FILE, "rb") as f:
        magic = f.read(4)
    assert magic == b"\x7fELF", f"{SO_FILE} is not a valid ELF file."

    compute_hash = load_hash_function()
    for employee_id in (0, 1, 2, 17, 101):
        expected = (employee_id * 97) ^ 0x5A
        assert compute_hash(employee_id) == expected, \
            f"compute_hash({employee_id}) returned an incorrect value."


def test_database_schema_and_data():
    assert os.path.isfile(DB_FILE), f"Database file {DB_FILE} does not exist."

    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='employees';")
    table = cursor.fetchone()
    assert table is not None, "Table 'employees' does not exist in the database."

    cursor.execute("PRAGMA table_info(employees);")
    columns = {row[1]: row[2].upper() for row in cursor.fetchall()}

    expected_columns = {"id": "INTEGER", "first_name": "TEXT", "last_name": "TEXT", "age_years": "INTEGER"}

    for col_name, col_type in expected_columns.items():
        assert col_name in columns, f"Column '{col_name}' is missing from 'employees' table."
        assert col_type in columns[col_name], f"Column '{col_name}' should be of type {col_type}."

    assert "full_name" not in columns, "Column 'full_name' should have been dropped."
    assert "age" not in columns, "Column 'age' should have been dropped/renamed."

    cursor.execute("SELECT id, first_name, last_name, age_years FROM employees ORDER BY id;")
    rows = cursor.fetchall()

    assert len(rows) == 2, f"Expected 2 rows in 'employees' table, found {len(rows)}."
    assert rows[0] == (1, 'Alice', 'Smith', 30), f"First row data mismatch: {rows[0]}"
    assert rows[1] == (2, 'Bob', 'Jones', 45), f"Second row data mismatch: {rows[1]}"
    conn.close()


def test_result_json():
    assert os.path.isfile(RESULT_JSON), f"Result file {RESULT_JSON} does not exist."

    with open(RESULT_JSON, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{RESULT_JSON} does not contain valid JSON.")

    expected_data = {
        "id": 1,
        "first_name": "Alice",
        "last_name": "Smith",
        "age_years": 30,
        "hash": load_hash_function()(1),
    }

    for key, value in expected_data.items():
        assert key in data, f"Key '{key}' missing from JSON response."
        assert data[key] == value, f"Value for '{key}' is incorrect. Expected {value}, got {data[key]}."


def get_employee(employee_id):
    with urllib.request.urlopen(f"{BASE_URL}/{employee_id}", timeout=3) as response:
        assert response.status == 200
        return json.loads(response.read().decode("utf-8"))


def test_live_rest_api():
    compute_hash = load_hash_function()
    expected = {
        1: {"id": 1, "first_name": "Alice", "last_name": "Smith", "age_years": 30, "hash": compute_hash(1)},
        2: {"id": 2, "first_name": "Bob", "last_name": "Jones", "age_years": 45, "hash": compute_hash(2)},
    }
    for employee_id, expected_data in expected.items():
        assert get_employee(employee_id) == expected_data

    with pytest.raises(urllib.error.HTTPError) as error:
        urllib.request.urlopen(f"{BASE_URL}/999999", timeout=3)
    assert error.value.code == 404
TEST_EOF

all_ok=1
if [ -z "$SELECTED_SERVER" ]; then
    all_ok=0
fi

if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    all_ok=0
fi

# Replace the library temporarily with an unpredictable implementation, restart
# the submitted server, and verify that API hashes come from the shared object.
if [ "$all_ok" -eq 1 ]; then
    stop_server
    ORIGINAL_BACKUP="/tmp/libuserhash.original.$$"
    cp -p "$SO_FILE" "$ORIGINAL_BACKUP" || all_ok=0

    if [ "$all_ok" -eq 1 ]; then
        read -r PROBE_A PROBE_B < <(python3 - <<'PY'
import secrets
print(secrets.randbelow(7000) + 1001, secrets.randbelow(500000) + 200001)
PY
)
        cat > /tmp/probe_userhash.c <<EOF
int compute_hash(int id) {
    return id * $PROBE_A + $PROBE_B;
}
EOF
        gcc -shared -fPIC /tmp/probe_userhash.c -o /tmp/probe_libuserhash.so || all_ok=0
        if [ "$all_ok" -eq 1 ]; then
            mv -f /tmp/probe_libuserhash.so "$SO_FILE" || all_ok=0
        fi
    fi

    if [ "$all_ok" -eq 1 ] && ! launch_server "$SELECTED_SERVER"; then
        all_ok=0
    fi

    if [ "$all_ok" -eq 1 ]; then
        PROBE_A="$PROBE_A" PROBE_B="$PROBE_B" python3 - <<'PY' || all_ok=0
import json, os, urllib.request
A = int(os.environ['PROBE_A'])
B = int(os.environ['PROBE_B'])
records = {
    1: ("Alice", "Smith", 30),
    2: ("Bob", "Jones", 45),
}
for employee_id, (first, last, age) in records.items():
    with urllib.request.urlopen(f'http://127.0.0.1:8080/api/employees/{employee_id}', timeout=3) as response:
        assert response.status == 200
        data = json.loads(response.read().decode('utf-8'))
    assert data == {
        'id': employee_id,
        'first_name': first,
        'last_name': last,
        'age_years': age,
        'hash': employee_id * A + B,
    }
PY
    fi
fi

if [ "$all_ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

exit 0
