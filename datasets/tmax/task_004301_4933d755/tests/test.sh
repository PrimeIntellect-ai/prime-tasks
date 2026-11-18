#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import tempfile
import pytest

EVIL_CORPUS_DIR = "/home/user/tests/evil_corpus/"
CLEAN_CORPUS_DIR = "/home/user/tests/clean_corpus/"
BINARY_PATH = "/home/user/app/filter_paths"
SOURCE_PATH = "/home/user/app/filter_paths.c"
WATCHER_PATH = "/home/user/app/watcher.sh"


def run_filter_paths(filepath, binary=BINARY_PATH):
    try:
        result = subprocess.run(
            [binary, filepath],
            capture_output=True,
            text=True,
            timeout=2
        )
        return result.stdout.strip()
    except subprocess.TimeoutExpired:
        return "TIMEOUT"
    except Exception as e:
        return f"ERROR: {e}"


def expected_result(contents):
    for line in contents.splitlines():
        if not line:
            continue
        if line.startswith("/") or ".." in line.split("/"):
            return "MALICIOUS"
    return "SAFE"


def test_binary_exists():
    assert os.path.isfile(BINARY_PATH), f"Compiled binary missing at {BINARY_PATH}. Did you run gcc?"
    assert os.access(BINARY_PATH, os.X_OK), f"Binary at {BINARY_PATH} is not executable."
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY_PATH} is not a compiled ELF binary."

    assert os.path.isfile(SOURCE_PATH), f"C source missing at {SOURCE_PATH}."


def test_adversarial_corpus():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Missing evil corpus dir: {EVIL_CORPUS_DIR}"
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Missing clean corpus dir: {CLEAN_CORPUS_DIR}"

    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]

    assert len(evil_files) > 0, "No files found in evil corpus."
    assert len(clean_files) > 0, "No files found in clean corpus."

    bypassed_evil = []
    modified_clean = []

    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, filename)
        output = run_filter_paths(filepath)
        if output != "MALICIOUS":
            bypassed_evil.append((filename, output))

    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, filename)
        output = run_filter_paths(filepath)
        if output != "SAFE":
            modified_clean.append((filename, output))

    error_messages = []
    if bypassed_evil:
        files_list = ", ".join([f"{f} (got {out})" for f, out in bypassed_evil[:5]])
        error_messages.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {files_list}")

    if modified_clean:
        files_list = ", ".join([f"{f} (got {out})" for f, out in modified_clean[:5]])
        error_messages.append(f"{len(modified_clean)} of {len(clean_files)} clean modified (rejected): {files_list}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def test_randomized_hidden_inputs_and_source():
    with tempfile.TemporaryDirectory(prefix="path_filter_check_") as workdir:
        rebuilt = os.path.join(workdir, secrets.token_hex(10))
        build = subprocess.run(
            ["gcc", "-o", rebuilt, SOURCE_PATH],
            capture_output=True,
            text=True,
            timeout=10
        )
        assert build.returncode == 0, f"filter_paths.c does not compile with gcc: {build.stderr}"

        def token():
            return "p" + secrets.token_hex(8)

        cases = ["\n\n"]
        for _ in range(10):
            a, b, c = token(), token(), token()
            cases.extend([
                f"{a}/{b}\n",
                f"./{a}/{b}\n\n{c}\n",
                f"{a}..{b}/{c}\n",
                f".../{a}/.{b}\n",
                f"/{a}/{b}\n",
                f"../{a}\n",
                f"{a}/../{b}\n",
                f"{a}/{b}/..\n",
                f"{a}\n\n/{b}\n{c}\n",
                f"{a}/{b}\n{c}/../{token()}\n"
            ])

        random.SystemRandom().shuffle(cases)
        failures = []
        for contents in cases:
            path = os.path.join(workdir, secrets.token_hex(12) + ".txt")
            with open(path, "w", encoding="utf-8", newline="") as f:
                f.write(contents)
            expected = expected_result(contents)
            installed_output = run_filter_paths(path, BINARY_PATH)
            rebuilt_output = run_filter_paths(path, rebuilt)
            if installed_output != expected or rebuilt_output != expected:
                failures.append((expected, installed_output, rebuilt_output, repr(contents)))

        if failures:
            expected, installed, rebuilt_output, contents = failures[0]
            pytest.fail(
                f"Randomized path-list check failed: expected {expected}, "
                f"installed binary returned {installed}, source rebuild returned {rebuilt_output}, "
                f"input={contents}"
            )


def test_watcher_process_restarted():
    pid_file = "/home/user/app/watcher.pid"
    assert os.path.isfile(pid_file), "watcher.pid is missing."
    with open(pid_file, "r") as f:
        pid_str = f.read().strip()

    assert pid_str.isdigit(), f"Invalid PID in watcher.pid: {pid_str}"
    pid = int(pid_str)

    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f"Watcher process with PID {pid} is not running. Did you restart the watcher.sh script?")

    proc_dir = f"/proc/{pid}"
    assert os.path.isdir(proc_dir), f"Watcher process with PID {pid} disappeared."

    try:
        executable = os.path.realpath(os.path.join(proc_dir, "exe"))
        with open(os.path.join(proc_dir, "cmdline"), "rb") as f:
            argv = [part.decode("utf-8", "surrogateescape") for part in f.read().split(b"\0") if part]
        process_cwd = os.path.realpath(os.path.join(proc_dir, "cwd"))
    except OSError as e:
        pytest.fail(f"Cannot inspect watcher process {pid}: {e}")

    assert os.path.basename(executable) == "bash", (
        f"PID {pid} is not the watcher shell process (executable is {executable})."
    )

    expected_script = os.path.realpath(WATCHER_PATH)
    script_matches = False
    for arg in argv[1:]:
        candidate = arg if os.path.isabs(arg) else os.path.join(process_cwd, arg)
        if os.path.realpath(candidate) == expected_script:
            script_matches = True
            break

    assert script_matches, (
        f"PID {pid} is running, but its command line does not execute {WATCHER_PATH}: {argv}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
