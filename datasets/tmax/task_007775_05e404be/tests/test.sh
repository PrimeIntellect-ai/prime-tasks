#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess
import tempfile

HOME = "/home/user"
LOG_DIR = "/home/user/container_logs/app_prod"
LOG_FILE = os.path.join(LOG_DIR, "health.log")
SCRIPT = os.path.join(HOME, "run_monitor.sh")
SOURCE = os.path.join(HOME, "uptime_monitor.cpp")
EXECUTABLE = os.path.join(HOME, "uptime_monitor")
FINAL = os.path.join(HOME, "final_uptime.txt")


def expected_output(total, uptime):
    return f"System Uptime: {(uptime / total) * 100.0:.4f}%"


def write_log(directory, total, uptime):
    os.makedirs(directory, exist_ok=True)
    with open(os.path.join(directory, "health.log"), "w") as f:
        f.write(f"TOTAL_TIME {total}\nUPTIME {uptime}\n")


def run_checked(command, **kwargs):
    return subprocess.run(
        command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=True,
        **kwargs,
    )


def test_final_uptime_file_exists():
    """Check if the final output file was created."""
    assert os.path.isfile(FINAL), "The file /home/user/final_uptime.txt does not exist. Did you run the script and redirect its output?"


def test_final_uptime_content():
    """Check if the final output file contains the correct uptime percentage."""
    with open(FINAL, "r") as f:
        content = f.read().strip()
    expected = "System Uptime: 99.9950%"
    assert content == expected, f"Expected the file to contain exactly '{expected}', but got '{content}'. Check your C++ precision logic and environment variables."


def test_uptime_monitor_executable_exists():
    """Check if the C++ program was recompiled."""
    assert os.path.isfile(EXECUTABLE), f"The compiled executable {EXECUTABLE} does not exist. Did you recompile the C++ file?"
    assert os.access(EXECUTABLE, os.X_OK), f"The file {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The uptime_monitor artifact is not a compiled executable."


def test_run_monitor_script_fixed():
    """Verify that the run_monitor.sh script was updated to point to the correct log directory."""
    assert os.path.isfile(SCRIPT), f"File {SCRIPT} is missing."
    with open(SCRIPT, "r") as f:
        content = f.read()
    assert "/home/user/container_logs/app_prod" in content, "The run_monitor.sh script does not appear to point to the correct log directory (/home/user/container_logs/app_prod)."


def test_corrected_source_compiles_and_calculates_dynamic_inputs():
    """Compile the submitted source and verify that it performs floating-point calculation."""
    assert os.path.isfile(SOURCE), "The C++ source file is missing."
    with tempfile.TemporaryDirectory() as tmp:
        rebuilt = os.path.join(tmp, "rebuilt_monitor")
        run_checked(["g++", SOURCE, "-o", rebuilt])
        for total, uptime in ((8, 1), (20000, 12345)):
            case_dir = os.path.join(tmp, f"case_{total}_{uptime}")
            write_log(case_dir, total, uptime)
            env = os.environ.copy()
            env["UPTIME_LOG_DIR"] = case_dir
            result = run_checked([rebuilt], env=env)
            assert result.stdout.strip() == expected_output(total, uptime), (
                f"Recompiled source returned {result.stdout.strip()!r} for "
                f"TOTAL_TIME={total}, UPTIME={uptime}."
            )


def test_installed_program_and_monitor_script_on_dynamic_inputs():
    """Run the requested script with undisclosed-at-build-time log values."""
    with open(LOG_FILE, "rb") as f:
        original_log = f.read()
    try:
        for total, uptime in ((16, 3), (40000, 24691)):
            write_log(LOG_DIR, total, uptime)
            result = run_checked([SCRIPT])
            assert result.stdout.strip() == expected_output(total, uptime), (
                f"run_monitor.sh returned {result.stdout.strip()!r} for "
                f"TOTAL_TIME={total}, UPTIME={uptime}."
            )
    finally:
        with open(LOG_FILE, "wb") as f:
            f.write(original_log)


def test_script_exports_correct_directory_and_invokes_monitor():
    """Ensure the script actually exports the directory and executes uptime_monitor."""
    with tempfile.TemporaryDirectory() as tmp:
        backup = os.path.join(tmp, "uptime_monitor.backup")
        capture = os.path.join(tmp, "captured_env")
        shutil.copy2(EXECUTABLE, backup)
        try:
            with open(EXECUTABLE, "w") as f:
                f.write("#!/bin/bash\nprintf '%s' \"$UPTIME_LOG_DIR\" > " + repr(capture) + "\nprintf 'monitor-invoked\\n'\n")
            os.chmod(EXECUTABLE, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                               stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)
            result = run_checked([SCRIPT])
            assert result.stdout.strip() == "monitor-invoked", "run_monitor.sh did not execute /home/user/uptime_monitor normally."
            assert os.path.isfile(capture), "run_monitor.sh did not invoke /home/user/uptime_monitor."
            with open(capture, "r") as f:
                exported = f.read()
            assert exported == LOG_DIR, f"UPTIME_LOG_DIR was exported as {exported!r}, expected {LOG_DIR!r}."
        finally:
            shutil.copy2(backup, EXECUTABLE)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
