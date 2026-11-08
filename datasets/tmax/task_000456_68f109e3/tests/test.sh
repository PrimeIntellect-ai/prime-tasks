#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import os
import stat
import subprocess
import tarfile
import uuid

import pytest

BASE = "/home/user/account_system"
SUPERVISOR = os.path.join(BASE, "supervisor.py")
DB_INIT = os.path.join(BASE, "db_init.py")
PROFILE_GEN = os.path.join(BASE, "profile_gen.py")
CI_SCRIPT = os.path.join(BASE, "ci_run.sh")


@contextlib.contextmanager
def replaced_files(replacements):
    originals = {}
    try:
        for path, content in replacements.items():
            st = os.stat(path)
            with open(path, "rb") as f:
                originals[path] = (f.read(), stat.S_IMODE(st.st_mode))
            with open(path, "w") as f:
                f.write(content)
            os.chmod(path, 0o755)
        yield
    finally:
        for path, (content, mode) in originals.items():
            with open(path, "wb") as f:
                f.write(content)
            os.chmod(path, mode)


def remove_path(path):
    if os.path.isdir(path) and not os.path.islink(path):
        import shutil
        shutil.rmtree(path)
    elif os.path.exists(path) or os.path.islink(path):
        os.remove(path)


@pytest.fixture(scope="session", autouse=True)
def run_ci_script():
    if not os.path.exists(CI_SCRIPT):
        pytest.fail(f"Required script {CI_SCRIPT} does not exist.")
    if not os.access(CI_SCRIPT, os.X_OK):
        pytest.fail(f"Script {CI_SCRIPT} is not executable.")

    cleanup_files = [
        os.path.join(BASE, "db.lock"),
        os.path.join(BASE, "fail_state.tmp"),
        os.path.join(BASE, "ci_status.log"),
        os.path.join(BASE, "release.tar.gz"),
        os.path.join(BASE, "profiles/groupA/user1.json"),
        os.path.join(BASE, "profiles/user2.json"),
    ]
    for path in cleanup_files:
        remove_path(path)

    subprocess.run([CI_SCRIPT], cwd=BASE, capture_output=True, text=True, timeout=20)


def test_ci_run_exists_and_executable():
    assert os.path.exists(CI_SCRIPT), f"{CI_SCRIPT} is missing."
    assert os.path.isfile(CI_SCRIPT), f"{CI_SCRIPT} is not a regular file."
    assert os.access(CI_SCRIPT, os.X_OK), f"{CI_SCRIPT} is not executable."


def test_supervisor_execution_success():
    profile_path = os.path.join(BASE, "profiles/groupA/user1.json")
    assert os.path.exists(profile_path), (
        "Supervisor did not successfully run profile_gen.py to completion. "
        "Check dependency waiting and restart policies."
    )


def test_ci_status_log():
    log_path = os.path.join(BASE, "ci_status.log")
    assert os.path.exists(log_path), f"Log file {log_path} was not created."
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert content == "SUCCESS", f"Expected ci_status.log to contain exactly 'SUCCESS', got '{content}'."


def test_release_tarball_exists_and_valid():
    tar_path = os.path.join(BASE, "release.tar.gz")
    assert os.path.exists(tar_path), f"Tarball {tar_path} was not created."
    assert tarfile.is_tarfile(tar_path), f"{tar_path} is not a valid tar archive."

    with tarfile.open(tar_path, "r:gz") as tar:
        names = tar.getnames()
        assert any("user1.json" in name for name in names), "Tarball does not contain the generated profiles."


def test_profile_permissions():
    profiles_dir = os.path.join(BASE, "profiles")
    assert os.path.exists(profiles_dir), f"Directory {profiles_dir} does not exist."

    for root, dirs, files in os.walk(profiles_dir):
        for d in dirs:
            dir_path = os.path.join(root, d)
            mode = stat.S_IMODE(os.stat(dir_path).st_mode)
            assert mode == 0o750, f"Directory {dir_path} has incorrect permissions: {oct(mode)} (expected 0o750)."

        for name in files:
            file_path = os.path.join(root, name)
            mode = stat.S_IMODE(os.stat(file_path).st_mode)
            assert mode == 0o640, f"File {file_path} has incorrect permissions: {oct(mode)} (expected 0o640)."


