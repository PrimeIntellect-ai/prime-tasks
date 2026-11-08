#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import pytest

CLEAN_FILE = "/home/user/tickets_clean.jsonl"

@pytest.fixture
def clean_data():
    assert os.path.exists(CLEAN_FILE), f"The output file {CLEAN_FILE} does not exist."

    records = {}
    with open(CLEAN_FILE, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                data = json.loads(line)
            except json.JSONDecodeError as e:
                pytest.fail(f"Failed to parse JSON on line {line_num} of {CLEAN_FILE}: {e}")

            assert "filename" in data, f"Record on line {line_num} is missing the 'filename' key."
            records[data["filename"]] = data

    return records

def test_output_file_exists_and_has_five_records(clean_data):
    assert len(clean_data) == 5, f"Expected 5 records in {CLEAN_FILE}, found {len(clean_data)}."

def test_record_keys(clean_data):
    expected_keys = {"date", "email", "error_code", "message", "filename"}
    for filename, record in clean_data.items():
        assert set(record.keys()) == expected_keys, f"Record for {filename} does not have the exact expected keys. Found: {set(record.keys())}"

def test_ticket_1_extraction(clean_data):
    record = clean_data.get("ticket_1.txt")
    assert record is not None, "ticket_1.txt record not found."
    assert record["date"] == "2023-10-01"
    assert record["email"] == "alice@example.com"
    assert record["error_code"] == "ERR_404"
    assert "The requested file was not found." in record["message"]
    assert record["message"] == "The requested file was not found."

def test_ticket_2_imputation_and_encoding(clean_data):
    record = clean_data.get("ticket_2.txt")
    assert record is not None, "ticket_2.txt record not found."
    assert record["date"] == "2023-10-02"
    assert record["email"] == "bob@test.org"
    assert record["error_code"] == "ERR_504", "Expected ERR_504 imputed from 'timeout'."
    assert "falló" in record["message"], "Special characters were not correctly decoded from ISO-8859-1."
    assert record["message"] == "Connection timeout while trying to reach the database. El servidor falló."

def test_ticket_3_imputation_and_encoding(clean_data):
    record = clean_data.get("ticket_3.txt")
    assert record is not None, "ticket_3.txt record not found."
    assert record["date"] == "2023-10-03"
    assert record["email"] == "charlie@domain.net"
    assert record["error_code"] == "ERR_403", "Expected ERR_403 imputed from 'denied'."
    assert "€" in record["message"], "Special character '€' was not correctly decoded from Windows-1252."
    assert record["message"] == "Access denied for user. La sesión expiró con el símbolo €."

def test_ticket_4_imputation(clean_data):
    record = clean_data.get("ticket_4.txt")
    assert record is not None, "ticket_4.txt record not found."
    assert record["date"] == "2023-10-04"
    assert record["email"] == "dave@example.com"
    assert record["error_code"] == "ERR_500", "Expected ERR_500 imputed from 'exception'."
    assert record["message"] == "The application threw an unhandled exception during startup."

def test_ticket_5_imputation(clean_data):
    record = clean_data.get("ticket_5.txt")
    assert record is not None, "ticket_5.txt record not found."
    assert record["date"] == "2023-10-05"
    assert record["email"] == "eve@hacker.net"
    assert record["error_code"] == "ERR_UNKNOWN", "Expected ERR_UNKNOWN for generic message."
    assert record["message"] == "Just a generic complaint about the UI. Nothing specific."
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
baseline_status=$?

if [ "$baseline_status" -eq 0 ]; then
cat << 'DYNAMIC_EOF' > /tmp/dynamic_verify.py
import json
import os
import secrets
import stat
import subprocess
import sys

RAW = "/home/user/tickets_raw"
OUT = "/home/user/tickets_clean.jsonl"
REQUIRED_KEYS = {"date", "email", "error_code", "message", "filename"}

originals = [
    ("ticket_1.txt", "utf-8", "Date: 2023-10-01\nEmail: alice@example.com\nError: [ERR_404]\nMessage: The requested file was not found.", "2023-10-01", "alice@example.com", "ERR_404", "The requested file was not found."),
    ("ticket_2.txt", "iso-8859-1", "Reported: 2023-10-02\nUser: bob@test.org\nError: []\nMessage: Connection timeout while trying to reach the database. El servidor falló.", "2023-10-02", "bob@test.org", "ERR_504", "Connection timeout while trying to reach the database. El servidor falló."),
    ("ticket_3.txt", "windows-1252", "Date: 2023-10-03\nEmail: charlie@domain.net\nError: []\nMessage: Access denied for user. La sesión expiró con el símbolo €.", "2023-10-03", "charlie@domain.net", "ERR_403", "Access denied for user. La sesión expiró con el símbolo €."),
    ("ticket_4.txt", "utf-8", "Date: 2023-10-04\nEmail: dave@example.com\nMessage: The application threw an unhandled exception during startup.", "2023-10-04", "dave@example.com", "ERR_500", "The application threw an unhandled exception during startup."),
    ("ticket_5.txt", "utf-8", "Reported: 2023-10-05\nUser: eve@hacker.net\nError: []\nMessage: Just a generic complaint about the UI. Nothing specific.", "2023-10-05", "eve@hacker.net", "ERR_UNKNOWN", "Just a generic complaint about the UI. Nothing specific."),
]

def command_for(path):
    suffix = os.path.splitext(path)[1].lower()
    commands = {
        ".py": [sys.executable, path],
        ".sh": ["bash", path],
        ".pl": ["perl", path],
        ".rb": ["ruby", path],
        ".js": ["node", path],
        ".php": ["php", path],
        ".jar": ["java", "-jar", path],
        ".go": ["go", "run", path],
    }
    if suffix in commands:
        return commands[suffix]
    try:
        if os.path.isfile(path) and os.access(path, os.X_OK):
            return [path]
    except OSError:
        pass
    return None

def discover_candidates():
    excluded = {
        os.path.realpath(OUT),
        os.path.realpath(__file__),
        os.path.realpath("/tmp/test_final_state.py"),
    }
    candidates = []
    seen = set()
    raw_mtime = max(os.stat(os.path.join(RAW, n)).st_mtime for n in os.listdir(RAW))

    for root in ("/home/user", "/root", "/tmp"):
        if not os.path.isdir(root):
            continue
        for current, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if not d.startswith(".") and d not in {"tickets_raw", "__pycache__", "node_modules"}]
            for name in files:
                path = os.path.realpath(os.path.join(current, name))
                if path in excluded or path in seen or path.startswith(RAW + os.sep):
                    continue
                try:
                    if root != "/home/user" and os.stat(path).st_mtime < raw_mtime - 1:
                        continue
                except OSError:
                    continue
                cmd = command_for(path)
                if cmd is not None:
                    seen.add(path)
                    priority = 0 if path.startswith("/home/user/") else 1
                    candidates.append((priority, -os.stat(path).st_mtime, path, cmd))

    for name in os.listdir("/"):
        path = os.path.realpath(os.path.join("/", name))
        if path in excluded or path in seen or not os.path.isfile(path):
            continue
        cmd = command_for(path)
        if cmd is not None:
            try:
                if os.stat(path).st_mtime >= raw_mtime - 1:
                    candidates.append((2, -os.stat(path).st_mtime, path, cmd))
            except OSError:
                pass
    candidates.sort()
    return [(path, cmd) for _, _, path, cmd in candidates]

