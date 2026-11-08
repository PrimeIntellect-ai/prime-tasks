#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shutil
import signal
import stat
import struct
import subprocess
import tempfile
import time

import pytest

REPORT_PATH = "/home/user/report.json"
WALS_DIR = "/home/user/wals"
TRIGGER_PATH = "/home/user/trigger_db.py"


def test_report_json_exists():
    """Test that the /home/user/report.json file exists."""
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} is missing."


def test_report_json_content():
    """Test that report.json contains the expected original result."""
    try:
        with open(REPORT_PATH, "r") as f:
            report_data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {REPORT_PATH} does not contain valid JSON.")

    assert "active_wal" in report_data, "The JSON report is missing the 'active_wal' key."
    assert "purge_candidates" in report_data, "The JSON report is missing the 'purge_candidates' key."
    assert report_data["active_wal"] == "db_7.wal", (
        f"Expected active_wal to be 'db_7.wal', but got '{report_data['active_wal']}'."
    )

    expected_candidates = ["db_2.wal", "db_6.wal"]
    actual_candidates = report_data["purge_candidates"]
    assert isinstance(actual_candidates, list), "'purge_candidates' must be a JSON array (list)."
    assert sorted(actual_candidates) == expected_candidates, (
        f"Expected purge_candidates to be {expected_candidates}, but got {actual_candidates}."
    )


def trigger_processes():
    result = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                argv = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if TRIGGER_PATH in argv and any("python" in os.path.basename(x) for x in argv):
            result.append(int(entry))
    return result


def test_workload_was_run_and_is_writing():
    pids = trigger_processes()
    assert pids, "No running Python workload process for /home/user/trigger_db.py was found."
    target = os.path.join(WALS_DIR, "db_7.wal")
    before = os.path.getsize(target)
    time.sleep(1.4)
    after = os.path.getsize(target)
    assert after > before, "The workload process is not actively appending to db_7.wal."


def discover_python_scripts():
    scripts = []
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d not in {"wals", "__pycache__"} and not d.startswith(".wals_verifier")]
        for name in files:
            path = os.path.join(root, name)
            if os.path.realpath(path) == os.path.realpath(TRIGGER_PATH) or not os.path.isfile(path):
                continue
            is_python = name.endswith(".py")
            if not is_python:
                try:
                    with open(path, "rb") as f:
                        is_python = b"python" in f.readline(256).lower()
                except OSError:
                    pass
            if is_python:
                scripts.append(path)

    def priority(path):
        try:
            text = open(path, "r", errors="ignore").read()
        except OSError:
            text = ""
        return ("report.json" not in text, path)

    return sorted(set(scripts), key=priority)


def terminate_group(proc):
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        proc.wait(timeout=1)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait(timeout=1)


def write_fixture(names, active, candidates, page_size):
    os.makedirs(WALS_DIR)
    header = struct.pack(">IIIIIIII", 0x377F0682, 3007000, page_size, 0, 0, 0, 0, 0)
    for name in names:
        with open(os.path.join(WALS_DIR, name), "wb") as f:
            f.write(header)
            for frame_no in range(7):
                pgno = 999 if name in candidates and frame_no == 3 else 20 + frame_no
                f.write(struct.pack(">IIIIII", pgno, 0, 0, 0, 0, 0))
                f.write(os.urandom(page_size))


