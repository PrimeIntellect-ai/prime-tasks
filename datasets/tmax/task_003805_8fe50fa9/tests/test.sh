#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import builtins
import configparser
import io
import os
import shutil
import stat
import subprocess
import sys
import time

PROJECT_DIR = "/home/user/project"


def test_services_ini_updated():
    ini_path = os.path.join(PROJECT_DIR, "services.ini")
    assert os.path.isfile(ini_path), "services.ini is missing."

    config = configparser.ConfigParser()
    config.read(ini_path)

    assert config.has_section("analytics-worker"), "Missing [analytics-worker] section."
    assert config.has_option("analytics-worker", "After"), "Missing 'After' directive in [analytics-worker]."

    after_val = config.get("analytics-worker", "After")
    assert after_val == "data-fetcher", f"Expected 'After=data-fetcher', got 'After={after_val}'"


def test_analytics_worker_retry_logic():
    worker_path = os.path.join(PROJECT_DIR, "analytics-worker.py")
    assert os.path.isfile(worker_path), "analytics-worker.py is missing."

    with open(worker_path, "r") as f:
        content = f.read()

    # Preserve the original source-level assertions.
    assert "except " in content or "except:" in content or "Exception" in content, "No exception handling found in analytics-worker.py."
    assert "time.sleep(1)" in content or "time.sleep(1.0)" in content, "Missing time.sleep(1) in analytics-worker.py."
    assert "sys.exit(1)" in content or "exit(1)" in content, "Missing exit code 1 on failure in analytics-worker.py."
    assert "for " in content or "while " in content, "No loop construct found for retries in analytics-worker.py."


def _execute_worker(fake_open, fake_sleep):
    worker_path = os.path.join(PROJECT_DIR, "analytics-worker.py")
    with open(worker_path, "r") as f:
        source = f.read()
    code = compile(source, worker_path, "exec")

    real_open = builtins.open
    real_sleep = time.sleep
    builtins.open = fake_open
    time.sleep = fake_sleep
    try:
        try:
            exec(code, {"__name__": "__main__", "__file__": worker_path})
            return None
        except SystemExit as exc:
            return exc.code
    finally:
        builtins.open = real_open
        time.sleep = real_sleep


def test_analytics_worker_makes_four_attempts_and_succeeds_after_three_misses():
    target = os.path.join(PROJECT_DIR, "data", "metrics.csv")
    attempts = []
    sleeps = []

    def fake_open(path, mode="r", *args, **kwargs):
        assert os.fspath(path) == target, f"Worker opened unexpected path: {path}"
        attempts.append((os.fspath(path), mode))
        if len(attempts) <= 3:
            raise FileNotFoundError(target)
        return io.StringIO("id,value\n1,100\n2,200\n")

    code = _execute_worker(fake_open, lambda seconds: sleeps.append(seconds))
    assert code in (None, 0), f"Worker did not succeed on its fourth attempt (exit={code})"
    assert len(attempts) == 4, f"Expected exactly 4 open attempts, got {len(attempts)}"
    assert sleeps == [1, 1, 1], f"Expected three one-second waits, got {sleeps}"


def test_analytics_worker_exits_one_after_four_missing_file_attempts():
    target = os.path.join(PROJECT_DIR, "data", "metrics.csv")
    attempts = []
    sleeps = []

    def fake_open(path, mode="r", *args, **kwargs):
        assert os.fspath(path) == target, f"Worker opened unexpected path: {path}"
        attempts.append((os.fspath(path), mode))
        raise FileNotFoundError(target)

    code = _execute_worker(fake_open, lambda seconds: sleeps.append(seconds))
    assert code == 1, f"Expected exit code 1 after exhausted retries, got {code}"
    assert len(attempts) == 4, f"Expected exactly 4 open attempts, got {len(attempts)}"
    assert sleeps == [1, 1, 1], f"Expected three one-second waits, got {sleeps}"


def test_analytics_worker_only_retries_file_not_found():
    target = os.path.join(PROJECT_DIR, "data", "metrics.csv")
    attempts = []
    sleeps = []

    def fake_open(path, mode="r", *args, **kwargs):
        assert os.fspath(path) == target, f"Worker opened unexpected path: {path}"
        attempts.append((os.fspath(path), mode))
        raise PermissionError(target)

    try:
        _execute_worker(fake_open, lambda seconds: sleeps.append(seconds))
    except PermissionError:
        pass
    else:
        raise AssertionError("Worker swallowed or retried PermissionError instead of catching only FileNotFoundError")

    assert len(attempts) == 1, f"PermissionError should not be retried; got {len(attempts)} attempts"
    assert sleeps == [], f"PermissionError should not cause a retry sleep; got {sleeps}"


def test_run_pipeline_script_exists_and_executable():
    script_path = os.path.join(PROJECT_DIR, "run_pipeline.sh")
    assert os.path.isfile(script_path), "run_pipeline.sh is missing."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), "run_pipeline.sh is not executable."


