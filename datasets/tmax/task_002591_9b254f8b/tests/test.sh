#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import glob
import os
import re
import secrets
import struct
import subprocess
import tempfile
import time

HOME = "/home/user"
SOURCE = f"{HOME}/extractor.c"
EXTRACTOR = f"{HOME}/extractor"
ORGANIZER = f"{HOME}/organize.sh"
INVENTORY = f"{HOME}/inventory.log"
SORTED = f"{HOME}/inventory_sorted.log"


def expected_asset_lines():
    entries = []
    for asset in glob.glob(f"{HOME}/assets/*.bin"):
        with open(asset, "rb") as f:
            data = f.read(16)
        if len(data) == 16:
            magic, project_id, timestamp = struct.unpack("<IIQ", data)
            if magic == 0xDEADBEEF:
                entries.append((project_id, timestamp))
    entries.sort(key=lambda item: item[0])
    return [f"ProjectID: {p}, Timestamp: {t}\n" for p, t in entries]


def test_extractor_c_exists():
    assert os.path.isfile(SOURCE), "/home/user/extractor.c does not exist."


def test_extractor_executable_exists():
    assert os.path.isfile(EXTRACTOR), f"{EXTRACTOR} does not exist."
    assert os.access(EXTRACTOR, os.X_OK), f"{EXTRACTOR} is not executable."


def test_organize_sh_exists():
    assert os.path.isfile(ORGANIZER), "/home/user/organize.sh does not exist."


def test_inventory_sorted_log_contents():
    assert os.path.isfile(SORTED), f"{SORTED} does not exist. Ensure your script creates it."
    expected_lines = expected_asset_lines()
    with open(SORTED, "r") as f:
        actual_lines = f.readlines()
    assert len(actual_lines) == len(expected_lines), \
        f"Expected {len(expected_lines)} entries, but found {len(actual_lines)} in {SORTED}."
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, \
            f"Mismatch at line {i + 1} in {SORTED}.\nExpected: {expected.strip()}\nActual: {actual.strip()}"


def exercise_extractor(path):
    try:
        os.unlink(INVENTORY)
    except FileNotFoundError:
        pass

    expected = []
    cases = []
    for _ in range(60):
        project_id = secrets.randbelow(2**32)
        timestamp = secrets.randbelow(2**64)
        expected.append(f"ProjectID: {project_id}, Timestamp: {timestamp}\n")
        cases.append((struct.pack("<IIQ", 0xDEADBEEF, project_id, timestamp) + secrets.token_bytes(11), True))
    for _ in range(20):
        project_id = secrets.randbelow(2**32)
        timestamp = secrets.randbelow(2**64)
        cases.append((struct.pack("<IIQ", 0xBAADF00D, project_id, timestamp), False))

    processes = [(subprocess.Popen([path], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE), data, valid)
                 for data, valid in cases]
    for proc, data, valid in processes:
        stdout, stderr = proc.communicate(data, timeout=15)
        assert proc.returncode == 0, f"Extractor exited with {proc.returncode}. stderr: {stderr!r}"
        if not valid:
            assert stdout == b"", "Invalid magic must be ignored silently."

    with open(INVENTORY, "r") as f:
        actual = f.readlines()
    assert collections.Counter(actual) == collections.Counter(expected), \
        "Extractor did not append exactly the expected records under concurrent execution."


def test_source_and_executable_behavior_and_locking():
    with open(SOURCE, "r", errors="replace") as f:
        source_text = f.read()
    uses_flock = re.search(r"\bflock\b", source_text) and "LOCK_EX" in source_text
    uses_fcntl = (re.search(r"\bfcntl\b", source_text) and "F_WRLCK" in source_text and
                  ("F_SETLK" in source_text or "F_SETLKW" in source_text))
    assert uses_flock or uses_fcntl, "extractor.c must acquire an exclusive flock or fcntl lock."

    assert open(EXTRACTOR, "rb").read(4) == b"\x7fELF", "extractor must be a compiled executable."
    exercise_extractor(EXTRACTOR)

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "extractor-rebuilt")
        result = subprocess.run(["gcc", SOURCE, "-o", rebuilt], stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True)
        assert result.returncode == 0, f"extractor.c does not compile:\n{result.stderr}"
        exercise_extractor(rebuilt)


def test_organizer_executes_extractor_concurrently_and_waits():
    expected_lines = expected_asset_lines()
    td = tempfile.mkdtemp(prefix="organizer-probe-")
    os.chmod(td, 0o777)
    saved = os.path.join(td, "real-extractor")
    state = os.path.join(td, "state")
    os.replace(EXTRACTOR, saved)
    os.chmod(saved, 0o755)
    with open(state, "w") as f:
        f.write("0 0")
    os.chmod(state, 0o666)

    wrapper = f'''#!/usr/bin/python3
import fcntl
import os
import subprocess
import sys
import time
STATE = {state!r}
REAL = {saved!r}
data = sys.stdin.buffer.read()
with open(STATE, "r+") as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    current, maximum = map(int, f.read().split())
    current += 1
    maximum = max(maximum, current)
    f.seek(0); f.truncate(); f.write(f"{{current}} {{maximum}}"); f.flush()
    fcntl.flock(f, fcntl.LOCK_UN)
time.sleep(0.12)
result = subprocess.run([REAL], input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
with open(STATE, "r+") as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    current, maximum = map(int, f.read().split())
    current -= 1
    f.seek(0); f.truncate(); f.write(f"{{current}} {{maximum}}"); f.flush()
    fcntl.flock(f, fcntl.LOCK_UN)
sys.stdout.buffer.write(result.stdout)
sys.stderr.buffer.write(result.stderr)
sys.exit(result.returncode)
'''
    try:
        with open(EXTRACTOR, "w") as f:
            f.write(wrapper)
        os.chmod(EXTRACTOR, 0o755)
        for path in (INVENTORY, SORTED):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass

        result = subprocess.run(["runuser", "-u", "user", "--", "bash", ORGANIZER],
                                cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, timeout=60)
        assert result.returncode == 0, f"organize.sh failed:\n{result.stderr}"
        with open(state, "r") as f:
            current, maximum = map(int, f.read().split())
        assert current == 0, "organize.sh returned before all extractor jobs completed."
        assert maximum >= 4, f"Expected at least 4 concurrent extractor jobs, observed {maximum}."
        assert os.path.isfile(SORTED), "organize.sh did not create inventory_sorted.log."
        with open(SORTED, "r") as f:
            actual_lines = f.readlines()
        assert actual_lines == expected_lines, "organize.sh did not produce the correctly sorted inventory."
    finally:
        try:
            os.unlink(EXTRACTOR)
        except FileNotFoundError:
            pass
        if os.path.exists(saved):
            os.replace(saved, EXTRACTOR)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