def test_monitor_script_on_derived_fixture_and_mmap_usage():
    scripts = discover_python_scripts()
    assert scripts, "No agent-written Python monitoring script was found under /home/user."

    original_report = open(REPORT_PATH, "rb").read()
    original_trigger = open(TRIGGER_PATH, "rb").read()
    original_trigger_mode = stat.S_IMODE(os.stat(TRIGGER_PATH).st_mode)
    backup_wals = f"/home/user/.wals_verifier_backup_{os.getpid()}"

    rng = random.SystemRandom()
    token = rng.randrange(10000, 99999)
    names = [f"audit_{token}_{i}.wal" for i in range(6)]
    active = rng.choice(names)
    inactive = [name for name in names if name != active]
    candidates = sorted(rng.sample(inactive, 2))
    page_size = rng.choice([1024, 2048, 4096])

    trace_dir = tempfile.mkdtemp(prefix="wal_mmap_trace_")
    marker = os.path.join(trace_dir, "mapped_paths.txt")
    sitecustomize = os.path.join(trace_dir, "sitecustomize.py")
    with open(sitecustomize, "w") as f:
        f.write(
            "import mmap as _mmap, os as _os\n"
            "_real_mmap = _mmap.mmap\n"
            "def _traced_mmap(fd, *args, **kwargs):\n"
            "    try:\n"
            "        p = _os.path.realpath(_os.readlink('/proc/self/fd/%d' % fd))\n"
            "        with open(_os.environ['WAL_MMAP_MARKER'], 'a') as out:\n"
            "            out.write(p + '\\n')\n"
            "    except Exception:\n"
            "        pass\n"
            "    return _real_mmap(fd, *args, **kwargs)\n"
            "_mmap.mmap = _traced_mmap\n"
        )

    workload = None
    os.replace(WALS_DIR, backup_wals)
    try:
        for pid in trigger_processes():
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        time.sleep(0.2)

        passed = False
        failures = []
        for script in scripts:
            if os.path.exists(WALS_DIR):
                shutil.rmtree(WALS_DIR)
            write_fixture(names, active, set(candidates), page_size)
            if os.path.exists(REPORT_PATH):
                os.unlink(REPORT_PATH)
            if os.path.exists(marker):
                os.unlink(marker)

            trigger_source = (
                "import time\n"
                f"target = {os.path.join(WALS_DIR, active)!r}\n"
                "while True:\n"
                "    with open(target, 'ab') as f:\n"
                "        f.write(b'junk')\n"
                "    time.sleep(0.2)\n"
            )
            with open(TRIGGER_PATH, "w") as f:
                f.write(trigger_source)
            os.chmod(TRIGGER_PATH, 0o755)

            workload = subprocess.Popen(
                ["python3", TRIGGER_PATH],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            time.sleep(0.35)

            env = os.environ.copy()
            env["PYTHONPATH"] = trace_dir + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
            env["WAL_MMAP_MARKER"] = marker
            proc = subprocess.Popen(
                ["python3", script],
                cwd="/home/user",
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                start_new_session=True,
            )
            try:
                stdout, stderr = proc.communicate(timeout=15)
            except subprocess.TimeoutExpired:
                terminate_group(proc)
                stdout, stderr = "", "timed out"
            finally:
                try:
                    os.killpg(proc.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass

            terminate_group(workload)
            workload = None

            try:
                with open(REPORT_PATH, "r") as f:
                    result = json.load(f)
            except Exception as exc:
                failures.append(f"{script}: did not create valid report.json ({exc}); {stderr[-300:]}")
                continue

            expected = {"active_wal": active, "purge_candidates": candidates}
            if result != expected:
                failures.append(f"{script}: expected {expected}, got {result}")
                continue

            mapped = set()
            if os.path.exists(marker):
                with open(marker, "r") as f:
                    mapped = {line.strip() for line in f if line.strip()}
            required = {os.path.realpath(os.path.join(WALS_DIR, n)) for n in inactive}
            missing = required - mapped
            if missing:
                failures.append(f"{script}: did not mmap inactive WAL files {sorted(missing)}")
                continue

            passed = True
            break

        assert passed, "No monitoring script passed the derived live-workload test. " + " | ".join(failures)
    finally:
        if workload is not None:
            terminate_group(workload)
        if os.path.exists(WALS_DIR):
            shutil.rmtree(WALS_DIR)
        os.replace(backup_wals, WALS_DIR)
        with open(TRIGGER_PATH, "wb") as f:
            f.write(original_trigger)
        os.chmod(TRIGGER_PATH, original_trigger_mode)
        with open(REPORT_PATH, "wb") as f:
            f.write(original_report)
        shutil.rmtree(trace_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
