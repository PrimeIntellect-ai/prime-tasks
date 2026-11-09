#!/bin/bash
set -e
mkdir -p /logs/verifier

ORACLE=/app/legacy_processor
HIDDEN_ORACLE=/root/.legacy_processor_hidden_$$
mv "$ORACLE" "$HIDDEN_ORACLE"
restore_oracle() {
    if [ -e "$HIDDEN_ORACLE" ]; then
        mv "$HIDDEN_ORACLE" "$ORACLE"
    fi
}
trap restore_oracle EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import pwd
import random
import signal
import string
import subprocess
import tempfile
import time

import pandas as pd
import pytest

AGENT_SCRIPT = "/home/user/fast_processor.py"
USER_INFO = pwd.getpwnam("user")


def generate_random_csv(file_path, num_rows, num_sensors, missing_rate, seed):
    rng = random.Random(seed)
    sensors = []
    while len(sensors) < num_sensors:
        name = f"sensor_{''.join(rng.choices(string.ascii_lowercase, k=7))}"
        if name not in sensors:
            sensors.append(name)

    with open(file_path, "w") as f:
        f.write("timestamp," + ",".join(sensors) + "\n")
        timestamp = rng.randint(0, 100000)
        for i in range(num_rows):
            timestamp += rng.randint(1, 10)
            row = [str(timestamp)]
            for _ in sensors:
                if (i == 0 or i == num_rows - 1) and rng.random() < 0.5:
                    row.append("")
                elif rng.random() < missing_rate:
                    row.append("NaN" if rng.random() < 0.2 else "")
                else:
                    row.append(f"{rng.uniform(-1000.0, 1000.0):.6f}")
            f.write(",".join(row) + "\n")


def expected_output(input_csv):
    df = pd.read_csv(input_csv)
    df = df.set_index("timestamp")
    df = df.interpolate(method="index")
    df = df.bfill().ffill()
    df = df.reset_index()
    df = df.melt(id_vars=["timestamp"], var_name="sensor", value_name="value")
    df["value"] = df["value"].round(4)
    df = df.sort_values(by=["timestamp", "sensor"])
    df = df.dropna(subset=["value"])
    out = io.StringIO()
    df.to_csv(out, index=False)
    return out.getvalue()


def process_concurrency(root_pid):
    records = {}
    try:
        proc_entries = os.listdir("/proc")
    except OSError:
        return 0

    for entry in proc_entries:
        if not entry.isdigit():
            continue
        pid = int(entry)
        ppid = None
        threads = 1
        try:
            with open(f"/proc/{pid}/status") as f:
                for line in f:
                    if line.startswith("PPid:"):
                        ppid = int(line.split()[1])
                    elif line.startswith("Threads:"):
                        threads = int(line.split()[1])
            records[pid] = (ppid, threads)
        except (OSError, ValueError):
            pass

    tree = {root_pid}
    changed = True
    while changed:
        changed = False
        for pid, (ppid, _) in records.items():
            if ppid in tree and pid not in tree:
                tree.add(pid)
                changed = True
    return sum(records.get(pid, (None, 1))[1] for pid in tree)


def run_agent(input_csv, output_csv, workers, monitor=False, timeout=120):
    def demote():
        os.setgroups([])
        os.setgid(USER_INFO.pw_gid)
        os.setuid(USER_INFO.pw_uid)

    env = os.environ.copy()
    env["HOME"] = USER_INFO.pw_dir
    cmd = ["python3", AGENT_SCRIPT, input_csv, output_csv, "--workers", str(workers)]
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
        preexec_fn=demote,
        start_new_session=True,
    )
    maximum_concurrency = 1
    deadline = time.monotonic() + timeout
    while proc.poll() is None:
        if monitor:
            maximum_concurrency = max(maximum_concurrency, process_concurrency(proc.pid))
        if time.monotonic() >= deadline:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait()
            pytest.fail(f"Agent timed out with --workers {workers}")
        time.sleep(0.002)

    stdout, stderr = proc.communicate()
    if proc.returncode != 0:
        pytest.fail(
            f"Agent failed with --workers {workers} (exit {proc.returncode}):\n"
            f"stdout:\n{stdout}\nstderr:\n{stderr}"
        )
    assert os.path.isfile(output_csv), "Agent did not produce an output file"
    return maximum_concurrency


