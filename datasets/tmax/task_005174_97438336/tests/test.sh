#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import signal
import stat
import subprocess
import tempfile
import time
from decimal import Decimal

PIPELINE_DIR = "/home/user/pipeline"
RESULT_FILE = os.path.join(PIPELINE_DIR, "result.txt")
SCRIPT_FILE = os.path.join(PIPELINE_DIR, "aggregate_metrics.sh")
DATA_FILE = os.path.join(PIPELINE_DIR, "data.csv")
PARSER_FILE = os.path.join(PIPELINE_DIR, "metric_parser")
LIBRARY_FILE = os.path.join(PIPELINE_DIR, "libcustom_math.so")


def test_result_file_correct():
    """Verify that the result file contains the correct average with exactly 4 decimal places."""
    assert os.path.isfile(RESULT_FILE), f"Result file {RESULT_FILE} is missing. Did you run the script?"
    with open(RESULT_FILE, "r") as f:
        content = f.read().strip()

    assert content == "30.5454", f"Expected average '30.5454', but got '{content}'. Check your precision and loop logic."


def test_script_is_runnable_bash_script():
    assert os.path.isfile(SCRIPT_FILE), f"Missing script: {SCRIPT_FILE}"
    assert os.access(SCRIPT_FILE, os.X_OK), f"Script is not executable: {SCRIPT_FILE}"
    with open(SCRIPT_FILE, "rb") as f:
        first_line = f.readline().decode("utf-8", errors="replace")
    assert first_line.startswith("#!") and "bash" in first_line, "aggregate_metrics.sh must be a Bash script."


def test_script_fixes_shared_library():
    """Verify that the script fixes the shared library issue."""
    with open(SCRIPT_FILE, "r") as f:
        script_content = f.read()

    has_ld_path = "LD_LIBRARY_PATH" in script_content
    has_ldconfig = "ldconfig" in script_content
    has_patchelf = "patchelf" in script_content
    has_cd = "cd " in script_content and "./metric_parser" in script_content

    assert has_ld_path or has_ldconfig or has_patchelf, "Could not find LD_LIBRARY_PATH or similar fix for the shared library in the script."


def test_pipeline_executes_parser_and_computes_unseen_dataset():
    """Run the submitted pipeline on verifier-generated data and observe library loading."""
    assert os.path.isfile(PARSER_FILE), "metric_parser is missing."
    assert os.path.isfile(LIBRARY_FILE), "libcustom_math.so is missing."

    original_data = open(DATA_FILE, "rb").read()
    original_result = open(RESULT_FILE, "rb").read() if os.path.exists(RESULT_FILE) else None
    original_library = open(LIBRARY_FILE, "rb").read()
    library_mode = stat.S_IMODE(os.stat(LIBRARY_FILE).st_mode)

    work = tempfile.mkdtemp(prefix="pipeline_verify_")
    marker = os.path.join(work, "library_loaded")
    shim_dir = os.path.join(work, "bin")
    os.mkdir(shim_dir)

    try:
        # Keep completion tests quick without changing the submitted script.
        sleep_shim = os.path.join(shim_dir, "sleep")
        with open(sleep_shim, "w") as f:
            f.write("#!/bin/sh\nexec /bin/sleep 0.05\n")
        os.chmod(sleep_shim, 0o755)

        # Replace the library temporarily with an ABI-compatible instrumented build.
        # Its constructor proves that metric_parser was actually executed and linked.
        source = os.path.join(work, "custom_math_probe.c")
        escaped_marker = marker.replace("\\", "\\\\").replace('"', '\\"')
        with open(source, "w") as f:
            f.write(
                "#include <stdio.h>\n"
                "__attribute__((constructor)) static void loaded(void) {\n"
                f"  FILE *fp = fopen(\"{escaped_marker}\", \"a\");\n"
                "  if (fp) { fputs(\"loaded\\n\", fp); fclose(fp); }\n"
                "}\n"
                "double add(double a, double b) { return a + b; }\n"
            )
        probe_library = os.path.join(work, "libcustom_math.so")
        subprocess.run(["gcc", "-shared", "-fPIC", "-o", probe_library, source], check=True)
        shutil.copyfile(probe_library, LIBRARY_FILE)
        os.chmod(LIBRARY_FILE, library_mode)

        # Generate values at verification time. Adjust the final value so the exact
        # average has four decimal places and requires no ambiguous tie rounding.
        units = [secrets.randbelow(800000) + 10000 for _ in range(5)]
        units[-1] += (-sum(units)) % len(units)
        expected = Decimal(sum(units)) / Decimal(len(units) * 10000)
        expected_text = f"{expected:.4f}"

        with open(DATA_FILE, "w") as f:
            f.write("id,value\n")
            for index, value in enumerate(units, 1):
                f.write(f"{index},{value / 10000:.4f}\n")

        if os.path.exists(RESULT_FILE):
            os.remove(RESULT_FILE)

        env = os.environ.copy()
        env.pop("LD_LIBRARY_PATH", None)
        env["PATH"] = shim_dir + os.pathsep + env.get("PATH", "")
        completed = subprocess.run(
            [SCRIPT_FILE],
            cwd=PIPELINE_DIR,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )

        assert completed.returncode == 0, (
            f"Pipeline failed with exit code {completed.returncode}. stderr: {completed.stderr}"
        )
        assert os.path.isfile(marker), "The pipeline did not execute and dynamically link metric_parser."
        assert os.path.isfile(RESULT_FILE), "The executed pipeline did not create result.txt."
        with open(RESULT_FILE, "r") as f:
            actual = f.read().strip()
        assert re.fullmatch(r"-?\d+\.\d{4}", actual), f"Result is not formatted with exactly four decimal places: {actual!r}"
        assert actual == expected_text, f"Expected verifier-derived average {expected_text}, got {actual}."
    finally:
        with open(DATA_FILE, "wb") as f:
            f.write(original_data)
        with open(LIBRARY_FILE, "wb") as f:
            f.write(original_library)
        os.chmod(LIBRARY_FILE, library_mode)
        if original_result is None:
            if os.path.exists(RESULT_FILE):
                os.remove(RESULT_FILE)
        else:
            with open(RESULT_FILE, "wb") as f:
                f.write(original_result)
        shutil.rmtree(work, ignore_errors=True)