def build_inputs():
    token = secrets.token_hex(8)
    day = 10 + secrets.randbelow(15)
    explicit_code = "ERR_" + secrets.token_hex(4).upper()
    challenges = [
        (f"probe_explicit_{token}.txt", "utf-8", f"Date:   2026-07-{day:02d}\nEmail: explicit-{token}@example.test\nError: [{explicit_code}]\nMessage: Curly quote ” and UTF-8 café.\nSecond message line {token}.", f"2026-07-{day:02d}", f"explicit-{token}@example.test", explicit_code, f"Curly quote ” and UTF-8 café.\nSecond message line {token}."),
        (f"probe_timeout_{token}.txt", "iso-8859-1", f"Reported:  2026-08-{day:02d}\nUser: timeout-{token}@example.test\nError: []\nMessage: A TIMEOUT ocurrió para el niño {token}. Café.", f"2026-08-{day:02d}", f"timeout-{token}@example.test", "ERR_504", f"A TIMEOUT ocurrió para el niño {token}. Café."),
        (f"probe_forbidden_{token}.txt", "windows-1252", f"Date: 2026-09-{day:02d}\nEmail: forbidden-{token}@example.test\nError: []\nMessage: The operation was FoRbIdDeN — cost €{day}. “Retry later.”", f"2026-09-{day:02d}", f"forbidden-{token}@example.test", "ERR_403", f"The operation was FoRbIdDeN — cost €{day}. “Retry later.”"),
        (f"probe_crash_{token}.txt", "utf-8", f"Reported: 2026-10-{day:02d}\nUser: crash-{token}@example.test\nMessage:\n  A CRASH occurred for request {token}.\nDetails remain on this line.", f"2026-10-{day:02d}", f"crash-{token}@example.test", "ERR_500", f"A CRASH occurred for request {token}.\nDetails remain on this line."),
        (f"probe_unknown_{token}.txt", "utf-8", f"Date: 2026-11-{day:02d}\nEmail: unknown-{token}@example.test\nError: []\nMessage: Ordinary status report {token}; no classified keyword applies.", f"2026-11-{day:02d}", f"unknown-{token}@example.test", "ERR_UNKNOWN", f"Ordinary status report {token}; no classified keyword applies."),
    ]
    return originals + challenges

