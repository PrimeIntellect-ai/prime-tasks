#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shutil
import signal
import subprocess
import tempfile
import time
import pytest

HOME = "/home/user"

def stop_process_group(proc):
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        proc.wait(timeout=1.0)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait(timeout=2.0)


def read_metric_lines(path):
    with open(path) as f:
        lines = f.read().splitlines()
    parsed = []
    for line in lines:
        assert re.fullmatch(r"\d+,\d+,\d+", line), f"Invalid metric line: {line!r}"
        parsed.append(tuple(map(int, line.split(","))))
    return parsed


def test_dummy_worker_sh():
    path = "/home/user/dummy_worker.sh"
    assert os.path.isfile(path), f"{path} does not exist."
    assert os.access(path, os.X_OK), f"{path} is not executable."


def test_monitor_go_and_bin():
    go_file = "/home/user/monitor.go"
    bin_file = "/home/user/monitor"
    assert os.path.isfile(go_file), f"{go_file} does not exist."
    assert os.path.isfile(bin_file), f"{bin_file} does not exist. Did you compile the Go program?"
    assert os.access(bin_file, os.X_OK), f"{bin_file} is not executable."


def test_metrics_log_format():
    log_path = "/home/user/metrics.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist."
    with open(log_path) as f:
        lines = f.read().splitlines()
    assert len(lines) > 0, f"{log_path} is empty."
    for line in lines:
        assert re.match(r"^\d+,\d+,\d+$", line), f"Invalid log format in {log_path}: '{line}'. Expected '<UnixTimestamp>,<PID>,<RSS_KB>'."


def test_restarts_log_format():
    log_path = "/home/user/restarts.log"
    if os.path.isfile(log_path):
        with open(log_path) as f:
            lines = f.read().splitlines()
        for line in lines:
            assert re.match(r"^\d+,RESTART$", line), f"Invalid log format in {log_path}: '{line}'. Expected '<UnixTimestamp>,RESTART'."


def test_analyze_sh():
    path = "/home/user/analyze.sh"
    assert os.path.isfile(path), f"{path} does not exist."
    assert os.access(path, os.X_OK), f"{path} is not executable."


def test_report_txt_format():
    path = "/home/user/report.txt"
    assert os.path.isfile(path), f"{path} does not exist."
    with open(path) as f:
        lines = f.read().splitlines()
    assert len(lines) >= 2, f"{path} should contain exactly two lines."
    assert re.match(r"^Max RSS: \d+ KB$", lines[0]), f"Line 1 format incorrect: {lines[0]}"
    assert re.match(r"^Restarts: \d+$", lines[1]), f"Line 2 format incorrect: {lines[1]}"


