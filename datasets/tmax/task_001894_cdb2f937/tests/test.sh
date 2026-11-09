#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import signal
import stat
import subprocess
import time
from pathlib import Path

MONITOR = "/home/user/scripts/monitor.sh"
SUPERVISOR = "/home/user/scripts/supervisor.sh"
ANALYZE = "/home/user/scripts/analyze.sh"
CSV = Path("/home/user/logs/usage.csv")
SUPERVISOR_LOG = Path("/home/user/logs/supervisor.log")
REPORT = Path("/home/user/report.txt")


def test_directories_and_files_exist():
    expected_files = [
        "/home/user/scripts/monitor.sh",
        "/home/user/scripts/supervisor.sh",
        "/home/user/scripts/analyze.sh",
        "/home/user/logs/usage.csv",
        "/home/user/logs/supervisor.log",
        "/home/user/report.txt",
        "/home/user/workloads/db/init.dat",
        "/home/user/workloads/app/init.dat",
        "/home/user/workloads/db/spike.dat"
    ]
    for f in expected_files:
        assert os.path.isfile(f), f"Expected file {f} does not exist."


def test_crontab_installed():
    try:
        result = subprocess.run(["crontab", "-l"], capture_output=True, text=True, check=True)
        assert "/home/user/scripts/supervisor.sh" in result.stdout, "supervisor.sh not found in crontab."
    except subprocess.CalledProcessError:
        try:
            result = subprocess.run(["crontab", "-u", "user", "-l"], capture_output=True, text=True, check=True)
            assert "/home/user/scripts/supervisor.sh" in result.stdout, "supervisor.sh not found in user's crontab."
        except subprocess.CalledProcessError:
            assert False, "Failed to read crontab or crontab is empty."


def test_report_content():
    report_path = "/home/user/report.txt"
    assert os.path.isfile(report_path), f"{report_path} not found."
    with open(report_path, "r") as f:
        content = f.read()
    assert re.search(r"db_growth_bytes:\s*5242880", content), "db_growth_bytes is not 5242880 in report.txt."
    assert re.search(r"app_growth_bytes:\s*0", content), "app_growth_bytes is not 0 in report.txt."


def test_csv_format():
    csv_path = "/home/user/logs/usage.csv"
    assert os.path.isfile(csv_path), f"{csv_path} not found."
    with open(csv_path, "r") as f:
        lines = f.readlines()
    assert len(lines) > 0, "usage.csv is empty."
    for line in lines:
        line = line.strip()
        if line:
            assert re.match(r"^[0-9]+,(db|app),[0-9]+$", line), f"Invalid CSV format in line: '{line}'"


def test_supervisor_log_format():
    log_path = "/home/user/logs/supervisor.log"
    assert os.path.isfile(log_path), f"{log_path} not found."
    with open(log_path, "r") as f:
        lines = f.readlines()
    assert len(lines) > 0, "supervisor.log is empty."
    for line in lines:
        line = line.strip()
        if line:
            assert re.match(r"^\[[0-9]+\] Restarted monitor daemon$", line), f"Invalid log format in line: '{line}'"


def _read_crontab(args):
    result = subprocess.run(args, capture_output=True, text=True)
    return result.stdout if result.returncode == 0 else ""


def test_file_sizes_executability_and_minute_schedule():
    assert os.path.getsize("/home/user/workloads/db/init.dat") == 1048576
    assert os.path.getsize("/home/user/workloads/app/init.dat") == 2097152
    assert os.path.getsize("/home/user/workloads/db/spike.dat") == 5242880
    for script in (MONITOR, SUPERVISOR, ANALYZE):
        mode = os.stat(script).st_mode
        assert stat.S_ISREG(mode), f"{script} is not a regular file"
        assert mode & 0o111, f"{script} is not executable"

    cron_texts = [_read_crontab(["crontab", "-l"]), _read_crontab(["crontab", "-u", "user", "-l"])]
    minute_line = re.compile(r"^\s*\*\s+\*\s+\*\s+\*\s+\*\s+[^#\n]*?/home/user/scripts/supervisor\.sh(?:\s|$)")
    assert any(any(minute_line.search(line) for line in text.splitlines()) for text in cron_texts), \
        "No every-minute crontab entry runs supervisor.sh"


def _monitor_pids():
    found = set()
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            cmdline = (entry / "cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace")
            if MONITOR in cmdline:
                found.add(int(entry.name))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return found


def _kill_monitors():
    for sig in (signal.SIGTERM, signal.SIGKILL):
        pids = _monitor_pids()
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        time.sleep(0.3)


def _du(path):
    output = subprocess.check_output(["du", "-sb", path], text=True)
    return int(output.split()[0])


def _csv_rows():
    rows = []
    if not CSV.exists():
        return rows
    for raw in CSV.read_text().splitlines():
        match = re.fullmatch(r"([0-9]+),(db|app),([0-9]+)", raw.strip())
        if match:
            rows.append((int(match.group(1)), match.group(2), int(match.group(3))))
    return rows


def _wait_for_pair(db_size, app_size, timeout=5.0, not_before=None):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        grouped = {}
        for timestamp, name, size in _csv_rows():
            if not_before is not None and timestamp < not_before:
                continue
            grouped.setdefault(timestamp, {})[name] = size
        for timestamp, values in grouped.items():
            if values.get("db") == db_size and values.get("app") == app_size:
                return timestamp
        time.sleep(0.1)
    raise AssertionError(f"monitor did not record derived sizes db={db_size}, app={app_size}")


