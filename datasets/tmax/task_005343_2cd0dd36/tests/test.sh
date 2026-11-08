#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import stat
import subprocess
import tempfile
import time

SUPERVISOR = "/home/user/supervisor.py"
CONFIG = "/home/user/restore_config.ini"
RESTORE = "/home/user/run_restore.sh"
LOG = "/home/user/supervisor.log"
STATE = "/home/user/.restore_state"
CRON = "/home/user/restore_cron"


def run_supervisor(env=None, timeout=20):
    return subprocess.run(
        ["/usr/bin/env", "python3", SUPERVISOR],
        capture_output=True,
        env=env,
        timeout=timeout,
    )


def read_log():
    assert os.path.exists(LOG), f"Log file {LOG} was not created"
    with open(LOG, "r") as f:
        return f.read().strip().splitlines()


def test_supervisor_script_exists_and_executable():
    assert os.path.exists(SUPERVISOR), f"Missing {SUPERVISOR}"
    assert os.access(SUPERVISOR, os.X_OK), f"{SUPERVISOR} is not executable"


def test_cron_file_exists_and_correct():
    assert os.path.exists(CRON), f"Missing {CRON}"
    with open(CRON, "r") as f:
        content = f.read().strip()

    match = re.search(
        r"^\*\s+\*\s+\*\s+\*\s+\*\s+/usr/bin/env\s+python3\s+/home/user/supervisor\.py$",
        content,
        re.MULTILINE,
    )
    assert match, f"Cron file {CRON} does not contain the correct schedule and command. Found: {content}"
    assert len(content.splitlines()) == 1, f"Cron file must contain a single line. Found: {content}"


def test_supervisor_behavior_success():
    for path in (LOG, STATE):
        if os.path.exists(path):
            os.remove(path)

    result = run_supervisor()
    assert result.returncode == 0, f"Supervisor script should exit with 0 on success, got {result.returncode}"
    assert read_log() == [
        "[RETRY] Restore failed, attempt 1 of 4",
        "[RETRY] Restore failed, attempt 2 of 4",
        "[SUCCESS] Restore completed",
    ]


def test_supervisor_behavior_fatal():
    if os.path.exists(LOG):
        os.remove(LOG)

    with open(RESTORE, "rb") as f:
        original_script = f.read()
    original_mode = stat.S_IMODE(os.stat(RESTORE).st_mode)

    try:
        with open(RESTORE, "w") as f:
            f.write("#!/bin/bash\nexit 1\n")
        os.chmod(RESTORE, original_mode)

        result = run_supervisor()
        assert result.returncode != 0, "Supervisor script should exit with non-zero code when max retries reached"

        log_content = read_log()
        assert len(log_content) == 5, f"Expected 5 log lines (4 retries + 1 fatal), got {len(log_content)}"
        assert log_content[-1] == "[FATAL] Restore failed after 4 attempts", f"Expected fatal message, got: {log_content[-1]}"
        for i in range(1, 5):
            assert log_content[i - 1] == f"[RETRY] Restore failed, attempt {i} of 4", f"Expected retry line {i}, got: {log_content[i - 1]}"
    finally:
        with open(RESTORE, "wb") as f:
            f.write(original_script)
        os.chmod(RESTORE, original_mode)