def _process_table():
    output = subprocess.check_output(["ps", "-eo", "pid=,ppid=,args="], text=True)
    rows = []
    for line in output.splitlines():
        parts = line.strip().split(None, 2)
        if len(parts) == 3:
            rows.append((int(parts[0]), int(parts[1]), parts[2]))
    return rows


def _descendants(root_pid):
    rows = _process_table()
    by_parent = {}
    for pid, ppid, command in rows:
        by_parent.setdefault(ppid, []).append((pid, command))
    found = []
    pending = [root_pid]
    while pending:
        parent = pending.pop()
        for pid, command in by_parent.get(parent, []):
            found.append((pid, command))
            pending.append(pid)
    return found


def _assert_signal_cleanup(sig):
    process = subprocess.Popen(
        ["bash", SCRIPT_FILE],
        cwd=PIPELINE_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        preexec_fn=os.setsid,
    )
    captured_sleep_pids = []
    try:
        deadline = time.time() + 3
        descendants = []
        while time.time() < deadline:
            descendants = _descendants(process.pid)
            sleeps = [
                (pid, command) for pid, command in descendants
                if re.search(r"(?:^|/)sleep 100$", command.strip())
            ]
            if len(sleeps) >= 2:
                captured_sleep_pids = [pid for pid, _ in sleeps]
                break
            if process.poll() is not None:
                break
            time.sleep(0.1)

        assert len(captured_sleep_pids) >= 2, "The pipeline did not spawn its two long-running background sleep tasks."

        pgid = os.getpgid(process.pid)
        os.kill(process.pid, sig)
        process.wait(timeout=5)
        time.sleep(0.3)

        remaining = {pid: command for pid, _, command in _process_table()}
        leaked_captured = [
            pid for pid in captured_sleep_pids
            if pid in remaining and re.search(r"(?:^|/)sleep 100$", remaining[pid].strip())
        ]
        assert not leaked_captured, f"Background child processes survived signal {sig}: {leaked_captured}"

        ps_output = subprocess.check_output(["ps", "-eo", "pid,ppid,cmd"]).decode("utf-8")
        leaked_sleeps = []
        for line in ps_output.splitlines():
            if "sleep 100" in line and "grep" not in line:
                parts = line.split()
                if len(parts) >= 3:
                    leaked_sleeps.append(line)
        assert len(leaked_sleeps) == 0, "Found leaked 'sleep 100' processes after sending a signal to the script."
    finally:
        if process.poll() is None:
            try:
                os.killpg(os.getpgid(process.pid), signal.SIGKILL)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                pass
        for pid in captured_sleep_pids:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def test_script_trap_and_cleanup():
    """Verify that the script properly traps signals and cleans up background processes."""
    with open(SCRIPT_FILE, "r") as f:
        script_content = f.read()

    assert "trap" in script_content, "No 'trap' command found in the script."
    assert "kill" in script_content, "No 'kill' command found in the script to terminate background processes."

    _assert_signal_cleanup(signal.SIGTERM)
    _assert_signal_cleanup(signal.SIGINT)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
