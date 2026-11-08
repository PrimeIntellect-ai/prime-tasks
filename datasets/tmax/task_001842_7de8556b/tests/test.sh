#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import os
import re
import signal
import subprocess
import tempfile
import time

BASE_DIR = "/home/user/log_pipeline"
MERGE = os.path.join(BASE_DIR, "merge_logs.sh")

EXPECTED_RUN_ALL = '''#!/bin/bash
while read -r f1 f2; do
    ./merge_logs.sh "$f1" "$f2" &
done < jobs.txt
wait
echo "All jobs finished successfully" > success.log
'''

EXPECTED_JOBS = '''inputs/app1.log inputs/app3.log
inputs/app4.log inputs/app5.log
inputs/app10.log inputs/app11.log
inputs/app2.log inputs/app6.log
inputs/app6.log inputs/app2.log
inputs/app8.log inputs/app9.log
'''


def test_mre_txt_content():
    mre_path = os.path.join(BASE_DIR, "mre.txt")
    assert os.path.isfile(mre_path), f"File {mre_path} is missing."
    with open(mre_path, "r") as f:
        content = f.read().strip()
    valid_lines = [
        "inputs/app2.log inputs/app6.log",
        "inputs/app6.log inputs/app2.log",
    ]
    assert content in valid_lines, (
        "mre.txt must contain exactly one of the deadlocking lines. "
        f"Found: {content}"
    )


def test_protected_files_unchanged():
    with open(os.path.join(BASE_DIR, "run_all.sh"), "r") as f:
        assert f.read() == EXPECTED_RUN_ALL, "run_all.sh must not be changed."
    with open(os.path.join(BASE_DIR, "jobs.txt"), "r") as f:
        assert f.read() == EXPECTED_JOBS, "jobs.txt must not be changed."


def test_merge_logs_sh_modified_and_has_assertion():
    assert os.path.isfile(MERGE), f"Script {MERGE} is missing."
    assert os.access(MERGE, os.X_OK), f"Script {MERGE} is not executable."
    with open(MERGE, "r") as f:
        content = f.read()

    # Preserve the original modification check.
    has_comparison = "<" in content or ">" in content or "sort" in content
    assert has_comparison, (
        "merge_logs.sh does not seem to contain alphabetical comparison logic "
        "to prevent deadlocks."
    )

    # The required assertion must occur before the first real locking step and
    # must fail/exit when its ordering condition is not satisfied.
    active_lines = []
    offset = 0
    first_lock = None
    for line in content.splitlines(True):
        stripped = line.lstrip()
        if not stripped.startswith("#") and (
            re.search(r"\bflock\b", line) or
            (re.search(r"\bexec\b", line) and ".lock" in line)
        ):
            first_lock = offset
            break
        offset += len(line)
    assert first_lock is not None, "merge_logs.sh contains no locking step."
    prefix = content[:first_lock]

    bracket_expr = r"(?:\[\[[^\]]*(?:<|>)[^\]]*\]\]|\[[^\]]*(?:\\<|\\>)[^\]]*\])"
    short_circuit = re.search(
        bracket_expr + r"\s*\|\|\s*(?:exit\b|return\b|\{[\s\S]{0,200}?\b(?:exit|return)\b)",
        prefix,
    )
    conditional_exit = re.search(
        r"\bif\s+!?\s*" + bracket_expr +
        r"\s*;?\s*then(?:(?!\bfi\b)[\s\S]){0,300}?\b(?:exit|return)\b",
        prefix,
    )
    assert short_circuit or conditional_exit, (
        "merge_logs.sh must contain a bash assertion before locking that exits "
        "unless the first lock path is alphabetically before or equal to the second."
    )


def _try_exclusive(fd):
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return True
    except BlockingIOError:
        return False


def _exercise_lock_order(reverse_arguments):
    with tempfile.TemporaryDirectory(prefix="lock-order-") as td:
        low = os.path.join(td, "a.log")
        high = os.path.join(td, "z.log")
        with open(low, "w") as f:
            f.write("a\n")
        with open(high, "w") as f:
            f.write("z\n")

        low_fd = os.open(low + ".lock", os.O_RDWR | os.O_CREAT, 0o666)
        high_fd = os.open(high + ".lock", os.O_RDWR | os.O_CREAT, 0o666)
        probe_low_fd = os.open(low + ".lock", os.O_RDWR)
        proc = None
        try:
            # Hold the alphabetically first lock so the child must block there.
            fcntl.flock(low_fd, fcntl.LOCK_EX)
            args = [MERGE, high, low] if reverse_arguments else [MERGE, low, high]
            proc = subprocess.Popen(
                args,
                cwd=td,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                start_new_session=True,
            )
            time.sleep(0.7)
            assert proc.poll() is None, (
                "merge_logs.sh did not wait for the alphabetically first lock."
            )

            # While it is blocked on the first lock, the second lock must remain free.
            assert _try_exclusive(high_fd), (
                "merge_logs.sh acquired the alphabetically later lock first."
            )

            # Let the child acquire the first lock while continuing to hold the second.
            fcntl.flock(low_fd, fcntl.LOCK_UN)
            acquired_low = False
            deadline = time.time() + 3
            while time.time() < deadline and proc.poll() is None:
                if _try_exclusive(probe_low_fd):
                    fcntl.flock(probe_low_fd, fcntl.LOCK_UN)
                    time.sleep(0.03)
                else:
                    acquired_low = True
                    break
            assert acquired_low, (
                "merge_logs.sh did not acquire and retain the alphabetically first lock "
                "before attempting the second."
            )
            assert proc.poll() is None, "merge_logs.sh did not wait for the second lock."

            fcntl.flock(high_fd, fcntl.LOCK_UN)
            stdout, stderr = proc.communicate(timeout=5)
            assert proc.returncode == 0, (
                f"merge_logs.sh failed with code {proc.returncode}: {stdout}{stderr}"
            )
        finally:
            for fd in (low_fd, high_fd, probe_low_fd):
                try:
                    fcntl.flock(fd, fcntl.LOCK_UN)
                except OSError:
                    pass
            if proc is not None and proc.poll() is None:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait()
            os.close(low_fd)
            os.close(high_fd)
            os.close(probe_low_fd)


def test_lock_acquisition_order_for_both_argument_orders():
    _exercise_lock_order(False)
    _exercise_lock_order(True)


def test_run_all_really_completes_and_creates_success_log():
    success_path = os.path.join(BASE_DIR, "success.log")
    try:
        os.remove(success_path)
    except FileNotFoundError:
        pass

    proc = subprocess.Popen(
        [os.path.join(BASE_DIR, "run_all.sh")],
        cwd=BASE_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = proc.communicate(timeout=12)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.wait()
        raise AssertionError("run_all.sh deadlocked or failed to complete within 12 seconds.")

    assert proc.returncode == 0, (
        f"run_all.sh failed with code {proc.returncode}: {stdout}{stderr}"
    )
    assert os.path.isfile(success_path), (
        f"File {success_path} is missing. Did run_all.sh complete successfully?"
    )
    with open(success_path, "r") as f:
        content = f.read().strip()
    assert content == "All jobs finished successfully", (
        f"success.log has incorrect content: {content}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