def test_monitor_executes_continuously_and_measures_live_directories():
    _kill_monitors()
    CSV.write_text("")
    probe = Path(f"/home/user/workloads/db/.verifier_probe_{secrets.token_hex(8)}")
    probe_size = 1200000 + secrets.randbelow(600000)
    baseline_db = _du("/home/user/workloads/db")
    baseline_app = _du("/home/user/workloads/app")
    started_epoch = int(time.time())
    proc = subprocess.Popen([MONITOR], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        first_timestamp = _wait_for_pair(baseline_db, baseline_app, timeout=4.5, not_before=started_epoch - 1)
        assert proc.poll() is None, "monitor.sh exited instead of running an infinite loop"

        with open(probe, "wb") as f:
            f.truncate(probe_size)
        changed_db = _du("/home/user/workloads/db")
        changed_app = _du("/home/user/workloads/app")
        assert changed_db != baseline_db
        second_timestamp = _wait_for_pair(changed_db, changed_app, timeout=4.5, not_before=first_timestamp)
        assert second_timestamp - first_timestamp <= 3, "monitor did not sample at approximately one-second intervals"
        assert proc.poll() is None, "monitor.sh stopped after producing data"
    finally:
        try:
            probe.unlink()
        except FileNotFoundError:
            pass
        _kill_monitors()


def test_supervisor_restarts_once_redirects_output_and_avoids_duplicates():
    _kill_monitors()
    SUPERVISOR_LOG.write_text("")
    before_csv_size = CSV.stat().st_size if CSV.exists() else 0
    started = int(time.time())
    result = subprocess.run([SUPERVISOR], capture_output=True, text=True, timeout=5)
    assert result.returncode == 0, result.stderr

    deadline = time.monotonic() + 3
    pids = set()
    while time.monotonic() < deadline:
        pids = _monitor_pids()
        if pids:
            break
        time.sleep(0.1)
    assert pids, "supervisor.sh did not start monitor.sh"

    lines = [line for line in SUPERVISOR_LOG.read_text().splitlines() if line.strip()]
    assert len(lines) == 1, "supervisor must log exactly one restart when starting the monitor"
    match = re.fullmatch(r"\[([0-9]+)\] Restarted monitor daemon", lines[0])
    assert match and started - 1 <= int(match.group(1)) <= int(time.time()) + 1

    redirected = False
    for pid in pids:
        try:
            out_target = os.readlink(f"/proc/{pid}/fd/1")
            err_target = os.readlink(f"/proc/{pid}/fd/2")
            if out_target == "/dev/null" and err_target == "/dev/null":
                redirected = True
        except (FileNotFoundError, PermissionError):
            pass
    assert redirected, "supervisor did not redirect monitor stdout and stderr to /dev/null"

    deadline = time.monotonic() + 3.5
    while time.monotonic() < deadline and (not CSV.exists() or CSV.stat().st_size <= before_csv_size):
        time.sleep(0.1)
    assert CSV.exists() and CSV.stat().st_size > before_csv_size, "supervisor-started monitor produced no CSV data"

    first_pids = _monitor_pids()
    result = subprocess.run([SUPERVISOR], capture_output=True, text=True, timeout=5)
    assert result.returncode == 0, result.stderr
    time.sleep(0.4)
    assert _monitor_pids() == first_pids, "supervisor started a duplicate monitor"
    lines_after = [line for line in SUPERVISOR_LOG.read_text().splitlines() if line.strip()]
    assert lines_after == lines, "supervisor logged a restart even though monitor.sh was already running"
    _kill_monitors()


def test_analyzer_computes_growth_from_runtime_generated_csv():
    _kill_monitors()
    csv_backup = CSV.read_bytes() if CSV.exists() else None
    report_backup = REPORT.read_bytes() if REPORT.exists() else None
    db_min = 100000 + secrets.randbelow(100000)
    db_growth = 200000 + secrets.randbelow(200000)
    app_min = 300000 + secrets.randbelow(100000)
    app_growth = 400000 + secrets.randbelow(200000)
    synthetic = [
        f"101,db,{db_min + db_growth}",
        f"101,app,{app_min}",
        f"102,db,{db_min}",
        f"102,app,{app_min + app_growth}",
        f"103,db,{db_min + db_growth // 2}",
        f"103,app,{app_min + app_growth // 3}",
    ]
    try:
        CSV.write_text("\n".join(synthetic) + "\n")
        try:
            REPORT.unlink()
        except FileNotFoundError:
            pass
        result = subprocess.run([ANALYZE], capture_output=True, text=True, timeout=5)
        assert result.returncode == 0, result.stderr
        assert REPORT.is_file(), "analyze.sh did not create report.txt"
        lines = REPORT.read_text().splitlines()
        assert lines == [f"db_growth_bytes: {db_growth}", f"app_growth_bytes: {app_growth}"], \
            "analyze.sh did not derive max-minus-min growth from usage.csv"
    finally:
        if csv_backup is None:
            try:
                CSV.unlink()
            except FileNotFoundError:
                pass
        else:
            CSV.write_bytes(csv_backup)
        if report_backup is None:
            try:
                REPORT.unlink()
            except FileNotFoundError:
                pass
        else:
            REPORT.write_bytes(report_backup)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
