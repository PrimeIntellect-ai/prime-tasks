#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import stat
import subprocess
import time

import pytest

SCRIPT_PATH = "/home/user/deploy_and_monitor.sh"
METRICS_PATH = "/home/user/metrics.csv"
APP_PATH = "/home/user/app/index.html"
CURL_LOG = "/tmp/verifier_curl.log"


def matching_processes(kind):
    matches = {}
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        pid = int(name)
        try:
            raw = open(f"/proc/{pid}/cmdline", "rb").read()
            cmd = raw.replace(b"\0", b" ").decode(errors="replace").strip()
        except OSError:
            continue
        if kind == "python":
            if re.search(r"(^|\s)python3(?:\s|$).*\s-m\s+http\.server\s+8443(?:\s|$)", cmd):
                matches[pid] = cmd
        elif kind == "socat":
            if re.search(r"(^|/)socat(?:\s|$)", cmd) and "9443" in cmd and "8443" in cmd:
                matches[pid] = cmd
    return matches


def rss_kb(pid):
    try:
        with open(f"/proc/{pid}/status") as f:
            for line in f:
                if line.startswith("VmRSS:"):
                    return int(line.split()[1])
    except OSError:
        pass
    return None


def read_metric_rows():
    try:
        with open(METRICS_PATH) as f:
            lines = [line.strip() for line in f if line.strip()]
    except OSError:
        return []
    rows = []
    for line in lines[1:]:
        if re.fullmatch(r"[0-9]+,[0-9]+,[0-9]+", line):
            rows.append(tuple(map(int, line.split(","))))
    return rows


@pytest.fixture(scope="session", autouse=True)
def run_script():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."

    # Remove stale outputs so they must be produced by this execution.
    for path in (METRICS_PATH, APP_PATH, CURL_LOG):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    # Record curl invocations without changing curl's behavior.
    wrapper_dir = "/tmp/verifier-bin"
    os.makedirs(wrapper_dir, exist_ok=True)
    wrapper = os.path.join(wrapper_dir, "curl")
    with open(wrapper, "w") as f:
        f.write("#!/bin/bash\nprintf '%s\\n' \"$*\" >> /tmp/verifier_curl.log\nexec /usr/bin/curl \"$@\"\n")
    os.chmod(wrapper, 0o755)

    baseline_python = set(matching_processes("python"))
    baseline_socat = set(matching_processes("socat"))
    env = os.environ.copy()
    env["PATH"] = wrapper_dir + ":" + env.get("PATH", "")

    start_mono = time.monotonic()
    start_epoch = int(time.time())
    proc = subprocess.Popen(
        [SCRIPT_PATH], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, env=env, start_new_session=True
    )

    python_pids = set()
    socat_pids = set()
    python_cwds = {}
    rss_samples = {}
    row_first_seen = {}
    forwarding_worked = False
    deadline = start_mono + 15

    try:
        while proc.poll() is None and time.monotonic() < deadline:
            now = time.monotonic()
            py = matching_processes("python")
            so = matching_processes("socat")
            new_py = set(py) - baseline_python
            new_so = set(so) - baseline_socat
            python_pids.update(new_py)
            socat_pids.update(new_so)

            for pid in new_py:
                try:
                    python_cwds[pid] = os.path.realpath(f"/proc/{pid}/cwd")
                except OSError:
                    pass
                value = rss_kb(pid)
                if value is not None:
                    rss_samples.setdefault(pid, []).append((now, value))

            for row in read_metric_rows():
                row_first_seen.setdefault(row, now)

            # Exercise the forwarded endpoint while both required services exist.
            if not forwarding_worked and new_py and new_so:
                try:
                    check = subprocess.run(
                        ["/usr/bin/curl", "-s", "--max-time", "1", "http://localhost:9443/"],
                        capture_output=True, text=True, timeout=2
                    )
                    forwarding_worked = check.returncode == 0 and check.stdout.strip() == "OK"
                except subprocess.TimeoutExpired:
                    pass
            time.sleep(0.02)

        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait(timeout=2)
            pytest.fail("Script did not finish within 15 seconds.")
        stdout, stderr = proc.communicate(timeout=2)
    finally:
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait(timeout=2)

    end_mono = time.monotonic()
    for row in read_metric_rows():
        row_first_seen.setdefault(row, end_mono)

    assert proc.returncode == 0, f"Script failed to execute. stderr: {stderr}"

    state = {
        "start_mono": start_mono,
        "start_epoch": start_epoch,
        "end_mono": end_mono,
        "python_pids": python_pids,
        "socat_pids": socat_pids,
        "python_cwds": python_cwds,
        "rss_samples": rss_samples,
        "row_first_seen": row_first_seen,
        "forwarding_worked": forwarding_worked,
        "stderr": stderr,
    }
    return state


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."