def reset_inputs(items):
    os.makedirs(RAW, exist_ok=True)
    for name in os.listdir(RAW):
        path = os.path.join(RAW, name)
        if os.path.isfile(path) and name.endswith(".txt"):
            os.unlink(path)
    for filename, encoding, content, *_ in items:
        with open(os.path.join(RAW, filename), "wb") as f:
            f.write(content.encode(encoding))
    try:
        os.unlink(OUT)
    except FileNotFoundError:
        pass

def valid_output(items):
    expected = {
        row[0]: {
            "date": row[3], "email": row[4], "error_code": row[5],
            "message": row[6], "filename": row[0]
        }
        for row in items
    }
    try:
        raw = open(OUT, "rb").read()
        text = raw.decode("utf-8", errors="strict")
    except (OSError, UnicodeDecodeError):
        return False

    records = {}
    try:
        for line in text.splitlines():
            if not line.strip():
                continue
            record = json.loads(line)
            if not isinstance(record, dict) or set(record) != REQUIRED_KEYS:
                return False
            filename = record.get("filename")
            if filename in records:
                return False
            records[filename] = record
    except (json.JSONDecodeError, TypeError):
        return False

    return records == expected

def main():
    candidates = discover_candidates()
    if not candidates:
        print("No ETL script or executable artifact was found.", file=sys.stderr)
        return 1

    items = build_inputs()
    for path, cmd in candidates:
        reset_inputs(items)
        try:
            result = subprocess.run(cmd, cwd="/home/user", env={**os.environ, "HOME": "/home/user"}, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
        except (OSError, subprocess.TimeoutExpired):
            continue
        if result.returncode == 0 and valid_output(items):
            print(f"Validated ETL artifact: {path}")
            return 0

    print("No discovered artifact produced correct output for randomized inputs.", file=sys.stderr)
    return 1

if __name__ == "__main__":
    raise SystemExit(main())
DYNAMIC_EOF

python3 /tmp/dynamic_verify.py
verify_status=$?
else
verify_status=1
fi

if [ "$verify_status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
