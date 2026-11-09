#!/bin/bash
set +e
mkdir -p /logs/verifier

ORACLE_PATH=/app/astro_filter
BACKUP_DIR=""
CASES_FILE="$(mktemp /tmp/astro-cases.XXXXXX)"
chmod 600 "$CASES_FILE"

cleanup() {
    if [ -n "$BACKUP_DIR" ] && [ -f "$BACKUP_DIR/astro_filter" ]; then
        mv "$BACKUP_DIR/astro_filter" "$ORACLE_PATH"
        chmod 755 "$ORACLE_PATH"
        rmdir "$BACKUP_DIR" 2>/dev/null || true
    fi
    rm -f "$CASES_FILE" /tmp/test_final_state.py
}
trap cleanup EXIT

run_verification() {
    # Preserve the original oracle assertion and generate the original 100
    # byte-exact expected outputs before making the oracle unavailable.
    python3 - "$CASES_FILE" <<'PY'
import os
import pickle
import random
import struct
import subprocess
import sys

ORACLE_PATH = "/app/astro_filter"
NUM_FUZZ_ROUNDS = 100
out_path = sys.argv[1]

assert os.path.exists(ORACLE_PATH), f"Oracle executable not found at {ORACLE_PATH}"
assert os.path.isfile(ORACLE_PATH), f"Oracle path is not a file: {ORACLE_PATH}"
assert os.access(ORACLE_PATH, os.X_OK), f"Oracle is not executable: {ORACLE_PATH}"

rng = random.Random(42)
cases = []
for i in range(NUM_FUZZ_ROUNDS):
    length = rng.randint(2, 10000)
    floats = [rng.gauss(1e9, 1.0) for _ in range(length)]
    input_data = struct.pack(f"<{length}d", *floats)
    proc = subprocess.run(
        [ORACLE_PATH], input=input_data, capture_output=True,
        check=True, timeout=5
    )
    cases.append((length, input_data, proc.stdout))

with open(out_path, "wb") as f:
    pickle.dump(cases, f, protocol=4)
PY
    [ $? -eq 0 ] || return 1

    # Hide the oracle in a root-only directory while rebuilding and testing.
    # The submitted program and Cargo build run as the unprivileged user.
    BACKUP_DIR="$(mktemp -d /tmp/astro-oracle.XXXXXX)" || return 1
    chmod 700 "$BACKUP_DIR" || return 1
    mv "$ORACLE_PATH" "$BACKUP_DIR/astro_filter" || return 1

    PROJECT=/home/user/astro_fast
    [ -f "$PROJECT/Cargo.toml" ] || return 1
    [ -f "$PROJECT/src/main.rs" ] || return 1

    # Reject a bundled executable oracle in the submitted source tree.
    python3 - "$PROJECT" <<'PY'
import os
import sys

root = sys.argv[1]
for dirpath, dirnames, filenames in os.walk(root):
    rel = os.path.relpath(dirpath, root)
    if rel == ".":
        dirnames[:] = [d for d in dirnames if d not in ("target", ".git")]
    for name in filenames:
        path = os.path.join(dirpath, name)
        try:
            with open(path, "rb") as f:
                magic = f.read(4)
        except OSError:
            continue
        assert magic != b"\x7fELF", f"Bundled ELF executable found in source tree: {path}"
PY
    [ $? -eq 0 ] || return 1

    # Discard any pre-existing target, then compile the submitted Rust project.
    rm -rf "$PROJECT/target" || return 1
    runuser -u user -- env HOME=/home/user CARGO_HOME=/home/user/.cargo \
        cargo build --release --manifest-path "$PROJECT/Cargo.toml" || return 1

    AGENT_PATH="$PROJECT/target/release/astro_fast"
    [ -f "$AGENT_PATH" ] || return 1
    [ -x "$AGENT_PATH" ] || return 1

    # Also reject a direct byte-for-byte copy of the reference executable.
    if cmp -s "$AGENT_PATH" "$BACKUP_DIR/astro_filter"; then
        return 1
    fi

    cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import pickle
import re
import shutil
import struct
import subprocess
import tempfile
import pytest

AGENT_PATH = "/home/user/astro_fast/target/release/astro_fast"
PROJECT_PATH = "/home/user/astro_fast"
CASES_FILE = os.environ["ASTRO_CASES_FILE"]
RUNUSER = shutil.which("runuser") or "/usr/sbin/runuser"


def test_agent_executable_exists():
    assert os.path.exists(AGENT_PATH), f"Agent executable not found at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"Path {AGENT_PATH} is not a file"
    assert os.access(AGENT_PATH, os.X_OK), f"File {AGENT_PATH} is not executable"


def test_rust_project_exists():
    assert os.path.isfile(os.path.join(PROJECT_PATH, "Cargo.toml"))
    assert os.path.isfile(os.path.join(PROJECT_PATH, "src", "main.rs"))


def run_agent(input_data, round_number):
    fd, trace_path = tempfile.mkstemp(prefix="astro-trace-", dir="/tmp")
    os.close(fd)
    try:
        proc = subprocess.run(
            ["strace", "-f", "-qq", "-e", "trace=execve", "-o", trace_path,
             RUNUSER, "-u", "user", "--", AGENT_PATH],
            input=input_data,
            capture_output=True,
            check=True,
            timeout=5,
        )
        with open(trace_path, "r", errors="replace") as f:
            trace = f.read()

        # A Rust implementation should process the stream itself, not execute
        # the oracle, a shell, or another copied helper program.
        exec_paths = re.findall(r'execve\("([^"\\]*(?:\\.[^"\\]*)*)"', trace)
        allowed = {AGENT_PATH, RUNUSER}
        unexpected = [p for p in exec_paths if p not in allowed]
        assert not unexpected, (
            f"Agent delegated execution on round {round_number}: {unexpected}"
        )
        return proc.stdout
    finally:
        try:
            os.unlink(trace_path)
        except FileNotFoundError:
            pass


def test_fuzz_equivalence():
    with open(CASES_FILE, "rb") as f:
        cases = pickle.load(f)

    assert len(cases) == 100
    for i, (length, input_data, oracle_output) in enumerate(cases):
        try:
            agent_output = run_agent(input_data, i + 1)
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent failed on round {i+1} with error: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent timed out on round {i+1}")

        if oracle_output != agent_output:
            try:
                oracle_mean, oracle_var = struct.unpack("<dd", oracle_output)
                agent_mean, agent_var = struct.unpack("<dd", agent_output)
                diff_msg = (
                    f"Mismatch on round {i+1} (input length {length}):\n"
                    f"Oracle output: mean={oracle_mean}, variance={oracle_var} (hex: {oracle_output.hex()})\n"
                    f"Agent output:  mean={agent_mean}, variance={agent_var} (hex: {agent_output.hex()})"
                )
            except Exception:
                diff_msg = (
                    f"Mismatch on round {i+1} (input length {length}):\n"
                    f"Oracle output hex: {oracle_output.hex()}\n"
                    f"Agent output hex:  {agent_output.hex()}"
                )
            pytest.fail(diff_msg)
TEST_EOF

    ASTRO_CASES_FILE="$CASES_FILE" python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
}

if run_verification 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
