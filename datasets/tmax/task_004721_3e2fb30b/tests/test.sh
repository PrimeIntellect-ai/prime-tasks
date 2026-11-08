#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess
import tempfile
import time
import pytest

AGENT = "/app/sensor-agent-1.0.0/sensor-agent"
PID_FILE = "/home/user/sensor.pid"
FILTER = "/home/user/filter"
FILTER_SOURCE = "/home/user/filter.c"


def assert_elf(path):
    assert os.path.isfile(path), f"{path} does not exist or is not a regular file."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable."


def assert_recorded_agent_running():
    assert os.path.isfile(PID_FILE), f"PID file {PID_FILE} does not exist."
    with open(PID_FILE, "r") as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"Content of {PID_FILE} is not a valid PID: '{pid_str}'"

    try:
        with open(f"/proc/{pid_str}/comm", "r") as f:
            comm = f.read().strip()
        assert comm == "sensor-agent", (
            f"Process {pid_str} is running but named '{comm}', expected 'sensor-agent'."
        )
        assert os.path.samefile(f"/proc/{pid_str}/exe", AGENT), (
            f"Process {pid_str} is not running the compiled vendored artifact {AGENT}."
        )
    except FileNotFoundError:
        pytest.fail(f"Process with PID {pid_str} (from {PID_FILE}) is not running.")


def test_agent_running():
    """Verify that the compiled vendored sensor-agent is running and recorded."""
    assert_elf(AGENT)
    assert os.access(AGENT, os.X_OK), f"Agent {AGENT} is not executable."
    assert_recorded_agent_running()


def test_vendored_agent_builds_and_runs_from_source():
    """Rebuild an isolated copy so a merely renamed process cannot satisfy the task."""
    source_dir = "/app/sensor-agent-1.0.0"
    assert os.path.isfile(os.path.join(source_dir, "main.c")), "Vendored main.c is missing."
    assert os.path.isfile(os.path.join(source_dir, "Makefile")), "Vendored Makefile is missing."

    with tempfile.TemporaryDirectory() as td:
        build_dir = os.path.join(td, "sensor-agent-src")
        shutil.copytree(source_dir, build_dir)
        built = os.path.join(build_dir, "sensor-agent")
        if os.path.lexists(built):
            if os.path.isdir(built) and not os.path.islink(built):
                shutil.rmtree(built)
            else:
                os.unlink(built)

        res = subprocess.run(
            ["make", "-B", "sensor-agent"], cwd=build_dir,
            capture_output=True, text=True, timeout=30
        )
        assert res.returncode == 0, (
            f"Vendored source does not compile with make.\nstdout:\n{res.stdout}\nstderr:\n{res.stderr}"
        )
        assert_elf(built)
        assert os.access(built, os.X_OK), "Freshly built sensor-agent is not executable."

        proc = subprocess.Popen([built], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            time.sleep(0.4)
            assert proc.poll() is None, "Freshly built sensor-agent did not remain running."
        finally:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=3)


def test_setup_script():
    """Verify repeated setup produces the requested directory state, ACL, and PID."""
    script_path = "/home/user/setup_env.sh"
    assert os.path.isfile(script_path), f"Setup script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Setup script {script_path} is not executable."

    for invocation in range(2):
        res = subprocess.run(["bash", script_path], capture_output=True, text=True, timeout=20)
        assert res.returncode == 0, (
            f"setup_env.sh invocation {invocation + 1} failed with return code "
            f"{res.returncode}.\nStderr: {res.stderr}"
        )

        data_dir = "/home/user/sensor_data"
        assert os.path.isdir(data_dir), f"Data directory {data_dir} was not created."

        st = os.stat(data_dir)
        perms = stat.S_IMODE(st.st_mode) & 0o777
        assert perms == 0o750, f"Permissions of {data_dir} are {oct(perms)}, expected 0o750."

        acl_res = subprocess.run(["getfacl", data_dir], capture_output=True, text=True)
        assert acl_res.returncode == 0, "Failed to run getfacl."
        assert "user:nobody:r-x" in acl_res.stdout, (
            f"ACL for 'nobody' is not 'r-x'. getfacl output:\n{acl_res.stdout}"
        )
        assert_recorded_agent_running()


