#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import subprocess
import tempfile
import time

import pytest

OPERATOR = "/home/user/operator.py"
SUPERVISOR = "/home/user/supervisor.sh"
LOG = "/home/user/operator.log"
MANIFEST = "/home/user/manifest.json"
STORAGE = "/home/user/storage_dir"

LINE_RE = re.compile(
    r"^GW: (?P<ip>[0-9.]+) \| PING: (?P<ping>SUCCESS|FAILURE) "
    r"\| STORAGE: (?P<storage>\d+) KB \| STATUS: (?P<status>HEALTHY|UNHEALTHY)$"
)


def default_gateway():
    output = subprocess.run(
        ["ip", "route"], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, check=True, timeout=10
    ).stdout
    for line in output.splitlines():
        fields = line.split()
        if fields and fields[0] == "default":
            if "via" in fields and fields.index("via") + 1 < len(fields):
                return fields[fields.index("via") + 1]
    return "127.0.0.1"


def actual_ping_result(gateway):
    result = subprocess.run(
        ["ping", "-c", "1", gateway], stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, timeout=10
    )
    return "SUCCESS" if result.returncode == 0 else "FAILURE"


def disk_usage_kb():
    output = subprocess.run(
        ["du", "-sk", STORAGE], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, check=True, timeout=10
    ).stdout
    return int(output.split()[0])


def read_single_log_line():
    assert os.path.isfile(LOG), f"{LOG} was not created"
    with open(LOG, "r") as f:
        lines = f.read().splitlines()
    assert len(lines) == 1, f"operator.py must append exactly one line per execution; found {len(lines)}"
    match = LINE_RE.fullmatch(lines[0])
    assert match, f"Operator output has the wrong format: {lines[0]!r}"
    return match


def test_operator_py_exists():
    assert os.path.exists(OPERATOR), f"{OPERATOR} does not exist."
    assert os.path.isfile(OPERATOR), f"{OPERATOR} is not a file."


def test_supervisor_sh_exists():
    assert os.path.exists(SUPERVISOR), f"{SUPERVISOR} does not exist."
    assert os.path.isfile(SUPERVISOR), f"{SUPERVISOR} is not a file."


def test_operator_log_format():
    assert os.path.exists(LOG), f"{LOG} does not exist. Did you run supervisor.sh?"
    with open(LOG, "r") as f:
        lines = f.read().strip().split('\n')
    assert len(lines) == 3, f"Expected exactly 3 lines in {LOG}, found {len(lines)}."
    for i, line in enumerate(lines):
        match = LINE_RE.fullmatch(line)
        assert match, f"Line {i+1} in {LOG} does not match the expected format: {line!r}"
        ping = match.group("ping")
        storage = int(match.group("storage"))
        status = match.group("status")
        expected_status = "HEALTHY" if ping == "SUCCESS" and storage <= 10240 else "UNHEALTHY"
        assert status == expected_status, (
            f"Line {i+1} has incorrect STATUS {status!r}. Expected {expected_status!r} "
            f"based on PING {ping!r} and STORAGE {storage!r}."
        )


def test_supervisor_sh_contents():
    with open(SUPERVISOR, "r") as f:
        content = f.read()
    assert "sleep 1" in content or "sleep 1s" in content, \
        "supervisor.sh does not seem to contain a 1-second sleep."
    assert "operator.py" in content, "supervisor.sh does not seem to execute operator.py."
    subprocess.run(["bash", "-n", SUPERVISOR], check=True, timeout=10)


def test_operator_performs_real_diagnostics():
    assert os.path.isdir(STORAGE), f"{STORAGE} is not a directory"
    manifest_backup = open(MANIFEST, "rb").read()
    storage_backup = tempfile.mktemp(prefix="storage_dir.verifier-backup-", dir="/home/user")
    os.rename(STORAGE, storage_backup)
    os.mkdir(STORAGE)
    try:
        # Eight KiB gives the same answer under byte-size rounding and du -k on
        # the filesystem used by the task, while differing from the setup data.
        with open(os.path.join(STORAGE, "probe.bin"), "wb") as f:
            f.write(b"V" * 8192)
        usage = disk_usage_kb()
        with open(MANIFEST, "w") as f:
            json.dump({"max_storage_kb": usage - 1}, f)

        gateway = default_gateway()
        ping_result = actual_ping_result(gateway)
        open(LOG, "w").close()
        subprocess.run(["python3", OPERATOR], check=True, timeout=20)
        match = read_single_log_line()

        assert match.group("ip") == gateway, \
            f"Reported gateway {match.group('ip')!r}, but ip route gives {gateway!r}"
        assert match.group("ping") == ping_result, \
            f"Reported ping result {match.group('ping')!r}, expected {ping_result!r}"
        assert int(match.group("storage")) == usage, \
            f"Reported storage {match.group('storage')} KB, expected {usage} KB"
        assert match.group("status") == "UNHEALTHY", \
            "Storage above max_storage_kb must produce UNHEALTHY"
    finally:
        with open(MANIFEST, "wb") as f:
            f.write(manifest_backup)
        shutil.rmtree(STORAGE, ignore_errors=True)
        os.rename(storage_backup, STORAGE)


def test_supervisor_executes_operator_three_times_with_delays():
    original = open(OPERATOR, "rb").read()
    original_mode = os.stat(OPERATOR).st_mode
    probe = "/tmp/supervisor_execution_probe"
    try:
        if os.path.exists(probe):
            os.remove(probe)
        with open(OPERATOR, "w") as f:
            f.write(
                "import time\n"
                f"with open({probe!r}, 'a') as out:\n"
                "    out.write(str(time.monotonic()) + '\\n')\n"
            )
        os.chmod(OPERATOR, original_mode)
        subprocess.run(["bash", SUPERVISOR], check=True, timeout=10)
        assert os.path.isfile(probe), "supervisor.sh did not execute /home/user/operator.py"
        with open(probe, "r") as f:
            stamps = [float(x) for x in f.read().splitlines()]
        assert len(stamps) == 3, \
            f"supervisor.sh must execute operator.py exactly 3 times; observed {len(stamps)}"
        gaps = [stamps[i + 1] - stamps[i] for i in range(2)]
        for gap in gaps:
            assert 0.85 <= gap <= 1.75, \
                f"Expected a 1-second pause between executions; observed {gap:.3f} seconds"
    finally:
        with open(OPERATOR, "wb") as f:
            f.write(original)
        os.chmod(OPERATOR, original_mode)
        if os.path.exists(probe):
            os.remove(probe)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
