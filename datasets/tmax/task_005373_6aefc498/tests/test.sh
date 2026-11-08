#!/bin/bash
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import json
import os
import secrets
import string

import pytest
import requests

URL = "http://127.0.0.1:9090/process"
TOKEN = "pineapple"


def post_csv(csv_bytes, timeout=10):
    headers = {"Authorization": f"Bearer {TOKEN}"}
    files = {"dataset": (f"{secrets.token_hex(6)}.csv", csv_bytes, "text/csv")}
    try:
        return requests.post(URL, headers=headers, files=files, timeout=timeout)
    except requests.exceptions.ConnectionError:
        pytest.fail("Could not connect to the server at 127.0.0.1:9090.")


def encode_rows(rows):
    text = io.StringIO(newline="")
    writer = csv.writer(text, lineterminator="\n")
    writer.writerow(["EmployeeID", "FullName", "Jan_Sales", "Feb_Sales", "Mar_Sales"])
    writer.writerows(rows)
    return text.getvalue().encode("iso-8859-1")


def expected_for(rows):
    result = []
    seen = set()
    for employee_id, full_name, jan, feb, mar in rows:
        for month, sales in (("Jan", jan), ("Feb", feb), ("Mar", mar)):
            if sales == "":
                continue
            key = (employee_id, month)
            if key in seen:
                continue
            seen.add(key)
            result.append({
                "employee_id": employee_id,
                "full_name": full_name.upper(),
                "month": month,
                "sales": sales,
            })
    return result


def assert_processed(rows, timeout=10):
    response = post_csv(encode_rows(rows), timeout=timeout)
    assert response.status_code == 200, (
        f"Expected 200 OK, got {response.status_code}. Response: {response.text[:500]}"
    )
    try:
        data = response.json()
    except (json.JSONDecodeError, requests.exceptions.JSONDecodeError):
        pytest.fail(f"Response is not valid JSON: {response.text[:500]}")
    expected = expected_for(rows)
    assert data == expected, f"Expected {expected!r}, got {data!r}"


def test_source_file_exists():
    assert os.path.isfile("/home/user/etl_server.go"), "Go source file /home/user/etl_server.go is missing."


def test_auth_failure():
    """Test that missing or incorrect token returns 401 Unauthorized."""
    try:
        response = requests.post(URL, timeout=2)
    except requests.exceptions.ConnectionError:
        pytest.fail("Could not connect to the server at 127.0.0.1:9090. Is it running?")

    assert response.status_code == 401, f"Expected 401 for missing auth, got {response.status_code}"

    headers = {"Authorization": "Bearer wrongtoken"}
    response = requests.post(URL, headers=headers, timeout=2)
    assert response.status_code == 401, f"Expected 401 for incorrect auth, got {response.status_code}"