def test_analyze_sh_logic():
    files_to_mock = ["metrics.log", "metrics.log.1", "restarts.log", "report.txt"]
    for f in files_to_mock:
        src = f"/home/user/{f}"
        if os.path.exists(src):
            shutil.move(src, f"{src}.bak")
    try:
        with open("/home/user/metrics.log.1", "w") as f:
            f.write("1600000000,1234,5000\n1600000001,1234,16000\n")
        with open("/home/user/metrics.log", "w") as f:
            f.write("1600000002,1235,1000\n1600000003,1235,8000\n")
        with open("/home/user/restarts.log", "w") as f:
            f.write("1600000001,RESTART\n1600000004,RESTART\n")
        result = subprocess.run(["/home/user/analyze.sh"], cwd="/home/user", capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, f"analyze.sh failed with return code {result.returncode}\nStderr: {result.stderr}"
        report_path = "/home/user/report.txt"
        assert os.path.isfile(report_path), f"analyze.sh did not generate {report_path}"
        with open(report_path) as f:
            lines = f.read().splitlines()
        assert len(lines) == 2, f"{report_path} should have exactly 2 lines, got {len(lines)}"
        assert lines[0] == "Max RSS: 16000 KB", f"Expected 'Max RSS: 16000 KB', got '{lines[0]}'"
        assert lines[1] == "Restarts: 2", f"Expected 'Restarts: 2', got '{lines[1]}'"
    finally:
        for f in files_to_mock:
            src = f"/home/user/{f}"
            bak = f"{src}.bak"
            if os.path.exists(src):
                os.remove(src)
            if os.path.exists(bak):
                shutil.move(bak, src)


def test_worker_really_runs_and_grows_in_memory():
    proc = subprocess.Popen([f"{HOME}/dummy_worker.sh"], cwd=HOME, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    samples = []
    try:
        time.sleep(0.5)
        for _ in range(25):
            assert proc.poll() is None, "dummy_worker.sh exited instead of looping"
            status = f"/proc/{proc.pid}/status"
            with open(status) as f:
                match = re.search(r"^VmRSS:\s+(\d+)\s+kB", f.read(), re.MULTILINE)
            assert match, "Could not read worker RSS"
            samples.append(int(match.group(1)))
            time.sleep(0.2)
        assert max(samples) > min(samples), f"Worker RSS did not grow while it ran: {samples}"
    finally:
        stop_process_group(proc)
    assert not os.path.exists(f"/proc/{proc.pid}"), "dummy worker was not terminated"


def test_monitor_source_build_and_runtime_behaviour():
    tracked = ["dummy_worker.sh", "metrics.log", "metrics.log.1", "restarts.log", "report.txt"]
    backup_dir = tempfile.mkdtemp(prefix="monitor-backup-")
    built = "/tmp/monitor_from_submitted_source"
    for name in tracked:
        path = os.path.join(HOME, name)
        if os.path.lexists(path):
            shutil.copy2(path, os.path.join(backup_dir, name))
    try:
        build = subprocess.run(["go", "build", "-o", built, f"{HOME}/monitor.go"], capture_output=True, text=True, timeout=60)
        assert build.returncode == 0, f"monitor.go does not compile:\n{build.stderr}"

        # Execute the requested installed binary for the requested ten seconds.
        for name in ["metrics.log", "metrics.log.1", "restarts.log"]:
            try:
                os.remove(os.path.join(HOME, name))
            except FileNotFoundError:
                pass
        filler = b"X" * 5001
        with open(f"{HOME}/metrics.log", "wb") as f:
            f.write(filler)
        with open(f"{HOME}/metrics.log.1", "wb") as f:
            f.write(b"old backup")
        started = time.monotonic()
        proc = subprocess.Popen([f"{HOME}/monitor"], cwd=HOME, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        try:
            time.sleep(10.0)
        finally:
            stop_process_group(proc)
        elapsed = time.monotonic() - started
        assert 9.8 <= elapsed <= 12.5, f"Monitor test run did not last ten seconds: {elapsed:.2f}s"
        assert open(f"{HOME}/metrics.log.1", "rb").read() == filler, "Rotation did not overwrite metrics.log.1 with the >5000-byte log"
        metrics = read_metric_lines(f"{HOME}/metrics.log")
        assert len(metrics) >= 50, f"Expected roughly 100ms sampling, only got {len(metrics)} samples in ten seconds"
        assert max(t for t, _, _ in metrics) - min(t for t, _, _ in metrics) >= 8, "Telemetry does not span the ten-second run"
        assert all(pid > 1 and rss > 0 for _, pid, rss in metrics)
        for pid in {pid for _, pid, _ in metrics}:
            assert not os.path.exists(f"/proc/{pid}"), f"Worker PID {pid} remained after monitor cleanup"

        # At exactly 5000 bytes the first write must happen before rotation; therefore
        # the rotated file must contain more than the original 5000 bytes.
        low_worker = "#!/bin/bash\nwhile true; do sleep 1; done\n"
        with open(f"{HOME}/dummy_worker.sh", "w") as f:
            f.write(low_worker)
        os.chmod(f"{HOME}/dummy_worker.sh", 0o755)
        for name in ["metrics.log", "metrics.log.1", "restarts.log"]:
            try:
                os.remove(os.path.join(HOME, name))
            except FileNotFoundError:
                pass
        with open(f"{HOME}/metrics.log", "wb") as f:
            f.write(b"Y" * 5000)
        proc = subprocess.Popen([built], cwd=HOME, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        try:
            deadline = time.monotonic() + 2.0
            while time.monotonic() < deadline and not os.path.exists(f"{HOME}/metrics.log.1"):
                time.sleep(0.05)
        finally:
            stop_process_group(proc)
        assert os.path.isfile(f"{HOME}/metrics.log.1"), "Monitor did not rotate a log after it grew beyond 5000 bytes"
        assert os.path.getsize(f"{HOME}/metrics.log.1") > 5000, "Monitor rotated at 5000 bytes instead of strictly greater than 5000 bytes"

        # Force RSS over the threshold and require real kill/restart telemetry.
        hungry_worker = "#!/bin/bash\nexec python3 -c 'x=bytearray(32*1024*1024); import time; time.sleep(60)'\n"
        with open(f"{HOME}/dummy_worker.sh", "w") as f:
            f.write(hungry_worker)
        os.chmod(f"{HOME}/dummy_worker.sh", 0o755)
        for name in ["metrics.log", "metrics.log.1", "restarts.log"]:
            try:
                os.remove(os.path.join(HOME, name))
            except FileNotFoundError:
                pass
        proc = subprocess.Popen([built], cwd=HOME, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        try:
            time.sleep(2.5)
        finally:
            stop_process_group(proc)
        metrics = read_metric_lines(f"{HOME}/metrics.log")
        assert any(rss > 15000 for _, _, rss in metrics), "Monitor did not observe the worker above 15000 KB"
        assert len({pid for _, pid, _ in metrics}) >= 2, "Monitor did not spawn a replacement worker"
        with open(f"{HOME}/restarts.log") as f:
            restart_lines = f.read().splitlines()
        assert restart_lines, "No restart event was recorded"
        assert all(re.fullmatch(r"\d+,RESTART", line) for line in restart_lines)
        for pid in {pid for _, pid, _ in metrics}:
            assert not os.path.exists(f"/proc/{pid}"), f"Worker PID {pid} was left running"
    finally:
        try:
            os.remove(built)
        except FileNotFoundError:
            pass
        for name in tracked:
            path = os.path.join(HOME, name)
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
            saved = os.path.join(backup_dir, name)
            if os.path.exists(saved):
                shutil.copy2(saved, path)
        shutil.rmtree(backup_dir)


def test_analyze_sh_with_derived_random_inputs():
    names = ["metrics.log", "metrics.log.1", "restarts.log", "report.txt"]
    backup_dir = tempfile.mkdtemp(prefix="analyze-backup-")
    for name in names:
        path = os.path.join(HOME, name)
        if os.path.exists(path):
            shutil.copy2(path, os.path.join(backup_dir, name))
    rng = random.SystemRandom()
    try:
        for case in range(4):
            for name in names:
                try:
                    os.remove(os.path.join(HOME, name))
                except FileNotFoundError:
                    pass
            values_a = [rng.randrange(100, 14000) for _ in range(rng.randrange(2, 7))]
            values_b = [rng.randrange(14001, 50000) for _ in range(rng.randrange(1, 5))] if case != 1 else []
            with open(f"{HOME}/metrics.log", "w") as f:
                for i, value in enumerate(values_a):
                    f.write(f"{1800000000+i},{4000+case},{value}\n")
            if values_b:
                with open(f"{HOME}/metrics.log.1", "w") as f:
                    for i, value in enumerate(values_b):
                        f.write(f"{1700000000+i},{3000+case},{value}\n")
            restart_count = rng.randrange(0, 7)
            if case != 2 or restart_count:
                with open(f"{HOME}/restarts.log", "w") as f:
                    for i in range(restart_count):
                        f.write(f"{1750000000+i},RESTART\n")
            result = subprocess.run([f"{HOME}/analyze.sh"], cwd=HOME, capture_output=True, text=True, timeout=10)
            assert result.returncode == 0, result.stderr
            with open(f"{HOME}/report.txt") as f:
                lines = f.read().splitlines()
            expected_max = max(values_a + values_b)
            assert lines == [f"Max RSS: {expected_max} KB", f"Restarts: {restart_count}"], f"Wrong derived report for randomized case: {lines}"
    finally:
        for name in names:
            path = os.path.join(HOME, name)
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
            saved = os.path.join(backup_dir, name)
            if os.path.exists(saved):
                shutil.copy2(saved, path)
        shutil.rmtree(backup_dir)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
