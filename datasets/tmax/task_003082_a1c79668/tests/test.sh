#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import random
import string
import tempfile
import pytest

ORACLE_PATH = "/app/bin/query_formatter"
AGENT_PATH = "/home/user/formatter.sh"


def generate_random_input(seed):
    random.seed(seed)
    num_lines = random.randint(1, 10)
    lines = []
    for _ in range(num_lines):
        num_fields = random.randint(2, 6)
        fields = []
        for _ in range(num_fields):
            field_len = random.randint(1, 15)
            field = ''.join(random.choices(string.ascii_letters + string.digits, k=field_len))
            fields.append(field)
        lines.append("|".join(fields))
    return ("\n".join(lines) + "\n").encode("ascii")


def expected_output(data):
    # Independently model the documented black-box behavior; do not execute the
    # agent-visible oracle during verification.
    pieces = data.split(b"\n")
    line_count = len(pieces) - 1 if data.endswith(b"\n") else len(pieces)
    output = bytearray()

    for line in pieces[:line_count]:
        fields = line.split(b"|")
        last = fields[-1]
        fields[-1] = bytes(
            value - 32 if ord("a") <= value <= ord("z") else value
            for value in last
        )
        output.extend(b"|".join(reversed(fields)))
        output.extend(b"\n")

    return bytes(output)


def run_agent(input_data):
    trace_fd, trace_path = tempfile.mkstemp(prefix="formatter-exec-", suffix=".trace")
    os.close(trace_fd)
    try:
        try:
            proc = subprocess.run(
                [
                    "/usr/bin/strace",
                    "-f",
                    "-qq",
                    "-e",
                    "trace=execve",
                    "-o",
                    trace_path,
                    AGENT_PATH,
                ],
                input=input_data,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
            )
        except subprocess.TimeoutExpired:
            pytest.fail("Agent script timed out")

        assert proc.returncode == 0, (
            f"Agent script failed with return code {proc.returncode}\n"
            f"Stderr: {proc.stderr.decode('utf-8', errors='replace')}"
        )

        with open(trace_path, "r", encoding="utf-8", errors="replace") as trace_file:
            exec_calls = [line for line in trace_file if "execve(" in line]

        # The first execve starts formatter.sh. A pure Bash implementation needs
        # no further executable; this rejects wrappers around the oracle, copied
        # binaries, Python implementations, and other delegated implementations.
        assert len(exec_calls) == 1, (
            "formatter.sh executed an external program and is not a pure Bash "
            f"implementation. Exec trace:\n{''.join(exec_calls)}"
        )
        return proc.stdout
    finally:
        try:
            os.unlink(trace_path)
        except FileNotFoundError:
            pass


def test_agent_script_exists_and_executable():
    assert os.path.exists(AGENT_PATH), f"Agent script not found at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"{AGENT_PATH} is not a file"
    assert stat.S_ISREG(os.lstat(AGENT_PATH).st_mode), f"{AGENT_PATH} must be a regular file"
    assert os.access(AGENT_PATH, os.X_OK), f"{AGENT_PATH} is not executable"

    with open(AGENT_PATH, "rb") as script:
        assert script.readline().rstrip(b"\n") == b"#!/bin/bash", (
            "formatter.sh must start with #!/bin/bash"
        )

    syntax = subprocess.run(
        ["/bin/bash", "-n", AGENT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert syntax.returncode == 0, syntax.stderr.decode("utf-8", errors="replace")


def test_oracle_remains_available_for_reverse_engineering():
    assert os.path.exists(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle not executable at {ORACLE_PATH}"


def test_fuzz_equivalence():
    cases = [generate_random_input(42 + i) for i in range(100)]

    # Add verification-time randomized cases so a submission cannot special-case
    # the original public seeds.
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    alphabet = string.ascii_letters + string.digits + " _-.,:;!?/@#$%^&*()[]{}"
    for _ in range(40):
        lines = []
        for _ in range(rng.randint(1, 10)):
            fields = []
            for _ in range(rng.randint(1, 8)):
                fields.append("".join(rng.choice(alphabet) for _ in range(rng.randint(0, 25))))
            lines.append("|".join(fields))
        payload = "\n".join(lines)
        if rng.choice((True, False)):
            payload += "\n"
        cases.append(payload.encode("ascii"))

    cases.extend([
        b"",
        b"\n",
        b"a\n\nB|c\n",
        b"a|b",
        b"|\n",
        b"a||c\n",
        b"left|MiXeD value!\r\n",
        b"one|two|three|four\n",
        b"abc|xyz\n" * 50,
    ])

    for index, input_data in enumerate(cases, 1):
        expected = expected_output(input_data)
        actual = run_agent(input_data)
        assert actual == expected, (
            f"Output mismatch on run {index}!\n"
            f"Input bytes: {input_data!r}\n"
            f"Expected bytes: {expected!r}\n"
            f"Got bytes: {actual!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
