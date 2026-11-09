#!/bin/bash
set -u
mkdir -p /logs/verifier

ACTIVE_PID=""
cleanup() {
    if [ -n "$ACTIVE_PID" ] && kill -0 "$ACTIVE_PID" 2>/dev/null; then
        kill "$ACTIVE_PID" 2>/dev/null || true
        wait "$ACTIVE_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

cat << 'PY_EOF' > /tmp/watcher_ready.py
import glob
import os
import re
import sys

pid = sys.argv[1]
for path in glob.glob(f"/proc/{pid}/fdinfo/*"):
    try:
        text = open(path, "r").read()
    except OSError:
        continue
    for line in text.splitlines():
        if line.startswith("inotify "):
            match = re.search(r"mask:([0-9a-fA-F]+)", line)
            if match and (int(match.group(1), 16) & 0x8):  # IN_CLOSE_WRITE
                sys.exit(0)
sys.exit(1)
PY_EOF

wait_for_watcher() {
    local pid="$1"
    local i
    for i in $(seq 1 100); do
        kill -0 "$pid" 2>/dev/null || return 1
        python3 /tmp/watcher_ready.py "$pid" >/dev/null 2>&1 && return 0
        sleep 0.05
    done
    return 1
}

wait_for_clean_exit() {
    local pid="$1"
    local i state rc
    for i in $(seq 1 300); do
        if [ ! -e "/proc/$pid/stat" ]; then
            wait "$pid"
            return $?
        fi
        state=$(awk '{print $3}' "/proc/$pid/stat" 2>/dev/null || echo X)
        if [ "$state" = "Z" ]; then
            wait "$pid"
            return $?
        fi
        sleep 0.05
    done
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    return 1
}

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re

def test_monitor_files_exist():
    assert os.path.isfile("/home/user/monitor.c"), "/home/user/monitor.c is missing"
    assert os.path.isfile("/home/user/monitor"), "/home/user/monitor executable is missing"
    assert os.access("/home/user/monitor", os.X_OK), "/home/user/monitor is not executable"
    with open("/home/user/monitor", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/monitor is not a compiled executable"


def test_source_uses_required_inotify_event():
    source = open("/home/user/monitor.c", "r", errors="replace").read()
    assert re.search(r"\binotify_init(?:1)?\s*\(", source), "monitor.c does not initialize inotify"
    assert re.search(r"\binotify_add_watch\s*\(", source), "monitor.c does not add an inotify watch"
    assert "IN_CLOSE_WRITE" in source, "monitor.c does not request IN_CLOSE_WRITE events"


def test_bad_logs_csv_contents():
    csv_path = "/home/user/bad_logs.csv"
    assert os.path.isfile(csv_path), f"{csv_path} was not created"

    with open(csv_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "3,ERROR",
        "6,ERROR",
        "9,ERROR"
    ]

    assert lines == expected_lines, f"Contents of {csv_path} do not match the expected output. Got: {lines}"
TEST_EOF

verify() {
    rm -f /home/user/incoming/* /home/user/bad_logs.csv

    /home/user/monitor >/tmp/monitor_official.out 2>/tmp/monitor_official.err &
    ACTIVE_PID=$!
    wait_for_watcher "$ACTIVE_PID" || return 1
    /home/user/generate_logs.sh >/tmp/generator.out 2>/tmp/generator.err || return 1
    wait_for_clean_exit "$ACTIVE_PID" || return 1
    ACTIVE_PID=""

    # Retain the original file, executable, and exact-output assertions.
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || return 1

    # Rebuild the submitted source and exercise it with unpredictable IDs,
    # statuses, and a corruption set that is not correlated with JSON values.
    gcc /home/user/monitor.c -o /tmp/monitor_rebuilt || return 1
    rm -f /home/user/incoming/* /home/user/bad_logs.csv /tmp/dynamic_expected.txt

    /tmp/monitor_rebuilt >/tmp/monitor_dynamic.out 2>/tmp/monitor_dynamic.err &
    ACTIVE_PID=$!
    wait_for_watcher "$ACTIVE_PID" || return 1

    python3 << 'DYNAMIC_EOF'
import io
import json
import secrets
import time
import zipfile
from pathlib import Path

incoming = Path("/home/user/incoming")
rng = secrets.SystemRandom()
corrupt = set(rng.sample(range(1, 10), 3))
corrupt.add(10)
ids = rng.sample(range(10000, 99999), 10)
expected = []

for i in range(1, 11):
    status = "STATE_" + secrets.token_hex(5)
    record = {"id": ids[i - 1], "status": status, "data": "payload " + secrets.token_hex(8)}
    json_path = incoming / f"log_{i}.json"
    json_text = json.dumps(record, separators=(", ", ": "))
    json_path.write_text(json_text + "\n")

    archive = io.BytesIO()
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr(f"log_{i}.json", json_text + "\n")
    data = archive.getvalue()
    if i in corrupt:
        data = b"BROKENZIP!!!" + data[12:]
        expected.append(f"{record['id']},{record['status']}")

    with open(incoming / f"log_{i}.zip", "wb") as f:
        f.write(data)
    time.sleep(0.08)

Path("/tmp/dynamic_expected.txt").write_text("\n".join(expected) + "\n")
DYNAMIC_EOF

    wait_for_clean_exit "$ACTIVE_PID" || return 1
    ACTIVE_PID=""

    python3 << 'CHECK_EOF'
from pathlib import Path

expected = [x.strip() for x in Path("/tmp/dynamic_expected.txt").read_text().splitlines() if x.strip()]
path = Path("/home/user/bad_logs.csv")
assert path.is_file(), "/home/user/bad_logs.csv was not created in the dynamic run"
actual = [x.strip() for x in path.read_text().splitlines() if x.strip()]
assert actual == expected, f"dynamic archive test failed: expected {expected}, got {actual}"
CHECK_EOF
}

if verify; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
