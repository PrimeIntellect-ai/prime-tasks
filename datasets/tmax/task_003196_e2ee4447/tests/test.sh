#!/bin/bash
mkdir -p /logs/verifier
ok=1

SCRIPT=/home/user/serve_report.sh

# The requested artifact must exist and be valid Bash.
if [[ ! -f "$SCRIPT" || -L "$SCRIPT" ]] || ! /bin/bash -n "$SCRIPT"; then
    ok=0
fi

# Preserve the original endpoint assertions against the supplied data.
cat > /tmp/test_original_report.py <<'PY'
import requests
import pytest

def test_audit_report_endpoint():
    url = "http://127.0.0.1:8080/audit-report"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {url}. Is the Bash server running? Error: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    content_type = response.headers.get("Content-Type", "")
    assert "application/json" in content_type, f"Expected Content-Type to contain 'application/json', got '{content_type}'"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response body is not valid JSON. Body received:\n{response.text}")

    expected_data = [
        {"target_node": "EXT-99", "department": "Vendor-Cloud", "total_scp_bytes": 3000},
        {"target_node": "EXT-88", "department": "Offshore-Contractors", "total_scp_bytes": 1700},
    ]
    assert isinstance(data, list), f"Expected response JSON to be a list, got {type(data).__name__}"
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} items in the list, got {len(data)}"
    assert data == expected_data, f"JSON data does not match expected output.\nExpected: {expected_data}\nGot: {data}"
PY

if [[ "$ok" -eq 1 ]] && ! python3 -m pytest /tmp/test_original_report.py -x --tb=short; then
    ok=0
fi

stop_server() {
    pkill -TERM -f '/home/user/serve_report[.]sh' 2>/dev/null || true
    sleep 0.3
    python3 - <<'PY'
import glob, os, signal, time

def listeners():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if fields[3] == "0A" and int(fields[1].rsplit(":", 1)[1], 16) == 8080:
                inodes.add(fields[9])
    return inodes

for sig in (signal.SIGTERM, signal.SIGKILL):
    targets = listeners()
    if not targets:
        break
    for fd in glob.glob("/proc/[0-9]*/fd/*"):
        try:
            link = os.readlink(fd)
            if link.startswith("socket:[") and link[8:-1] in targets:
                pid = int(fd.split("/")[2])
                if pid != os.getpid():
                    os.kill(pid, sig)
        except (OSError, ValueError, ProcessLookupError, PermissionError):
            pass
    time.sleep(0.3)
PY
}

server_pid=""
cleanup() {
    if [[ -n "$server_pid" ]]; then
        kill "$server_pid" 2>/dev/null || true
    fi
    stop_server
}
trap cleanup EXIT

if [[ "$ok" -eq 1 ]]; then
    stop_server

    # Replace all inputs with an unpredictable second case, forcing the submitted
    # script to perform OCR, graph traversal, aggregation, metadata joining, and sorting.
    tag="${RANDOM}${RANDOM}"
    root="SRV-${tag}"
    y1="GATE-A-${tag}"
    y2="GATE-B-${tag}"
    y3="DECOY-${tag}"
    z1="DEST-A-${tag}"
    z2="DEST-B-${tag}"
    z3="DECOY-D-${tag}"
    n=$((RANDOM % 200 + 1))
    a=$((1100 + n))
    b=$((700 + n))
    c=$((3200 + n))

    convert -size 700x240 xc:white -font DejaVu-Sans -pointsize 22 -fill black \
      -annotate +25+45 "CONFIDENTIAL MEMO\n\nInvestigate this audit target.\nAUDIT_ROOT: ${root}\n\nManagement" \
      /app/incident_memo.png

    cat > /app/network_traffic.csv <<EOF
src_node,dst_node,protocol,bytes_transferred
${root},${y1},HTTPS,501
${root},${y2},HTTPS,502
${root},${y3},SSH,999
OTHER-${tag},${y3},HTTPS,888
${y1},${z1},SCP,${a}
${y2},${z1},SCP,${b}
${y1},${z2},SCP,${c}
${y2},${z3},HTTPS,9000
${y3},${z3},SCP,8000
${y1},${z2},TCP,7000
EOF

    cat > /app/node_metadata.json <<EOF
[
  {"node":"${z1}","department":"Research-${tag}","owner_id":"U1"},
  {"node":"${z2}","department":"External-${tag}","owner_id":"U2"},
  {"node":"${z3}","department":"Decoy-${tag}","owner_id":"U3"}
]
EOF

    runuser -u user -- /bin/bash "$SCRIPT" >/tmp/serve_report.log 2>&1 &
    server_pid=$!

    cat > /tmp/test_dynamic_report.py <<'PY'
import csv
import json
import re
import subprocess
import time
import requests


def derive_expected():
    text = subprocess.check_output(
        ["tesseract", "/app/incident_memo.png", "stdout"],
        text=True,
        stderr=subprocess.DEVNULL,
    )
    match = re.search(r"AUDIT_ROOT:\s*([A-Za-z0-9_-]+)", text)
    assert match, f"Verifier could not OCR AUDIT_ROOT from generated memo: {text!r}"
    root = match.group(1)

    with open("/app/network_traffic.csv", newline="") as f:
        rows = list(csv.DictReader(f))
    intermediates = {
        row["dst_node"] for row in rows
        if row["src_node"] == root and row["protocol"] == "HTTPS"
    }
    totals = {}
    for row in rows:
        if row["src_node"] in intermediates and row["protocol"] == "SCP":
            totals[row["dst_node"]] = totals.get(row["dst_node"], 0) + int(row["bytes_transferred"])

    with open("/app/node_metadata.json") as f:
        departments = {item["node"]: item["department"] for item in json.load(f)}

    result = [
        {"target_node": node, "department": departments[node], "total_scp_bytes": total}
        for node, total in totals.items()
    ]
    return sorted(result, key=lambda item: item["total_scp_bytes"], reverse=True)


def test_dynamic_audit_report():
    expected_data = derive_expected()
    url = "http://127.0.0.1:8080/audit-report"
    last_error = None
    response = None
    for _ in range(30):
        try:
            response = requests.get(url, timeout=2)
            break
        except requests.exceptions.RequestException as exc:
            last_error = exc
            time.sleep(0.25)
    assert response is not None, f"Submitted script did not start its server: {last_error}"
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    content_type = response.headers.get("Content-Type", "")
    assert "application/json" in content_type, f"Expected Content-Type to contain 'application/json', got '{content_type}'"
    try:
        data = response.json()
    except ValueError:
        raise AssertionError(f"Response body is not valid JSON. Body received:\n{response.text}")
    assert isinstance(data, list), f"Expected response JSON to be a list, got {type(data).__name__}"
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} items in the list, got {len(data)}"
    assert data == expected_data, f"JSON data does not match dynamically derived output.\nExpected: {expected_data}\nGot: {data}"
PY

    if ! python3 -m pytest /tmp/test_dynamic_report.py -x --tb=short; then
        ok=0
    fi
fi

if [[ "$ok" -eq 1 ]]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
