#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import sqlite3
import stat
import subprocess
import tempfile

APP = "/home/user/legacy_app"
RUNNER = os.path.join(APP, "runner.sh")
PROCESSOR = os.path.join(APP, "bin", "processor")
RESULTS = os.path.join(APP, "results.db")


def run_runner(timeout=10):
    env = os.environ.copy()
    env.pop("BYPASS_LEGACY_LOCKS", None)
    proc = subprocess.Popen(
        [RUNNER],
        cwd=APP,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.communicate()
        raise AssertionError("runner.sh did not complete; the legacy lock bypass is not working")
    assert proc.returncode == 0, f"runner.sh exited with {proc.returncode}. stdout={stdout!r}, stderr={stderr!r}"


def assert_results_database():
    assert os.path.isfile(RESULTS), "runner.sh did not create results.db"
    with sqlite3.connect(RESULTS) as db:
        table = db.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='completed'"
        ).fetchone()
        assert table is not None, "results.db has no completed table"
        total = db.execute("SELECT SUM(value) FROM completed").fetchone()[0]
    assert total == 500, f"Expected completed.value to sum to 500, got {total!r}"
    return total


def test_crash_tx_txt():
    path = "/home/user/crash_tx.txt"
    assert os.path.isfile(path), f"File {path} is missing. Did you extract the transaction ID?"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "TX-99382-ALPHA", f"Expected 'TX-99382-ALPHA' in {path}, but got '{content}'"


def test_runner_sh_fixed_and_pipeline_executes():
    assert os.path.isfile(RUNNER), f"File {RUNNER} is missing."
    assert os.access(RUNNER, os.X_OK), f"File {RUNNER} is not executable."
    with open(RUNNER, "r") as f:
        content = f.read()

    # Preserve the original assertion and additionally verify the variable reaches processor.
    assert "BYPASS_LEGACY_LOCKS" in content, f"The required environment variable bypass was not found in {RUNNER}."

    assert os.path.isfile(PROCESSOR), f"File {PROCESSOR} is missing."
    assert os.access(PROCESSOR, os.X_OK), f"File {PROCESSOR} is not executable."
    with open(PROCESSOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", "bin/processor is no longer the compiled processor binary"

    # Execute the submitted runner against the real processor from a clean results state.
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    run_runner()
    assert_results_database()

    # Replace processor temporarily with an instrumented executable to prove that runner
    # invokes it for the queued items and exports the bypass variable to each child.
    with sqlite3.connect(os.path.join(APP, "data.db")) as db:
        pending = db.execute(
            "SELECT payload FROM queue WHERE status='PENDING' ORDER BY id"
        ).fetchall()
    expected_payloads = [row[0] for row in pending]
    assert expected_payloads == ["A", "B"], "The pending input queue was unexpectedly modified"

    original = open(PROCESSOR, "rb").read()
    original_mode = stat.S_IMODE(os.stat(PROCESSOR).st_mode)
    fd, log_path = tempfile.mkstemp(prefix="processor_calls_", dir="/tmp")
    os.close(fd)
    probe = f'''#!/bin/bash
printf '%s|%s|%s\\n' "${{BYPASS_LEGACY_LOCKS+x}}" "${{BYPASS_LEGACY_LOCKS-}}" "$1" >> {log_path!r}
exit 0
'''
    try:
        with open(PROCESSOR, "w") as f:
            f.write(probe)
        os.chmod(PROCESSOR, 0o755)
        if os.path.exists(RESULTS):
            os.remove(RESULTS)
        run_runner()
        assert_results_database()
        with open(log_path, "r") as f:
            calls = [line.rstrip("\n").split("|", 2) for line in f if line.strip()]
        assert len(calls) == len(expected_payloads), (
            f"runner.sh invoked processor {len(calls)} times; expected {len(expected_payloads)}"
        )
        assert sorted(call[2] for call in calls) == sorted(expected_payloads), (
            "runner.sh did not invoke processor for each pending payload"
        )
        assert all(call[0] == "x" for call in calls), (
            "BYPASS_LEGACY_LOCKS was not exported into the processor environment"
        )
    finally:
        with open(PROCESSOR, "wb") as f:
            f.write(original)
        os.chmod(PROCESSOR, original_mode)
        try:
            os.remove(log_path)
        except FileNotFoundError:
            pass


def test_total_value_txt():
    path = "/home/user/total_value.txt"
    assert os.path.isfile(path), f"File {path} is missing. Did you calculate the sum and save it?"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "500", f"Expected '500' in {path}, but got '{content}'"
    assert int(content) == assert_results_database(), (
        "total_value.txt does not match the completed table populated by runner.sh"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