def test_run_pipeline_execution_and_status():
    script_path = os.path.join(PROJECT_DIR, "run_pipeline.sh")
    assert os.path.isfile(script_path), "run_pipeline.sh is missing."

    result = subprocess.run(["/bin/bash", script_path], capture_output=True, text=True)

    status_path = os.path.join(PROJECT_DIR, "status.txt")
    assert os.path.isfile(status_path), "status.txt was not created by run_pipeline.sh."
    with open(status_path, "r") as f:
        status_content = f.read().strip()
    assert status_content == "PIPELINE_SUCCESS", f"Expected PIPELINE_SUCCESS in status.txt, got '{status_content}'"

    log_path = os.path.join(PROJECT_DIR, "logs", "pipeline.log")
    assert os.path.isfile(log_path), "pipeline.log was not created in logs directory."
    with open(log_path, "r") as f:
        log_content = f.read()

    assert "Starting data-fetcher..." in log_content, "Log file missing data-fetcher startup message."
    assert "Starting analytics-worker..." in log_content, "Log file missing analytics-worker startup message."
    assert "All services completed successfully." in log_content, "Log file missing successful completion message."


def test_run_pipeline_really_cleans_and_executes_supervisor_with_redirects_and_statuses():
    script_path = os.path.join(PROJECT_DIR, "run_pipeline.sh")
    supervisor_path = os.path.join(PROJECT_DIR, "supervisor.py")
    data_dir = os.path.join(PROJECT_DIR, "data")
    logs_dir = os.path.join(PROJECT_DIR, "logs")
    probe_path = os.path.join(PROJECT_DIR, ".supervisor_probe")
    log_path = os.path.join(logs_dir, "pipeline.log")
    status_path = os.path.join(PROJECT_DIR, "status.txt")

    with open(supervisor_path, "rb") as f:
        original_supervisor = f.read()
    original_mode = stat.S_IMODE(os.stat(supervisor_path).st_mode)

    probe_supervisor = '''import os
import sys
project = "/home/user/project"
data = os.path.join(project, "data")
logs = os.path.join(project, "logs")
clean = os.path.isdir(data) and os.listdir(data) == []
logs_ready = os.path.isdir(logs)
with open(os.path.join(project, ".supervisor_probe"), "w") as f:
    f.write("CLEAN=" + str(clean) + "\\nLOGS=" + str(logs_ready) + "\\n")
print("PROBE_SUPERVISOR_STDOUT", flush=True)
print("PROBE_SUPERVISOR_STDERR", file=sys.stderr, flush=True)
sys.exit(int(os.environ.get("PROBE_EXIT", "0")))
'''

    try:
        with open(supervisor_path, "w") as f:
            f.write(probe_supervisor)

        for exit_code, expected_status in ((0, "PIPELINE_SUCCESS"), (7, "PIPELINE_FAILED")):
            shutil.rmtree(data_dir, ignore_errors=True)
            os.makedirs(os.path.join(data_dir, "stale-subdir"))
            with open(os.path.join(data_dir, "stale.txt"), "w") as f:
                f.write("stale")
            with open(os.path.join(data_dir, "stale-subdir", "old.txt"), "w") as f:
                f.write("old")

            shutil.rmtree(logs_dir, ignore_errors=True)
            if os.path.exists(probe_path):
                os.remove(probe_path)
            if os.path.exists(status_path):
                os.remove(status_path)

            env = os.environ.copy()
            env["PROBE_EXIT"] = str(exit_code)
            subprocess.run(["/bin/bash", script_path], capture_output=True, text=True, env=env, timeout=20)

            assert os.path.isfile(probe_path), "run_pipeline.sh did not execute /home/user/project/supervisor.py"
            with open(probe_path, "r") as f:
                probe = f.read()
            assert "CLEAN=True" in probe, "data directory was not empty when the supervisor started"
            assert "LOGS=True" in probe, "logs directory did not exist when the supervisor started"

            assert os.path.isfile(log_path), "Supervisor output log was not created"
            with open(log_path, "r") as f:
                logged = f.read()
            assert "PROBE_SUPERVISOR_STDOUT" in logged, "Supervisor stdout was not redirected to pipeline.log"
            assert "PROBE_SUPERVISOR_STDERR" in logged, "Supervisor stderr was not redirected to pipeline.log"

            assert os.path.isfile(status_path), "status.txt was not created"
            with open(status_path, "r") as f:
                status = f.read().strip()
            assert status == expected_status, f"For supervisor exit {exit_code}, expected {expected_status}, got {status}"
    finally:
        with open(supervisor_path, "wb") as f:
            f.write(original_supervisor)
        os.chmod(supervisor_path, original_mode)
        if os.path.exists(probe_path):
            os.remove(probe_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
