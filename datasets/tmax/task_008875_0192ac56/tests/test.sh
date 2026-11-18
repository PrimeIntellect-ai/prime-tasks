#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path

SCRIPT_PATH = "/home/user/consolidate.py"
ORIGINAL_OUTPUT = "/home/user/critical_errors.txt"


def test_consolidate_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."


def test_output_file_exists():
    assert os.path.isfile(ORIGINAL_OUTPUT), f"The output file {ORIGINAL_OUTPUT} does not exist. Did the script run successfully?"


def test_output_file_content():
    if not os.path.isfile(ORIGINAL_OUTPUT):
        return

    with open(ORIGINAL_OUTPUT, "r") as f:
        actual_content = f.read()

    expected_content = """[2023-10-01 10:10:00] FATAL CRITICAL_FAILURE: DB connection lost
    at db.connect()
    at main()
---END_RECORD---
[2023-10-04 13:00:00] FATAL CRITICAL_FAILURE: Network timeout
    Retries: 5
    Status: Failed
---END_RECORD---
[2023-10-02 11:05:00] FATAL CRITICAL_FAILURE: Out of memory
    Heap dump:
    0x0001
    0x0002
---END_RECORD---
"""

    actual_content = actual_content.replace("\r\n", "\n")
    expected_content = expected_content.replace("\r\n", "\n")
    assert actual_content == expected_content, f"The content of {ORIGINAL_OUTPUT} does not match the expected output. Found:\n{actual_content}"


def test_script_uses_atomic_write():
    if not os.path.isfile(SCRIPT_PATH):
        return

    with open(SCRIPT_PATH, "r") as f:
        script_content = f.read()

    has_rename = re.search(r'(os\.rename|shutil\.move|Path\.rename)', script_content)
    has_tmp = ".tmp" in script_content
    assert has_rename and has_tmp, "The script does not appear to use an atomic write approach (writing to a .tmp file and renaming)."


def install_atomic_monitor(base):
    hooks = Path(base) / "hooks"
    hooks.mkdir()
    monitor = hooks / "sitecustomize.py"
    monitor.write_text(r'''
import hashlib
import io
import json
import os

_log_path = os.environ.get("ATOMIC_MONITOR_LOG")
_real_rename = os.rename
_real_replace = os.replace
_open = io.open


def _snapshot(path):
    try:
        with _open(path, "rb") as f:
            return hashlib.sha256(f.read()).hexdigest()
    except Exception:
        return None


def _record(kind, src, dst, digest):
    if not _log_path:
        return
    event = {
        "kind": kind,
        "src": os.path.abspath(os.fspath(src)),
        "dst": os.path.abspath(os.fspath(dst)),
        "sha256": digest,
    }
    with _open(_log_path, "a", encoding="utf-8") as f:
        f.write(json.dumps(event) + "\n")


def _rename(src, dst, *args, **kwargs):
    digest = _snapshot(src)
    result = _real_rename(src, dst, *args, **kwargs)
    _record("rename", src, dst, digest)
    return result


def _replace(src, dst, *args, **kwargs):
    digest = _snapshot(src)
    result = _real_replace(src, dst, *args, **kwargs)
    _record("replace", src, dst, digest)
    return result


os.rename = _rename
os.replace = _replace
''', encoding="utf-8")
    return hooks


def run_and_verify(input_dir, output_path, expected, base):
    hooks = install_atomic_monitor(base)
    event_log = Path(base) / "atomic-events.jsonl"
    env = os.environ.copy()
    env["PYTHONPATH"] = str(hooks) + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    env["ATOMIC_MONITOR_LOG"] = str(event_log)

    result = subprocess.run(
        [sys.executable, SCRIPT_PATH, str(input_dir), str(output_path)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        timeout=15,
    )
    assert result.returncode == 0, f"Script failed on fresh input. stdout={result.stdout!r} stderr={result.stderr!r}"
    assert output_path.is_file(), "Script did not create the requested output file on fresh input."

    actual = output_path.read_text(encoding="utf-8").replace("\r\n", "\n")
    assert actual == expected, f"Incorrect output for fresh input. Expected {expected!r}, got {actual!r}"
    assert not Path(str(output_path) + ".tmp").exists(), "Temporary output remained after a successful run."

    events = []
    if event_log.exists():
        events = [json.loads(line) for line in event_log.read_text().splitlines() if line.strip()]
    expected_hash = hashlib.sha256(expected.encode("utf-8")).hexdigest()
    wanted_src = os.path.abspath(str(output_path) + ".tmp")
    wanted_dst = os.path.abspath(str(output_path))
    assert any(
        event.get("src") == wanted_src
        and event.get("dst") == wanted_dst
        and event.get("sha256") == expected_hash
        for event in events
    ), "The completed output was not written to output_path + '.tmp' and then atomically renamed to the final path."


def test_script_on_fresh_varied_logs_and_runtime_atomic_write():
    with tempfile.TemporaryDirectory(prefix="consolidate-test-") as td:
        base = Path(td)
        logs = base / "fresh-logs"
        (logs / "zeta").mkdir(parents=True)
        (logs / "alpha" / "deep").mkdir(parents=True)
        token = uuid.uuid4().hex

        first = f"[2041-07-09 01:02:03] ERROR first CRITICAL_FAILURE {token}\n  first continuation\n"
        second = f"[2041-07-09 01:02:04] INFO ordinary\n[2041-07-09 01:02:05] ERROR second\ncontinuation contains CRITICAL_FAILURE and {token}\n"
        third = f"[2041-07-10 11:12:13] CRITICAL_FAILURE third {token}\ntrace line 1\ntrace line 2\n"

        (logs / "alpha" / "deep" / "a.log").write_text(first + second, encoding="utf-8")
        (logs / "zeta" / "b.log").write_text(third, encoding="utf-8")
        (logs / "alpha" / "ignored.txt").write_text(f"[2041-01-01 00:00:00] CRITICAL_FAILURE {token}\n", encoding="utf-8")
        (logs / "alpha" / "upper.LOG").write_text(f"[2041-01-01 00:00:00] CRITICAL_FAILURE {token}\n", encoding="utf-8")

        records = [first.rstrip("\n"), second.split("[2041-07-09 01:02:04] INFO ordinary\n", 1)[1].rstrip("\n"), third.rstrip("\n")]
        expected = "".join(record + "\n---END_RECORD---\n" for record in records)
        run_and_verify(logs, base / "fresh-result.txt", expected, base)


def test_script_handles_no_matching_records_on_another_fresh_input():
    with tempfile.TemporaryDirectory(prefix="consolidate-empty-") as td:
        base = Path(td)
        logs = base / "logs"
        (logs / "nested").mkdir(parents=True)
        (logs / "nested" / "clean.log").write_text(
            "[2050-01-01 00:00:00] INFO clean\ncontinued clean text\n",
            encoding="utf-8",
        )
        run_and_verify(logs, base / "empty-result.txt", "", base)


def test_script_requires_exactly_two_arguments():
    with tempfile.TemporaryDirectory(prefix="consolidate-args-") as td:
        base = Path(td)
        logs = base / "logs"
        logs.mkdir()
        output = base / "out.txt"
        bad_commands = [
            [sys.executable, SCRIPT_PATH],
            [sys.executable, SCRIPT_PATH, str(logs)],
            [sys.executable, SCRIPT_PATH, str(logs), str(output), "extra"],
        ]
        for command in bad_commands:
            result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
            assert result.returncode != 0, f"Script accepted an invalid argument count: {command[2:]}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