def test_randomized_config_subprocess_retry_and_timing():
    with open(CONFIG, "rb") as f:
        original_config = f.read()
    with open(RESTORE, "rb") as f:
        original_restore = f.read()
    original_mode = stat.S_IMODE(os.stat(RESTORE).st_mode)

    workdir = tempfile.mkdtemp(prefix="supervisor_verify_")
    invocation_file = os.path.join(workdir, "invocations")
    subprocess_marker = os.path.join(workdir, "subprocess_calls")
    hookdir = os.path.join(workdir, "hook")
    os.mkdir(hookdir)

    # This hook runs inside the submitted supervisor and records actual calls made
    # through Python's subprocess module to the required restore path.
    with open(os.path.join(hookdir, "sitecustomize.py"), "w") as f:
        f.write('''import os\nimport subprocess\n_real_popen = subprocess.Popen\ndef _tracked_popen(*args, **kwargs):\n    command = args[0] if args else kwargs.get("args", "")\n    if isinstance(command, (list, tuple)):\n        text = " ".join(os.fspath(x) for x in command)\n    else:\n        text = os.fspath(command) if isinstance(command, os.PathLike) else str(command)\n    if "/home/user/run_restore.sh" in text:\n        marker = os.environ.get("SUPERVISOR_SUBPROCESS_MARKER")\n        if marker:\n            with open(marker, "a") as out:\n                out.write("call\\n")\n    return _real_popen(*args, **kwargs)\nsubprocess.Popen = _tracked_popen\n''')

    def install_fixture(token, failures):
        fixture = f'''#!/usr/bin/python3
import os
import time
path = {invocation_file!r}
token = {token!r}
try:
    with open(path, "r") as inp:
        attempt = len(inp.read().splitlines()) + 1
except FileNotFoundError:
    attempt = 1
with open(path, "a") as out:
    out.write(f"{{token}} {{attempt}} {{time.monotonic()}}\\n")
raise SystemExit(1 if attempt <= {failures} else 0)
'''
        with open(RESTORE, "w") as f:
            f.write(fixture)
        os.chmod(RESTORE, 0o755)

    def execute_scenario(max_retries, failures, should_succeed):
        token = secrets.token_hex(20)
        for path in (LOG, invocation_file, subprocess_marker):
            if os.path.exists(path):
                os.remove(path)

        with open(CONFIG, "w") as f:
            f.write(f"[Settings]\ntarget_dir=/tmp/unused_{token}\nmax_retries = {max_retries}\n")
        install_fixture(token, failures)

        env = os.environ.copy()
        env["PYTHONPATH"] = hookdir
        env["SUPERVISOR_SUBPROCESS_MARKER"] = subprocess_marker
        started = time.monotonic()
        result = run_supervisor(env=env)
        elapsed = time.monotonic() - started

        expected_attempts = failures + 1 if should_succeed else max_retries
        assert (result.returncode == 0) == should_succeed, (
            f"Unexpected supervisor exit code {result.returncode}; stderr={result.stderr!r}"
        )

        with open(invocation_file, "r") as f:
            records = [line.split() for line in f.read().splitlines()]
        assert len(records) == expected_attempts, f"Restore ran {len(records)} times, expected {expected_attempts}"
        assert all(parts[0] == token for parts in records), "The randomized restore fixture was not executed correctly"
        assert [int(parts[1]) for parts in records] == list(range(1, expected_attempts + 1))

        with open(subprocess_marker, "r") as f:
            subprocess_calls = f.read().splitlines()
        assert len(subprocess_calls) == expected_attempts, (
            "Each restore attempt must be launched through Python's subprocess module"
        )

        timestamps = [float(parts[2]) for parts in records]
        gaps = [b - a for a, b in zip(timestamps, timestamps[1:])]
        assert all(0.80 <= gap <= 1.70 for gap in gaps), f"Retries were not separated by one second: {gaps}"
        assert elapsed >= 0.80 * (expected_attempts - 1), "Supervisor did not wait one second between retries"

        expected_log = [
            f"[RETRY] Restore failed, attempt {i} of {max_retries}"
            for i in range(1, failures + 1 if should_succeed else max_retries + 1)
        ]
        if should_succeed:
            expected_log.append("[SUCCESS] Restore completed")
        else:
            expected_log.append(f"[FATAL] Restore failed after {max_retries} attempts")
        assert read_log() == expected_log

    try:
        success_max = 2 + secrets.randbelow(3)
        success_failures = 1 + secrets.randbelow(success_max - 1)
        execute_scenario(success_max, success_failures, True)

        fatal_max = 2 + secrets.randbelow(3)
        execute_scenario(fatal_max, fatal_max + 5, False)
    finally:
        with open(CONFIG, "wb") as f:
            f.write(original_config)
        with open(RESTORE, "wb") as f:
            f.write(original_restore)
        os.chmod(RESTORE, original_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