def run_filter(path, payload):
    res = subprocess.run([path], input=payload, capture_output=True, timeout=10)
    assert res.returncode == 0, (
        f"Filter {path} exited with {res.returncode}; stderr={res.stderr!r}"
    )
    return res.stdout


def test_filter_executable_exists():
    """Verify both the requested C source and compiled executable exist."""
    assert os.path.isfile(FILTER_SOURCE), f"C source {FILTER_SOURCE} does not exist."
    assert_elf(FILTER)
    assert os.access(FILTER, os.X_OK), f"Filter {FILTER} is not executable."


def test_filter_evil_corpus():
    """Preserve the original fixed-corpus rejection assertions."""
    evil_path = "/app/corpus/evil.txt"
    assert os.path.isfile(evil_path), f"Evil corpus {evil_path} is missing."
    with open(evil_path, "r") as f:
        evil_lines = f.readlines()

    bypassed = []
    for i, line in enumerate(evil_lines):
        res = subprocess.run([FILTER], input=line, capture_output=True, text=True, timeout=10)
        if res.stdout != "":
            bypassed.append(f"Line {i+1}: {line.strip()}")
    if bypassed:
        pytest.fail(
            f"{len(bypassed)} of {len(evil_lines)} evil lines bypassed the filter. "
            f"Examples: {bypassed[:5]}"
        )


def test_filter_clean_corpus():
    """Preserve the original fixed-corpus preservation assertions."""
    clean_path = "/app/corpus/clean.txt"
    assert os.path.isfile(clean_path), f"Clean corpus {clean_path} is missing."
    with open(clean_path, "r") as f:
        clean_lines = f.readlines()

    modified = []
    for i, line in enumerate(clean_lines):
        res = subprocess.run([FILTER], input=line, capture_output=True, text=True, timeout=10)
        if res.stdout != line:
            modified.append(f"Line {i+1}: expected {repr(line)}, got {repr(res.stdout)}")
    if modified:
        pytest.fail(
            f"{len(modified)} of {len(clean_lines)} clean lines modified by the filter. "
            f"Examples: {modified[:5]}"
        )


def generated_cases():
    token = os.urandom(24).hex().encode("ascii")
    clean = [
        b"device_" + token + b"=17.25\n",
        b"dots..and/slashes./remain_clean_" + token + b"\n",
        b"spaces and tabs\t" + token + b"\n",
        b"L" * 2048 + b"\n",
        b"final_without_newline_" + token,
    ]
    evil = [
        b"prefix_" + token + b";suffix\n",
        b"prefix_" + token + b"&suffix\n",
        b"prefix_" + token + b"|suffix\n",
        b"prefix_" + token + b"$suffix\n",
        b"prefix_" + token + b"../suffix\n",
        b"A" * 1900 + b"../" + token + b"\n",
        b"B" * 2047 + b";\n",
    ]
    return clean, evil


def assert_general_filter_behavior(path):
    clean, evil = generated_cases()

    for line in clean:
        assert run_filter(path, line) == line, f"Clean generated line was modified by {path}."
    for line in evil:
        assert run_filter(path, line) == b"", f"Restricted generated line bypassed {path}."

    mixed = []
    expected = b""
    for i in range(max(len(clean), len(evil))):
        if i < len(evil):
            mixed.append(evil[i])
        if i < len(clean):
            mixed.append(clean[i])
            expected += clean[i]
    assert run_filter(path, b"".join(mixed)) == expected, (
        f"{path} did not correctly process a multi-line stream."
    )


def test_filter_general_behavior_and_source_build():
    """Exercise unpredictable inputs, long lines, streams, and a fresh source build."""
    assert_general_filter_behavior(FILTER)

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "filter")
        res = subprocess.run(
            ["gcc", FILTER_SOURCE, "-o", rebuilt],
            capture_output=True, text=True, timeout=30
        )
        assert res.returncode == 0, (
            f"{FILTER_SOURCE} does not compile.\nstdout:\n{res.stdout}\nstderr:\n{res.stderr}"
        )
        assert_elf(rebuilt)
        assert_general_filter_behavior(rebuilt)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
