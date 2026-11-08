#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import subprocess
import tempfile
import time


def read_cpu_fields(pid):
    with open(f"/proc/{pid}/stat", "r") as f:
        stat = f.read().strip()
    # The command name in field 2 may contain spaces, so parse after its final ')'.
    fields = stat[stat.rfind(")") + 2:].split()
    return int(fields[11]), int(fields[12])


def assert_extractor_behavior(executable):
    worker = subprocess.Popen(["python3", "-c", "while True: pass"])
    stopped = False
    try:
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            utime, _ = read_cpu_fields(worker.pid)
            if utime > 0:
                break
            time.sleep(0.02)
        else:
            raise AssertionError("test process did not accumulate CPU time")

        os.kill(worker.pid, signal.SIGSTOP)
        stopped = True
        time.sleep(0.05)
        utime, stime = read_cpu_fields(worker.pid)

        result = subprocess.run(
            [executable, str(worker.pid)], capture_output=True, text=True, timeout=5
        )
        assert result.returncode == 0, result.stderr
        assert result.stdout == (
            f'worker_cpu_utime{{pid="{worker.pid}"}} {utime}\n'
            f'worker_cpu_stime{{pid="{worker.pid}"}} {stime}\n'
        )

        assert subprocess.run([executable], capture_output=True, timeout=5).returncode != 0
        assert subprocess.run(
            [executable, str(worker.pid), "extra"], capture_output=True, timeout=5
        ).returncode != 0
        assert subprocess.run(
            [executable, "99999999"], capture_output=True, timeout=5
        ).returncode != 0
    finally:
        if worker.poll() is None:
            if stopped:
                os.kill(worker.pid, signal.SIGCONT)
            worker.kill()
            worker.wait(timeout=5)


def test_extract_metrics_cpp_exists():
    cpp_file = "/home/user/extract_metrics.cpp"
    assert os.path.exists(cpp_file), f"{cpp_file} does not exist."
    assert os.path.isfile(cpp_file), f"{cpp_file} is not a file."


