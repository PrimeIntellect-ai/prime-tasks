#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import builtins
import contextlib
import io
import os
import runpy
import shutil
import subprocess
import tempfile
import threading
import time

SCRIPT_DIR = "/home/user/ticket_4092"
PYTHON_SCRIPT = os.path.join(SCRIPT_DIR, "process_jobs.py")
REGRESSION_SCRIPT = os.path.join(SCRIPT_DIR, "regression_test.sh")


def test_regression_script_exists_and_executable():
    assert os.path.isfile(REGRESSION_SCRIPT), f"{REGRESSION_SCRIPT} does not exist."
    assert os.access(REGRESSION_SCRIPT, os.X_OK), f"{REGRESSION_SCRIPT} is not executable."


def test_process_jobs_fixed():
    assert os.path.isfile(PYTHON_SCRIPT), f"{PYTHON_SCRIPT} does not exist."

    for i in range(5):
        result = subprocess.run(
            ["python3", PYTHON_SCRIPT],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"process_jobs.py failed with return code {result.returncode}"
        output = result.stdout.strip()
        assert output == "1000000", f"Run {i+1}: process_jobs.py output '{output}', expected '1000000'. Race condition might not be fully fixed."


def test_output_is_derived_from_counter():
    with open(PYTHON_SCRIPT, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=PYTHON_SCRIPT)

    qualifying_prints = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "print":
            if any(isinstance(child, ast.Name) and child.id == "counter" for arg in node.args for child in ast.walk(arg)):
                qualifying_prints.append(node)
    assert qualifying_prints, "The final tally must be printed from the global counter, not as a hard-coded constant."


def test_main_really_runs_ten_threads():
    real_thread = threading.Thread
    created = []
    started = []
    joined = []

    class RecordingThread(real_thread):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)
            created.append(self)

        def start(self):
            started.append(self)
            return super().start()

        def join(self, *args, **kwargs):
            joined.append(self)
            return super().join(*args, **kwargs)

    threading.Thread = RecordingThread
    try:
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            runpy.run_path(PYTHON_SCRIPT, run_name="__main__")
    finally:
        threading.Thread = real_thread

    assert output.getvalue().strip() == "1000000"
    assert len(created) == 10, f"process_jobs.py must create 10 threads, created {len(created)}"
    assert len(started) == 10, f"process_jobs.py must start 10 threads, started {len(started)}"
    assert len(joined) == 10, f"process_jobs.py must join 10 threads, joined {len(joined)}"


def test_counter_updates_are_synchronized():
    with open(PYTHON_SCRIPT, "r", encoding="utf-8") as f:
        source = f.read()

    real_range = builtins.range

    def shortened_range(*args):
        if args == (100000,):
            return real_range(25)
        return real_range(*args)

    custom_builtins = dict(vars(builtins))
    custom_builtins["range"] = shortened_range
    namespace = {
        "__name__": "verifier_counter_probe",
        "__file__": PYTHON_SCRIPT,
        "__builtins__": custom_builtins,
    }
    exec(compile(source, PYTHON_SCRIPT, "exec"), namespace)
    worker = namespace.get("process_job")
    assert callable(worker), "process_job must remain an executable worker function"

    class ProbeCounter:
        def __init__(self):
            self.value = 0
            self.active = 0
            self.overlap = False
            self.first = True
            self.guard = threading.Lock()

        def __add__(self, amount):
            with self.guard:
                if self.active:
                    self.overlap = True
                self.active += 1
                first = self.first
                self.first = False
            old = self.value
            time.sleep(0.05 if first else 0.0005)
            self.value = old + int(amount)
            with self.guard:
                self.active -= 1
            return self

    probe = ProbeCounter()
    namespace["counter"] = probe
    start_barrier = threading.Barrier(10)

    def invoke_worker():
        start_barrier.wait()
        worker()

    workers = [threading.Thread(target=invoke_worker) for _ in range(10)]
    for thread in workers:
        thread.start()
    for thread in workers:
        thread.join(timeout=10)
        assert not thread.is_alive(), "A worker thread did not finish"

    assert not probe.overlap, "Concurrent counter updates overlapped; the race condition is not protected by a shared synchronization primitive"
    assert probe.value == 250, f"The workers performed an incorrect tally: expected 250 probe increments, got {probe.value}"


def test_regression_script_success_behavior():
    result = subprocess.run([REGRESSION_SCRIPT], capture_output=True, timeout=60)
    assert result.returncode == 0, f"regression_test.sh should exit 0 for a correct process_jobs.py, but exited {result.returncode}."


def test_regression_script_failure_behavior():
    backup_path = PYTHON_SCRIPT + ".bak"
    shutil.copy2(PYTHON_SCRIPT, backup_path)
    try:
        with open(PYTHON_SCRIPT, "w") as f:
            f.write("print(999999)\n")
        result = subprocess.run([REGRESSION_SCRIPT], capture_output=True, timeout=20)
        assert result.returncode == 1, f"regression_test.sh should exit 1 when process_jobs.py outputs wrong values, but exited {result.returncode}."
    finally:
        shutil.move(backup_path, PYTHON_SCRIPT)


def run_regression_with_probe(fail_at):
    backup_path = PYTHON_SCRIPT + ".probe_backup"
    shutil.copy2(PYTHON_SCRIPT, backup_path)
    state_dir = tempfile.mkdtemp(prefix="ticket4092_")
    count_path = os.path.join(state_dir, "count")
    executable_path = os.path.join(state_dir, "executables")
    probe_source = f'''import os, sys
count_path = {count_path!r}
executable_path = {executable_path!r}
try:
    with open(count_path, "r") as f:
        count = int(f.read())
except FileNotFoundError:
    count = 0
count += 1
with open(count_path, "w") as f:
    f.write(str(count))
with open(executable_path, "a") as f:
    f.write(sys.executable + "\\n")
print(999999 if count == {fail_at} else 1000000)
'''
    try:
        with open(PYTHON_SCRIPT, "w", encoding="utf-8") as f:
            f.write(probe_source)
        result = subprocess.run([REGRESSION_SCRIPT], capture_output=True, timeout=20)
        with open(count_path, "r", encoding="utf-8") as f:
            count = int(f.read())
        with open(executable_path, "r", encoding="utf-8") as f:
            executables = [line.strip() for line in f if line.strip()]
        return result, count, executables
    finally:
        shutil.move(backup_path, PYTHON_SCRIPT)
        shutil.rmtree(state_dir, ignore_errors=True)


def test_regression_runs_python_exactly_ten_times_on_success():
    result, count, executables = run_regression_with_probe(0)
    assert result.returncode == 0, f"A ten-run successful regression should exit 0, got {result.returncode}"
    assert count == 10, f"regression_test.sh must execute process_jobs.py exactly 10 times, executed it {count} times"
    assert len(executables) == 10 and all(os.path.basename(path).startswith("python") for path in executables), "Each run must execute process_jobs.py with Python"


def test_regression_exits_immediately_on_each_possible_failure():
    for fail_at in range(1, 11):
        result, count, executables = run_regression_with_probe(fail_at)
        assert result.returncode == 1, f"Failure on run {fail_at} must produce exit status 1, got {result.returncode}"
        assert count == fail_at, f"Failure on run {fail_at} was not immediate: process_jobs.py ran {count} times"
        assert len(executables) == fail_at and all(os.path.basename(path).startswith("python") for path in executables)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
