#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess
import tempfile
import time
import uuid
from collections import Counter


def test_run_tests_script_exists_and_executable():
    script_path = "/home/user/run_tests.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    st = os.stat(script_path)
    assert bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)), f"Script {script_path} is not executable."


def test_bats_exec_suite_fixed():
    file_path = "/app/bats-core-1.8.2/libexec/bats-core/bats-exec-suite"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."
    with open(file_path, "r") as f:
        content = f.read()
    assert "jobs=1 # DEBUG: force single job" not in content, f"The perturbation 'jobs=1' is still present in {file_path}."


def test_execution_time_and_correctness():
    script_path = "/home/user/run_tests.sh"
    suite_path = "/home/user/web-sec-tests"
    bats_path = "/app/bats-core-1.8.2/bin/bats"

    assert os.path.isfile(script_path), "Cannot measure execution time because script does not exist."
    assert os.path.isfile(bats_path), f"The fixed bats executable {bats_path} does not exist."

    token = uuid.uuid4().hex
    backup_path = f"/home/user/.web-sec-tests.verifier-{token}"
    real_bats_path = f"{bats_path}.verifier-real-{token}"
    marker_fd, marker_path = tempfile.mkstemp(prefix="bats-markers-", dir="/tmp")
    call_fd, call_log = tempfile.mkstemp(prefix="bats-calls-", dir="/tmp")
    os.close(marker_fd)
    os.close(call_fd)
    os.chmod(marker_path, 0o666)
    os.chmod(call_log, 0o666)

    result = None
    execution_time = None
    call_lines = []
    marker_lines = []

    try:
        os.rename(suite_path, backup_path)
        os.mkdir(suite_path, 0o755)

        expected_markers = []
        for i in range(1, 25):
            marker = f"{token}-{i}"
            expected_markers.append(marker)
            test_file = os.path.join(suite_path, f"generated_{i}.bats")
            with open(test_file, "w") as f:
                f.write(
                    f'@test "Verifier generated parallel test {i}" {{\n'
                    f"  printf '%s\\n' '{marker}' >> '{marker_path}'\n"
                    "  sleep 1\n"
                    f"  [ $(({i} * {i})) -eq {i * i} ]\n"
                    "}\n"
                )
            os.chmod(test_file, 0o644)

        shutil.chown(suite_path, user="user", group="user")
        for name in os.listdir(suite_path):
            shutil.chown(os.path.join(suite_path, name), user="user", group="user")

        os.rename(bats_path, real_bats_path)
        with open(bats_path, "w") as f:
            f.write("#!/bin/bash\n")
            f.write("{ printf 'CALL'; printf '\\t%s' \"$@\"; printf '\\n'; } >> '{call_log}'\n")
            f.write(f"exec '{real_bats_path}' \"$@\"\n")
        os.chmod(bats_path, 0o755)

        start_time = time.time()
        result = subprocess.run(
            ["runuser", "-u", "user", "--", "bash", script_path],
            capture_output=True,
            text=True,
        )
        execution_time = time.time() - start_time

        with open(call_log, "r") as f:
            call_lines = [line.rstrip("\n").split("\t")[1:] for line in f if line.startswith("CALL\t")]
        with open(marker_path, "r") as f:
            marker_lines = [line.strip() for line in f if line.strip()]

    finally:
        if os.path.lexists(bats_path):
            os.unlink(bats_path)
        if os.path.lexists(real_bats_path):
            os.rename(real_bats_path, bats_path)
        if os.path.isdir(suite_path):
            shutil.rmtree(suite_path)
        if os.path.lexists(backup_path):
            os.rename(backup_path, suite_path)
        for path in (marker_path, call_log):
            if os.path.exists(path):
                os.unlink(path)

    assert result is not None, "The test runner was not executed."
    assert result.returncode == 0, f"Tests failed or script errored. Return code: {result.returncode}\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"

    output = result.stdout + "\n" + result.stderr
    assert "24 tests" in output or "ok 24" in output, "The script output does not indicate that 24 tests were run. Did it execute the bats test suite?"
    assert execution_time <= 6.0, f"Execution time {execution_time:.2f}s exceeded threshold of 6.0s. The test suite is likely not running in parallel."

    valid_call = False
    for args in call_lines:
        has_target = any(os.path.normpath(arg) == suite_path for arg in args)
        has_jobs_8 = any(arg in ("--jobs=8", "-j=8") for arg in args)
        for index, arg in enumerate(args[:-1]):
            if arg in ("--jobs", "-j") and args[index + 1] == "8":
                has_jobs_8 = True
        if has_target and has_jobs_8:
            valid_call = True
            break
    assert valid_call, "run_tests.sh did not invoke the specified bats executable on /home/user/web-sec-tests with 8 jobs."

    expected = Counter(f"{token}-{i}" for i in range(1, 25))
    assert Counter(marker_lines) == expected, "The generated Bats tests were not each executed exactly once."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
