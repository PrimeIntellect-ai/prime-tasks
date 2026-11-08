#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import stat
import subprocess
import tempfile
import uuid

BASE = "/home/user/capacity_planner"
SRC = BASE + "/src/monitor_mock.cpp"
BIN = BASE + "/bin/monitor"
LINK = BASE + "/active/current_monitor"
SCRIPT = BASE + "/health_check.sh"
LOG = BASE + "/logs/critical_alerts.log"
EXPECTED_MONITOR = (
    "frontend_web,45,60\n"
    "backend_api,85,70\n"
    "database_main,90,95\n"
    "cache_node,10,15\n"
    "ml_worker,20,88\n"
)


def run_checked(argv, timeout=20):
    return subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          text=True, timeout=timeout, check=True)


def test_directories_exist():
    """Verify that the required directories have been created."""
    dirs = [
        BASE + "/src",
        BASE + "/bin",
        BASE + "/logs",
        BASE + "/active",
    ]
    for d in dirs:
        assert os.path.isdir(d), f"Directory {d} is missing."


def test_cpp_source_and_binary():
    """Verify that the source compiles and both it and the installed binary behave correctly."""
    assert os.path.isfile(SRC), f"C++ source file {SRC} is missing."
    assert os.path.isfile(BIN), f"Compiled binary {BIN} is missing."
    assert os.access(BIN, os.X_OK), f"Compiled binary {BIN} is not executable."

    with open(BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BIN} is not a compiled ELF binary."

    installed = run_checked([BIN])
    assert installed.stdout == EXPECTED_MONITOR, (
        f"Installed monitor output was {installed.stdout!r}, expected {EXPECTED_MONITOR!r}."
    )

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "monitor_rebuilt")
        compile_result = subprocess.run(
            ["g++", SRC, "-o", rebuilt], stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=30
        )
        assert compile_result.returncode == 0, (
            f"monitor_mock.cpp did not compile: {compile_result.stderr}"
        )
        rebuilt_result = run_checked([rebuilt])
        assert rebuilt_result.stdout == EXPECTED_MONITOR, (
            f"Freshly compiled source output was {rebuilt_result.stdout!r}, "
            f"expected {EXPECTED_MONITOR!r}."
        )


def test_symlink():
    """Verify that the symlink exists and points to the correct binary."""
    assert os.path.islink(LINK), f"{LINK} is not a symlink."
    assert os.readlink(LINK) == BIN, f"Symlink {LINK} does not point to {BIN}."


def test_health_check_script():
    """Verify that the health-check script exists, is executable, and uses a text-processing tool."""
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} is missing."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."
    with open(SCRIPT, "r", errors="replace") as f:
        lines = [line.split("#", 1)[0] for line in f]
    active_text = "\n".join(lines)
    assert re.search(r"\b(?:awk|sed|grep)\b", active_text), (
        "health_check.sh must use awk, sed, or grep to process monitor output."
    )


def test_log_file_content():
    """Verify that the requested initial execution generated the correct alerts."""
    assert os.path.isfile(LOG), f"Log file {LOG} is missing."
    with open(LOG, "r") as f:
        content = f.read().strip().splitlines()
    expected_alerts = ["backend_api", "database_main", "ml_worker"]
    assert content == expected_alerts, (
        f"Log file content does not match expected alerts. Got {content}, "
        f"expected {expected_alerts}."
    )


def test_health_check_executes_symlink_and_filters_fresh_input():
    """Exercise the pipeline with unpredictable service names and derived answers."""
    token = uuid.uuid4().hex
    rows = [
        (f"quiet_{token}", 79, 79),
        (f"cpu_boundary_{token}", 80, 3),
        (f"memory_boundary_{token}", 4, 80),
        (f"cpu_high_{token}", 97, 12),
        (f"memory_high_{token}", 11, 96),
        (f"quiet_two_{token}", 0, 1),
    ]
    expected = [name for name, cpu, mem in rows if cpu >= 80 or mem >= 80]
    original_target = os.readlink(LINK)
    had_log = os.path.isfile(LOG)
    old_log = open(LOG, "rb").read() if had_log else None
    old_mode = stat.S_IMODE(os.stat(LOG).st_mode) if had_log else None

    with tempfile.TemporaryDirectory() as td:
        probe = os.path.join(td, "monitor_probe")
        with open(probe, "w") as f:
            f.write("#!/bin/sh\ncat <<'CSV_EOF'\n")
            for name, cpu, mem in rows:
                f.write(f"{name},{cpu},{mem}\n")
            f.write("CSV_EOF\n")
        os.chmod(probe, 0o755)

        try:
            os.unlink(LINK)
            os.symlink(probe, LINK)
            if os.path.lexists(LOG):
                os.unlink(LOG)

            result = subprocess.run(
                [SCRIPT], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, timeout=20
            )
            assert result.returncode == 0, (
                f"health_check.sh failed on test input: {result.stderr}"
            )
            assert os.path.isfile(LOG), "health_check.sh did not create critical_alerts.log."
            with open(LOG, "r") as f:
                actual = f.read().strip().splitlines()
            assert actual == expected, (
                f"Pipeline produced {actual}, expected {expected} for fresh input."
            )
        finally:
            if os.path.lexists(LINK):
                if os.path.isdir(LINK) and not os.path.islink(LINK):
                    shutil.rmtree(LINK)
                else:
                    os.unlink(LINK)
            os.makedirs(os.path.dirname(LINK), exist_ok=True)
            os.symlink(original_target, LINK)
            if os.path.lexists(LOG):
                if os.path.isdir(LOG) and not os.path.islink(LOG):
                    shutil.rmtree(LOG)
                else:
                    os.unlink(LOG)
            if had_log:
                with open(LOG, "wb") as f:
                    f.write(old_log)
                os.chmod(LOG, old_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
