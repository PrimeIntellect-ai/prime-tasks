#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import signal
import subprocess
import textwrap

import pytest

OPERATOR = "/home/user/operator.py"
LOG = "/home/user/operator.log"
STATE = "/home/user/app.state"
MANIFEST = "/home/user/manifest.json"


def run_operator(timeout=25):
    proc = subprocess.Popen(
        ["/usr/bin/python3", OPERATOR],
        cwd="/home/user",
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait()
        pytest.fail(f"operator.py did not terminate within {timeout} seconds")
    finally:
        # Clean up a db process that may still be alive after the operator exits.
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass


def setup_module(module):
    assert os.path.isfile(OPERATOR), f"Operator script not found at {OPERATOR}"
    for path in (LOG, STATE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    run_operator()


def test_operator_script_exists():
    path = "/home/user/operator.py"
    assert os.path.isfile(path), f"Operator script not found at {path}"


def test_operator_log_exists():
    path = "/home/user/operator.log"
    assert os.path.isfile(path), f"Operator log not found at {path}. Did the operator run and create it?"


def test_operator_log_contents():
    path = "/home/user/operator.log"
    with open(path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "[EXEC] Starting db",
        "[STATE] db is ready",
        "[EXEC] Starting app",
        "[WARN] app crashed, restarting",
        "[EXEC] Starting app",
        "[WARN] app crashed, restarting",
        "[EXEC] Starting app"
    ]

    assert lines == expected_lines, f"Log contents do not match expected sequence. Found: {lines}"


def test_app_state():
    path = "/home/user/app.state"
    assert os.path.isfile(path), f"App state file not found at {path}. Did the app run?"
    with open(path, "r") as f:
        count = int(f.read().strip())

    assert count == 3, f"Expected app to have run exactly 3 times, but state indicates {count} runs."


def test_operator_uses_manifest_readiness_and_restart_limit(tmp_path):
    original_manifest = open(MANIFEST, "rb").read()
    db_script = tmp_path / "probe_db.py"
    app_script = tmp_path / "probe_app.py"
    db_started = tmp_path / "db_started"
    ready_signal = tmp_path / "exact_ready_printed"
    app_count = tmp_path / "app_count"
    observations = tmp_path / "observations"

    db_script.write_text(textwrap.dedent(f"""
        import pathlib
        import time

        pathlib.Path({str(db_started)!r}).write_text("started")
        print("prefix ALT_READY suffix", flush=True)
        time.sleep(2)
        pathlib.Path({str(ready_signal)!r}).write_text("ready")
        print("ALT_READY", flush=True)
        time.sleep(1)
    """))

    app_script.write_text(textwrap.dedent(f"""
        import pathlib
        import sys

        count_path = pathlib.Path({str(app_count)!r})
        count = int(count_path.read_text()) if count_path.exists() else 0
        count += 1
        count_path.write_text(str(count))
        with pathlib.Path({str(observations)!r}).open("a") as out:
            out.write("1\\n" if pathlib.Path({str(ready_signal)!r}).exists() else "0\\n")
        sys.exit(7)
    """))

    manifest = {
        "services": {
            "db": {
                "command": f"/usr/bin/python3 {db_script}",
                "ready_marker": "ALT_READY"
            },
            "app": {
                "command": f"/usr/bin/python3 {app_script}",
                "depends_on": "db",
                "restart_policy": "Always",
                "max_restarts": 1
            }
        }
    }

    try:
        with open(MANIFEST, "w") as f:
            json.dump(manifest, f)
        try:
            os.remove(LOG)
        except FileNotFoundError:
            pass

        run_operator(timeout=15)

        assert db_started.is_file(), "The db command from the manifest was not executed"
        assert app_count.is_file(), "The app command from the manifest was not executed"
        assert int(app_count.read_text().strip()) == 2, \
            "max_restarts=1 must allow exactly two total app executions"

        seen = observations.read_text().splitlines()
        assert seen == ["1", "1"], \
            "app started before db printed the configured ready marker as an exact line"

        assert os.path.isfile(LOG), "Operator did not create its log during the behavioral run"
        with open(LOG) as f:
            lines = [line.strip() for line in f if line.strip()]

        assert lines.count("[EXEC] Starting db") == 1
        assert lines.count("[STATE] db is ready") == 1
        assert lines.count("[EXEC] Starting app") == 2
        assert "[WARN] app crashed, restarting" in lines
        assert "[ERROR] app max restarts exceeded" in lines
        assert lines.index("[STATE] db is ready") < lines.index("[EXEC] Starting app")
        assert lines.index("[ERROR] app max restarts exceeded") > \
            max(i for i, line in enumerate(lines) if line == "[EXEC] Starting app")
    finally:
        with open(MANIFEST, "wb") as f:
            f.write(original_manifest)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