def make_shared_tmpdir():
    path = tempfile.mkdtemp()
    os.chmod(path, 0o777)
    return path


def assert_output_matches(path, expected, context):
    with open(path) as f:
        actual = f.read()
    if actual != expected:
        expected_lines = expected.splitlines()
        actual_lines = actual.splitlines()
        first = min(len(expected_lines), len(actual_lines))
        for i, (want, got) in enumerate(zip(expected_lines, actual_lines)):
            if want != got:
                first = i
                break
        want = expected_lines[first] if first < len(expected_lines) else "<EOF>"
        got = actual_lines[first] if first < len(actual_lines) else "<EOF>"
        pytest.fail(
            f"Output mismatch for {context} at line {first + 1}:\n"
            f"Expected: {want}\nAgent:    {got}"
        )


def test_fast_processor_exists():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file"


def test_no_saved_legacy_executable():
    # Catch ordinary and harmlessly modified copies of the legacy wrapper in
    # locations available to the agent. The original is unavailable while tests run.
    signatures = (b"df.interpolate(method='index')", b"df=df.melt(id_vars=['timestamp']")
    roots = ["/home", "/root", "/tmp", "/var/tmp", "/dev/shm", "/usr/local", "/opt"]
    for root in roots:
        if not os.path.isdir(root):
            continue
        for current, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {"proc", "sys", ".cache"}]
            for name in files:
                path = os.path.join(current, name)
                try:
                    if os.path.islink(path) or os.path.getsize(path) > 2_000_000:
                        continue
                    with open(path, "rb") as f:
                        data = f.read()
                except OSError:
                    continue
                if data.startswith(b"\x7fELF") and all(s in data for s in signatures):
                    pytest.fail(f"Saved copy of the legacy executable found at {path}")


@pytest.mark.parametrize("i", range(20))
def test_fuzz_equivalence(i):
    rng = random.Random(42 + i)
    num_rows = rng.randint(100, 10000)
    num_sensors = rng.randint(3, 20)
    missing_rate = rng.uniform(0.05, 0.30)

    with tempfile.TemporaryDirectory() as tmpdir:
        os.chmod(tmpdir, 0o777)
        input_csv = os.path.join(tmpdir, "input.csv")
        agent_out = os.path.join(tmpdir, "agent_out.csv")
        generate_random_csv(input_csv, num_rows, num_sensors, missing_rate, 1000 + i)
        os.chmod(input_csv, 0o644)
        expected = expected_output(input_csv)
        run_agent(input_csv, agent_out, 2)
        assert_output_matches(agent_out, expected, f"fuzz case {i}")


def test_workers_controls_parallel_execution():
    with tempfile.TemporaryDirectory() as tmpdir:
        os.chmod(tmpdir, 0o777)
        input_csv = os.path.join(tmpdir, "parallel_input.csv")
        out_one = os.path.join(tmpdir, "out_one.csv")
        out_three = os.path.join(tmpdir, "out_three.csv")
        generate_random_csv(input_csv, 25000, 12, 0.20, 987654)
        os.chmod(input_csv, 0o644)
        expected = expected_output(input_csv)

        concurrency_one = run_agent(input_csv, out_one, 1, monitor=True)
        concurrency_three = run_agent(input_csv, out_three, 3, monitor=True)
        assert_output_matches(out_one, expected, "--workers 1")
        assert_output_matches(out_three, expected, "--workers 3")

        assert concurrency_three >= concurrency_one + 2, (
            "--workers did not control observable parallel execution: "
            f"workers=1 peak concurrency {concurrency_one}, "
            f"workers=3 peak concurrency {concurrency_three}"
        )
TEST_EOF

status=0
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || status=$?
restore_oracle
trap - EXIT

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
