#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import secrets
import signal
import subprocess

PROJECT = "/home/user/project"
RESOLVER = os.path.join(PROJECT, "scripts/resolve_deps.sh")
BUILD = os.path.join(PROJECT, "build.sh")
DEPS = os.path.join(PROJECT, "deps.txt")
RESOLVED = os.path.join(PROJECT, "resolved.txt")
VISITED = os.path.join(PROJECT, "visited.txt")


def run_command(command, timeout=5):
    proc = subprocess.Popen(
        command,
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        stdout, stderr = proc.communicate()
        raise AssertionError(f"Command timed out: {' '.join(command)}\nstdout: {stdout}\nstderr: {stderr}")
    assert proc.returncode == 0, (
        f"Command failed with status {proc.returncode}: {' '.join(command)}\n"
        f"stdout: {stdout}\nstderr: {stderr}"
    )


def read_resolved():
    assert os.path.isfile(RESOLVED), f"{RESOLVED} was not generated"
    with open(RESOLVED, "r") as f:
        return [line.strip() for line in f if line.strip()]


def clear_resolver_state():
    for path in (RESOLVED, VISITED):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def assert_unique_result(expected):
    lines = read_resolved()
    assert len(lines) == len(set(lines)), "resolved.txt contains duplicate entries. Dependencies should only be processed once."
    assert set(lines) == set(expected), f"Expected resolved dependencies {set(expected)}, got {set(lines)}"


def test_00_resolver_and_build_handle_an_unseen_cycle():
    assert os.path.isfile(RESOLVER), f"{RESOLVER} does not exist"
    assert os.access(RESOLVER, os.X_OK), f"{RESOLVER} is not executable"
    assert os.path.isfile(BUILD) and os.access(BUILD, os.X_OK), f"{BUILD} is not executable"

    # First ensure build.sh really regenerates the result for the supplied graph.
    run_command([BUILD])
    assert_unique_result({"core", "utils", "math", "graphics", "ui", "network_base", "crypto", "network", "app"})

    with open(DEPS, "rb") as f:
        original_deps = f.read()

    suffix = secrets.token_hex(8)
    a, b, c, d = [f"node_{name}_{suffix}" for name in ("a", "b", "c", "d")]
    dynamic_graph = (
        f"app:{a} {b}\n"
        f"{a}:{c}\n"
        f"{b}:{c} {d}\n"
        f"{c}:app\n"
        f"{d}:\n"
    )
    expected = {"app", a, b, c, d}

    try:
        with open(DEPS, "w") as f:
            f.write(dynamic_graph)

        # Exercise resolve_deps.sh itself so a prewritten resolved.txt or a
        # replacement build.sh cannot hide an unfixed recursive resolver.
        clear_resolver_state()
        run_command([RESOLVER, "app"])
        assert_unique_result(expected)

        # Also verify that the requested build entry point regenerates it.
        clear_resolver_state()
        run_command([BUILD])
        assert_unique_result(expected)
    finally:
        with open(DEPS, "wb") as f:
            f.write(original_deps)
        clear_resolver_state()
        run_command([BUILD])


def test_resolved_dependencies():
    resolved_path = "/home/user/project/resolved.txt"
    assert os.path.isfile(resolved_path), f"{resolved_path} does not exist. Did you run build.sh?"

    with open(resolved_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_deps = {"core", "utils", "math", "graphics", "ui", "network_base", "crypto", "network", "app"}
    actual_deps_set = set(lines)

    assert len(lines) == len(actual_deps_set), "resolved.txt contains duplicate entries. Dependencies should only be processed once."
    assert actual_deps_set == expected_deps, f"resolved.txt does not contain the correct set of dependencies. Expected {expected_deps}, got {actual_deps_set}"


def test_anomaly_investigation():
    anomaly_path = "/home/user/anomaly.txt"
    assert os.path.isfile(anomaly_path), f"{anomaly_path} does not exist."

    with open(anomaly_path, "r") as f:
        content = f.read().strip()

    # Retain the original fixture assertion.
    assert content == "lib_heavy_crypto", f"anomaly.txt contains incorrect dependency name. Expected 'lib_heavy_crypto', got '{content}'"

    download_log = "/home/user/project/logs/download.log"
    assert os.path.isfile(download_log), f"Required source log {download_log} is missing"
    slow = []
    pattern = re.compile(r"^\[[^]]+\]\s+Downloaded\s+(\S+)\s+in\s+(\d+)ms$")
    with open(download_log, "r") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line:
                continue
            match = pattern.match(line)
            assert match, f"Malformed download log line: {line}"
            if int(match.group(2)) > 5000:
                slow.append(match.group(1))

    assert len(slow) == 1, f"Expected exactly one download over 5000ms, found {slow}"
    assert content == slow[0], f"anomaly.txt should name {slow[0]}, got {content}"


def test_log_timeline_reconstruction():
    timeline_path = "/home/user/timeline.txt"
    assert os.path.isfile(timeline_path), f"{timeline_path} does not exist."

    with open(timeline_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    log_dir = "/home/user/project/logs"
    required = {"worker1.log", "worker2.log", "download.log"}
    log_files = sorted(glob.glob(os.path.join(log_dir, "*.log")))
    discovered = {os.path.basename(path) for path in log_files}
    assert required <= discovered, f"Required source logs are missing: {required - discovered}"

    expected_lines = []
    timestamp_pattern = re.compile(r"^\[(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\]")
    for file_path in log_files:
        with open(file_path, "r") as f:
            for raw_line in f:
                line = raw_line.strip()
                if not line:
                    continue
                assert timestamp_pattern.match(line), f"Malformed timestamp in {file_path}: {line}"
                expected_lines.append(line)

    expected_lines.sort(key=lambda line: timestamp_pattern.match(line).group(1))

    assert len(actual_lines) == len(expected_lines), f"timeline.txt does not contain the correct number of lines. Expected {len(expected_lines)}, got {len(actual_lines)}"
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Mismatch at line {i+1} in timeline.txt. Expected '{expected}', got '{actual}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
