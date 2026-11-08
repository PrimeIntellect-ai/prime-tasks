#!/bin/bash
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

ORACLE_HIDDEN="/root/.wal_packer.verifier.$$"
ORACLE_MOVED=0
cleanup() {
    if [ "$ORACLE_MOVED" = "1" ] && [ -e "$ORACLE_HIDDEN" ]; then
        mv "$ORACLE_HIDDEN" /app/wal_packer
    fi
}
trap cleanup EXIT

# Stop any agent-owned helper left running before verification.
pkill -KILL -u user 2>/dev/null || true

if [ ! -f /app/wal_packer ]; then
    exit 0
fi
mv /app/wal_packer "$ORACLE_HIDDEN" || exit 0
chmod 700 "$ORACLE_HIDDEN"
ORACLE_MOVED=1
export ORACLE_HIDDEN

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import re
import subprocess
import tempfile
import pytest

ORACLE_PATH = os.environ["ORACLE_HIDDEN"]
AGENT_SCRIPT = "/home/user/wal_packer.py"
USER_NAME = "user"


def generate_random_binary(size):
    """Generate random data with repeats and 0xAA bytes to exercise RLE."""
    if size == 0:
        return b""

    out = bytearray()
    while len(out) < size:
        choice = random.random()
        if choice < 0.1:
            out.append(0xAA)
        elif choice < 0.3:
            repeat_byte = random.randint(0, 255)
            repeat_count = random.randint(3, 300)
            out.extend([repeat_byte] * repeat_count)
        else:
            out.extend(random.randbytes(min(100, size - len(out))))
    return bytes(out[:size])


def run_oracle(input_file, output_file):
    proc = subprocess.run([ORACLE_PATH, input_file, output_file], capture_output=True)
    assert proc.returncode == 0, "Oracle failed"
    assert os.path.exists(output_file), "Oracle output missing"
    with open(output_file, "rb") as f:
        result = f.read()
    os.unlink(output_file)
    return result


def run_agent_traced(input_file, output_file, trace_file):
    proc = subprocess.run(
        [
            "strace", "-f", "-u", USER_NAME,
            "-e", "trace=execve,execveat,open,openat,rename,renameat,renameat2,link,linkat",
            "-o", trace_file,
            "python3", AGENT_SCRIPT, input_file, output_file,
        ],
        capture_output=True,
        env={**os.environ, "HOME": "/home/user"},
    )
    assert proc.returncode == 0, (
        f"Agent script failed. Stderr: {proc.stderr.decode(errors='replace')}"
    )

    with open(trace_file, "r", errors="replace") as f:
        trace = f.read()

    # The sole successful exec must be the initial Python interpreter. This prevents
    # wrappers from executing a saved or relocated copy of the reference binary.
    successful_execs = [
        line for line in trace.splitlines()
        if re.search(r"\bexecve(?:at)?\(.*\)\s+=\s+0\s*$", line)
    ]
    assert len(successful_execs) == 1, (
        "The Python implementation must not execute another program; "
        f"successful exec calls were: {successful_execs}"
    )
    assert "python3" in successful_execs[0]
    return trace


def test_agent_script_exists():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} does not exist."
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file."
    assert os.path.exists(ORACLE_PATH), f"Oracle binary {ORACLE_PATH} missing."


def test_fuzz_equivalence():
    random.seed(42)
    sizes = [0, 1, 2, 3, 10, 255, 256, 1024, 10000, 50000, 100000]
    sizes += [random.randint(10, 100000) for _ in range(40)]

    with tempfile.TemporaryDirectory() as tmpdir:
        os.chmod(tmpdir, 0o777)
        for i, size in enumerate(sizes):
            input_file = os.path.join(tmpdir, f"input_{i}.wal")
            oracle_out = os.path.join(tmpdir, f"oracle_out_{i}.pack")
            agent_out = os.path.join(tmpdir, f"agent_out_{i}.pack")
            trace_file = os.path.join(tmpdir, f"trace_{i}.log")

            data = generate_random_binary(size)
            with open(input_file, "wb") as f:
                f.write(data)
            os.chmod(input_file, 0o644)

            oracle_data = run_oracle(input_file, oracle_out)
            trace = run_agent_traced(input_file, agent_out, trace_file)

            assert os.path.exists(agent_out), f"Agent output missing for input {i}"
            with open(agent_out, "rb") as f:
                agent_data = f.read()

            if oracle_data != agent_data:
                min_len = min(len(oracle_data), len(agent_data))
                mismatch_idx = next(
                    (j for j in range(min_len) if oracle_data[j] != agent_data[j]),
                    min_len,
                )
                pytest.fail(
                    f"Mismatch on input {i} (size {size}).\n"
                    f"Oracle output length: {len(oracle_data)}\n"
                    f"Agent output length: {len(agent_data)}\n"
                    f"First difference at byte {mismatch_idx}."
                )


def test_atomic_replacement():
    random.seed(8675309)
    data = generate_random_binary(2 * 1024 * 1024)

    with tempfile.TemporaryDirectory() as tmpdir:
        os.chmod(tmpdir, 0o777)
        input_file = os.path.join(tmpdir, "atomic_input.wal")
        oracle_out = os.path.join(tmpdir, "atomic_oracle.pack")
        agent_out = os.path.join(tmpdir, "atomic_agent.pack")
        trace_file = os.path.join(tmpdir, "atomic_trace.log")

        with open(input_file, "wb") as f:
            f.write(data)
        os.chmod(input_file, 0o644)
        expected = run_oracle(input_file, oracle_out)

        # An existing destination ensures the implementation must atomically replace it.
        with open(agent_out, "wb") as f:
            f.write(b"preexisting-backup")
        os.chmod(agent_out, 0o644)

        trace = run_agent_traced(input_file, agent_out, trace_file)
        with open(agent_out, "rb") as f:
            assert f.read() == expected

        quoted_output = re.escape(repr(agent_out))
        lines = trace.splitlines()
        direct_writes = [
            line for line in lines
            if re.search(r"\bopen(?:at)?\(", line)
            and re.search(quoted_output, line)
            and ("O_WRONLY" in line or "O_RDWR" in line)
        ]
        assert not direct_writes, (
            "The final output path was opened for writing instead of being atomically replaced: "
            f"{direct_writes}"
        )

        atomic_installs = [
            line for line in lines
            if re.search(r"\b(?:rename|renameat|renameat2|link|linkat)\(", line)
            and re.search(quoted_output, line)
            and re.search(r"=\s+0\s*$", line)
        ]
        assert atomic_installs, "No successful atomic installation of the final output was observed"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