def test_app_file_created():
    assert os.path.isfile(APP_PATH), f"Application file {APP_PATH} was not created."
    with open(APP_PATH) as f:
        assert f.read().strip() == "OK", f"{APP_PATH} does not contain OK."


def test_required_services_and_forwarding(run_script):
    assert run_script["python_pids"], "No running python3 -m http.server 8443 was observed."
    assert run_script["socat_pids"], "No socat forwarding process for ports 9443 and 8443 was observed."
    assert any(cwd == "/home/user/app" for cwd in run_script["python_cwds"].values()), \
        "The Python HTTP server was not observed serving /home/user/app."
    assert run_script["forwarding_worked"], \
        "Requesting port 9443 did not return OK while both services were running."


def test_metrics_file_exists():
    assert os.path.isfile(METRICS_PATH), f"Metrics file {METRICS_PATH} was not created."


def test_metrics_file_content(run_script):
    with open(METRICS_PATH, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 4, f"Expected exactly 4 lines in {METRICS_PATH}, found {len(lines)}."
    assert lines[0] == "TIMESTAMP,PID,RSS_KB", f"Incorrect header in {METRICS_PATH}: {lines[0]}"

    data_pattern = re.compile(r"^[0-9]+,[0-9]+,[0-9]+$")
    rows = []
    for i, line in enumerate(lines[1:], start=1):
        assert data_pattern.match(line), f"Line {i+1} in {METRICS_PATH} does not match expected format: {line}"
        rows.append(tuple(map(int, line.split(","))))

    pids = {row[1] for row in rows}
    assert len(pids) == 1 and next(iter(pids)) in run_script["python_pids"], \
        "Metric PID is not the observed Python HTTP server PID."

    seen_times = [run_script["row_first_seen"].get(row) for row in rows]
    assert all(t is not None for t in seen_times), "Metric rows were not observed being produced by the script."
    assert seen_times[0] - run_script["start_mono"] >= 1.7, \
        "The first metric was written before the required 2-second startup wait."
    assert all(b - a >= 0.7 for a, b in zip(seen_times, seen_times[1:])), \
        "Metric rows were not produced with approximately 1-second intervals."

    for row, seen in zip(rows, seen_times):
        timestamp, pid, reported_rss = row
        observed_epoch = run_script["start_epoch"] + int(seen - run_script["start_mono"])
        assert abs(timestamp - observed_epoch) <= 2, \
            f"Timestamp {timestamp} does not correspond to when its row was written."
        nearby = [rss for sample_time, rss in run_script["rss_samples"].get(pid, []) if abs(sample_time - seen) <= 0.5]
        assert nearby, f"PID {pid} was not live when its metric row was written."
        assert min(abs(reported_rss - rss) for rss in nearby) <= 1024, \
            f"Reported RSS {reported_rss} KB does not match the live server's RSS."


def test_monitoring_curl_requests(run_script):
    calls = []
    if os.path.exists(CURL_LOG):
        with open(CURL_LOG) as f:
            calls = [line for line in f if "localhost:9443/" in line]
    # Default http.server logging provides an independent fallback for scripts
    # that invoke curl by an absolute path rather than through PATH.
    logged_gets = len(re.findall(r'"GET / HTTP/', run_script["stderr"]))
    assert len(calls) >= 3 or logged_gets >= 4, \
        "Three curl requests through localhost:9443 were not observed."


def test_processes_cleaned_up():
    python_check = subprocess.run(["pgrep", "-f", "python3 -m http.server 8443"], capture_output=True, text=True)
    assert python_check.returncode != 0, "python3 http.server process was not cleaned up."

    socat_check = subprocess.run(["pgrep", "-f", "socat.*9443"], capture_output=True, text=True)
    assert socat_check.returncode != 0, "socat process was not cleaned up."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