def test_supervisor_is_executable_python_artifact():
    assert os.path.isfile(SUPERVISOR), f"Required supervisor {SUPERVISOR} is missing."
    result = subprocess.run(
        ["python3", "-m", "py_compile", SUPERVISOR],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"supervisor.py is not valid Python: {result.stderr}"


def test_supervisor_waits_and_supports_three_restarts():
    token = uuid.uuid4().hex
    marker = os.path.join(BASE, f".db_done_{token}")
    attempts = os.path.join(BASE, f".attempts_{token}")
    violation = os.path.join(BASE, f".ordering_violation_{token}")

    db_probe = f'''#!/usr/bin/env python3
import time
from pathlib import Path
time.sleep(0.4)
Path({marker!r}).write_text("done")
'''
    profile_probe = f'''#!/usr/bin/env python3
import os
import sys
from pathlib import Path
marker = {marker!r}
attempt_file = Path({attempts!r})
if not os.path.exists(marker):
    Path({violation!r}).write_text("profile started before db completed")
    sys.exit(31)
count = int(attempt_file.read_text()) if attempt_file.exists() else 0
count += 1
attempt_file.write_text(str(count))
if count < 4:
    sys.exit(23)
sys.exit(0)
'''

    try:
        with replaced_files({DB_INIT: db_probe, PROFILE_GEN: profile_probe}):
            result = subprocess.run(
                ["python3", SUPERVISOR], cwd=BASE,
                capture_output=True, text=True, timeout=15,
            )
        assert result.returncode == 0, (
            "Supervisor did not succeed when profile_gen succeeded on the fourth total attempt. "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        assert not os.path.exists(violation), "profile_gen.py was started before db_init.py completed successfully."
        assert os.path.exists(attempts), "Supervisor never executed the instrumented profile_gen.py."
        assert int(open(attempts).read()) == 4, "Supervisor did not perform exactly three restarts before success."
    finally:
        for path in (marker, attempts, violation):
            remove_path(path)


def test_supervisor_stops_after_maximum_restarts_and_returns_failure():
    token = uuid.uuid4().hex
    marker = os.path.join(BASE, f".db_ready_{token}")
    attempts = os.path.join(BASE, f".failed_attempts_{token}")

    db_probe = f'''#!/usr/bin/env python3
from pathlib import Path
Path({marker!r}).write_text("ready")
'''
    profile_probe = f'''#!/usr/bin/env python3
import os
import sys
from pathlib import Path
if not os.path.exists({marker!r}):
    sys.exit(32)
p = Path({attempts!r})
n = int(p.read_text()) if p.exists() else 0
p.write_text(str(n + 1))
sys.exit(19)
'''

    try:
        with replaced_files({DB_INIT: db_probe, PROFILE_GEN: profile_probe}):
            result = subprocess.run(
                ["python3", SUPERVISOR], cwd=BASE,
                capture_output=True, text=True, timeout=15,
            )
        assert result.returncode == 1, f"Supervisor must exit 1 after exhausting restarts, got {result.returncode}."
        assert os.path.exists(attempts), "Supervisor never executed profile_gen.py."
        assert int(open(attempts).read()) == 4, "Maximum three restarts must mean exactly four total failed attempts."
    finally:
        for path in (marker, attempts):
            remove_path(path)


def test_supervisor_does_not_start_profile_after_database_failure():
    token = uuid.uuid4().hex
    launched = os.path.join(BASE, f".profile_launched_{token}")
    db_probe = '''#!/usr/bin/env python3
import sys
sys.exit(7)
'''
    profile_probe = f'''#!/usr/bin/env python3
from pathlib import Path
Path({launched!r}).write_text("launched")
'''

    try:
        with replaced_files({DB_INIT: db_probe, PROFILE_GEN: profile_probe}):
            result = subprocess.run(
                ["python3", SUPERVISOR], cwd=BASE,
                capture_output=True, text=True, timeout=10,
            )
        assert result.returncode != 0, "Supervisor reported success even though db_init.py failed."
        assert not os.path.exists(launched), "profile_gen.py was launched after db_init.py failed."
    finally:
        remove_path(launched)


def test_ci_runs_supervisor_and_writes_failure_when_it_fails():
    token = uuid.uuid4().hex
    invoked = os.path.join(BASE, f".supervisor_invoked_{token}")
    status = os.path.join(BASE, "ci_status.log")
    tar_path = os.path.join(BASE, "release.tar.gz")
    failing_supervisor = f'''#!/usr/bin/env python3
from pathlib import Path
import sys
Path({invoked!r}).write_text("invoked")
sys.exit(9)
'''

    remove_path(status)
    remove_path(tar_path)
    try:
        with replaced_files({SUPERVISOR: failing_supervisor}):
            subprocess.run(
                [CI_SCRIPT], cwd=BASE,
                capture_output=True, text=True, timeout=15,
            )
        assert os.path.exists(invoked), "ci_run.sh did not execute supervisor.py using python3."
        assert os.path.exists(status), "ci_run.sh did not create ci_status.log after supervisor failure."
        with open(status, "r") as f:
            content = f.read().strip()
        assert content == "FAILURE", f"Expected FAILURE after supervisor failure, got {content!r}."
        assert not os.path.exists(tar_path), "ci_run.sh packaged a release even though the supervisor failed."
    finally:
        remove_path(invoked)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