def test_extract_metrics_binary_exists_and_executable():
    bin_file = "/home/user/extract_metrics"
    assert os.path.exists(bin_file), f"{bin_file} does not exist."
    assert os.path.isfile(bin_file), f"{bin_file} is not a file."
    assert os.access(bin_file, os.X_OK), f"{bin_file} is not executable."
    with open(bin_file, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{bin_file} is not a compiled executable."


def test_run_observability_script_exists_and_executable():
    sh_file = "/home/user/run_observability.sh"
    assert os.path.exists(sh_file), f"{sh_file} does not exist."
    assert os.path.isfile(sh_file), f"{sh_file} is not a file."
    assert os.access(sh_file, os.X_OK), f"{sh_file} is not executable."


def test_node_metrics_prom_format():
    prom_file = "/home/user/node_metrics.prom"
    assert os.path.exists(prom_file), f"{prom_file} does not exist. Did you run your shell script?"

    with open(prom_file, "r") as f:
        content = f.read().strip().split('\n')

    assert len(content) == 2, f"Output in {prom_file} must contain exactly two lines, found {len(content)}."

    match_utime = re.match(r'^worker_cpu_utime\{pid="(\d+)"\} (\d+)$', content[0])
    match_stime = re.match(r'^worker_cpu_stime\{pid="(\d+)"\} (\d+)$', content[1])

    assert match_utime is not None, f"First line format is incorrect. Got: {content[0]}"
    assert match_stime is not None, f"Second line format is incorrect. Got: {content[1]}"
    assert match_utime.group(1) == match_stime.group(1), (
        f"PIDs must match in both lines. Found {match_utime.group(1)} and {match_stime.group(1)}."
    )


def test_source_and_installed_binary_extract_real_proc_values():
    assert_extractor_behavior("/home/user/extract_metrics")

    with tempfile.TemporaryDirectory() as tmp:
        rebuilt = os.path.join(tmp, "extract_metrics")
        result = subprocess.run(
            ["g++", "/home/user/extract_metrics.cpp", "-o", rebuilt],
            capture_output=True, text=True, timeout=30
        )
        assert result.returncode == 0, result.stderr
        assert_extractor_behavior(rebuilt)


def test_lifecycle_script_waits_invokes_extractor_writes_metrics_and_terminates_worker():
    worker_path = "/home/user/worker.sh"
    extractor_path = "/home/user/extract_metrics"
    script_path = "/home/user/run_observability.sh"
    prom_path = "/home/user/node_metrics.prom"
    suffix = str(os.getpid())
    worker_backup = f"/tmp/worker.sh.{suffix}.bak"
    extractor_backup = f"/tmp/extract_metrics.{suffix}.bak"
    trace = f"/tmp/obs_worker_trace.{suffix}"
    term_trace = f"/tmp/obs_worker_term.{suffix}"
    invocation = f"/tmp/obs_extract_call.{suffix}"
    worker_pid = None

    os.rename(worker_path, worker_backup)
    os.rename(extractor_path, extractor_backup)
    try:
        with open(worker_path, "w") as f:
            f.write(f'''#!/bin/bash
exec python3 -c 'import os,signal,time
open("{trace}","w").write(str(os.getpid())+" "+str(time.time_ns()))
def stop(sig, frame):
    open("{term_trace}","w").write("TERM")
    raise SystemExit(0)
signal.signal(signal.SIGTERM, stop)
while True: time.sleep(10)'
''')
        os.chmod(worker_path, 0o755)

        with open(extractor_path, "w") as f:
            f.write(f'''#!/bin/bash
printf '%s\\n' "$#" "$1" "$(date +%s%N)" > "{invocation}"
exec "{extractor_backup}" "$@"
''')
        os.chmod(extractor_path, 0o755)

        if os.path.exists(prom_path):
            os.unlink(prom_path)

        started = time.monotonic()
        proc = subprocess.Popen([script_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

        deadline = time.monotonic() + 3
        while not os.path.exists(trace) and time.monotonic() < deadline:
            time.sleep(0.01)
        assert os.path.exists(trace), "run_observability.sh did not start /home/user/worker.sh"

        with open(trace) as f:
            worker_pid_text, worker_start_ns_text = f.read().split()
        worker_pid = int(worker_pid_text)
        worker_start_ns = int(worker_start_ns_text)
        expected_utime, expected_stime = read_cpu_fields(worker_pid)

        stdout, stderr = proc.communicate(timeout=8)
        elapsed = time.monotonic() - started
        assert proc.returncode == 0, f"script exited {proc.returncode}: {stderr}"
        assert elapsed >= 1.8, f"script did not wait two seconds (elapsed {elapsed:.3f}s)"
        assert elapsed < 5.0, f"script took too long (elapsed {elapsed:.3f}s)"

        assert os.path.exists(invocation), "script did not execute /home/user/extract_metrics"
        with open(invocation) as f:
            argc, called_pid, called_ns = f.read().splitlines()
        assert argc == "1", "extract_metrics was not called with exactly one argument"
        assert called_pid == worker_pid_text, "extract_metrics was not passed the captured worker PID"
        delay = (int(called_ns) - worker_start_ns) / 1_000_000_000
        assert 1.8 <= delay < 4.0, f"extract_metrics was invoked after {delay:.3f}s, not after the required wait"

        with open(prom_path) as f:
            output = f.read()
        assert output == (
            f'worker_cpu_utime{{pid="{worker_pid}"}} {expected_utime}\n'
            f'worker_cpu_stime{{pid="{worker_pid}"}} {expected_stime}\n'
        )

        assert os.path.exists(term_trace), "worker did not receive a graceful SIGTERM"
        deadline = time.monotonic() + 2
        while os.path.exists(f"/proc/{worker_pid}") and time.monotonic() < deadline:
            time.sleep(0.02)
        assert not os.path.exists(f"/proc/{worker_pid}"), "background worker remains running"
    finally:
        if worker_pid is not None and os.path.exists(f"/proc/{worker_pid}"):
            try:
                os.kill(worker_pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        if os.path.exists(worker_path):
            os.unlink(worker_path)
        if os.path.exists(extractor_path):
            os.unlink(extractor_path)
        if os.path.exists(worker_backup):
            os.rename(worker_backup, worker_path)
        if os.path.exists(extractor_backup):
            os.rename(extractor_backup, extractor_path)
        for path in (trace, term_trace, invocation):
            if os.path.exists(path):
                os.unlink(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