def test_etl_processing():
    """Retain the original ETL test and its exact expected output."""
    headers = {"Authorization": f"Bearer {TOKEN}"}
    csv_content = (
        "EmployeeID,FullName,Jan_Sales,Feb_Sales,Mar_Sales\n"
        "101,Renée,,2000,\n"
        "102,José,1500,1600,1700\n"
        "101,Renée,1000,2000,3000\n"
    )
    files = {"dataset": ("data.csv", csv_content.encode("iso-8859-1"), "text/csv")}

    try:
        response = requests.post(URL, headers=headers, files=files, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Could not connect to the server at 127.0.0.1:9090.")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except (json.JSONDecodeError, requests.exceptions.JSONDecodeError):
        pytest.fail(f"Response is not valid JSON: {response.text}")

    expected_data = [
        {"employee_id": "101", "full_name": "RENÉE", "month": "Feb", "sales": "2000"},
        {"employee_id": "102", "full_name": "JOSÉ", "month": "Jan", "sales": "1500"},
        {"employee_id": "102", "full_name": "JOSÉ", "month": "Feb", "sales": "1600"},
        {"employee_id": "102", "full_name": "JOSÉ", "month": "Mar", "sales": "1700"},
        {"employee_id": "101", "full_name": "RENÉE", "month": "Jan", "sales": "1000"},
        {"employee_id": "101", "full_name": "RENÉE", "month": "Mar", "sales": "3000"},
    ]

    assert len(data) == len(expected_data), f"Expected {len(expected_data)} records, got {len(data)}"
    for i, expected_row in enumerate(expected_data):
        assert data[i] == expected_row, f"Mismatch at index {i}. Expected {expected_row}, got {data[i]}"


def test_randomized_generic_etl():
    """Exercise values unknown until verification, including quoting, Latin-1, gaps, and duplicates."""
    names = ["Ana, Muñoz", "Zoë Müller", "André Noël", "Léa D'Arcy"]
    for _ in range(2):
        ids = [str(100000 + secrets.randbelow(800000)) for _ in range(3)]
        while len(set(ids)) != 3:
            ids = [str(100000 + secrets.randbelow(800000)) for _ in range(3)]
        suffix = "".join(secrets.choice(string.ascii_lowercase) for _ in range(7))
        values = [str(1000 + secrets.randbelow(900000)) for _ in range(12)]
        rows = [
            [ids[0], names[0] + " " + suffix, values[0], "", values[1]],
            [ids[1], names[1], values[2], values[3], values[4]],
            [ids[0], "WRONG LATER NAME", values[5], values[6], values[7]],
            [ids[2], names[2], "", "", ""],
            [ids[2], names[3], values[8], values[9], values[10]],
            [ids[1], "ANOTHER LATER NAME", values[11], values[11], values[11]],
        ]
        assert_processed(rows)


def test_large_duplicate_heavy_stream():
    """Send a large upload whose tiny output requires processing the complete stream."""
    employee_id = str(100000 + secrets.randbelow(800000))
    first = [employee_id, "François, Peña", secrets.token_hex(5), secrets.token_hex(5), secrets.token_hex(5)]
    duplicate = [employee_id, "LATER NAME", secrets.token_hex(5), secrets.token_hex(5), secrets.token_hex(5)]
    missing = [employee_id, "IGNORED", "", "", ""]

    raw = io.BytesIO()
    text = io.TextIOWrapper(raw, encoding="iso-8859-1", newline="", write_through=True)
    writer = csv.writer(text, lineterminator="\n")
    writer.writerow(["EmployeeID", "FullName", "Jan_Sales", "Feb_Sales", "Mar_Sales"])
    writer.writerow(first)
    for i in range(140000):
        writer.writerow(duplicate if i % 2 == 0 else missing)
    text.flush()
    payload = raw.getvalue()
    assert len(payload) > 4_000_000

    response = post_csv(payload, timeout=25)
    assert response.status_code == 200, f"Expected 200 for large upload, got {response.status_code}: {response.text[:500]}"
    assert response.json() == expected_for([first]), "Large streamed upload was not deduplicated correctly"
TEST_EOF

# Build the submitted artifact itself, rather than trusting an unrelated process
# that may already be listening on the requested port.
if ! timeout 45s go build -o /tmp/etl_submission /home/user/etl_server.go >/tmp/etl_build.log 2>&1; then
    cat /tmp/etl_build.log
    exit 0
fi

# Stop any pre-existing listener on 127.0.0.1:9090.
python3 << 'KILL_EOF'
import os
import signal
import time

inodes = set()
for path in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(path) as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) > 9 and fields[1].split(":")[-1].upper() == "2382" and fields[3] == "0A":
                    inodes.add(fields[9])
    except OSError:
        pass

pids = set()
for entry in os.listdir("/proc"):
    if not entry.isdigit() or int(entry) == 1:
        continue
    fd_dir = f"/proc/{entry}/fd"
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                pids.add(int(entry))
                break
    except OSError:
        pass

for pid in pids:
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        pass
time.sleep(0.4)
for pid in pids:
    try:
        os.kill(pid, signal.SIGKILL)
    except OSError:
        pass
KILL_EOF

/tmp/etl_submission >/tmp/etl_server.log 2>&1 &
SERVER_PID=$!

python3 << 'WAIT_EOF'
import socket
import time
for _ in range(40):
    try:
        with socket.create_connection(("127.0.0.1", 9090), timeout=0.2):
            break
    except OSError:
        time.sleep(0.1)
WAIT_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

kill "$SERVER_PID" 2>/dev/null || true
wait "$SERVER_PID" 2>/dev/null || true
