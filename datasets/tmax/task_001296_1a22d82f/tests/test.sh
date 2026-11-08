#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'RUNNER_EOF' > /tmp/run_agent.py
import os
import runpy
import sys

BLOCKED_EXACT = {
    "os.system",
    "os.fork",
    "os.forkpty",
    "os.posix_spawn",
    "os.posix_spawnp",
    "subprocess.Popen",
}
BLOCKED_PREFIXES = ("os.exec", "os.spawn", "ctypes.")

def audit(event, args):
    if event in BLOCKED_EXACT or event.startswith(BLOCKED_PREFIXES):
        raise RuntimeError("external/native process execution is forbidden")

sys.addaudithook(audit)
sys.argv = ["/home/user/pipeline.py"]
runpy.run_path("/home/user/pipeline.py", run_name="__main__")
RUNNER_EOF
chmod 755 /tmp/run_agent.py

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import random
import resource
import string
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/app/legacy_processor"
AGENT_SCRIPT = "/home/user/pipeline.py"
RUNNER = "/tmp/run_agent.py"


def generate_random_string(length):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))


def generate_valid_line():
    id_val = ''.join(random.choices(string.ascii_uppercase + string.digits, k=random.randint(3, 5)))
    x_val = f"{random.uniform(0.0, 100.0):.2f}"
    y_val = f"{random.uniform(0.0, 100.0):.2f}"
    parts = [
        f"ID={id_val}",
        f"X={x_val}",
        f"Y={y_val}",
        generate_random_string(random.randint(5, 15)),
        generate_random_string(random.randint(5, 15)),
    ]
    random.shuffle(parts)
    return " ".join(parts) + "\n"


def generate_noise_line():
    return generate_random_string(random.randint(20, 60)) + "\n"


def generate_input_stream():
    num_lines = random.randint(100, 500)
    lines = []
    for _ in range(num_lines):
        if random.random() < 0.7:
            lines.append(generate_valid_line())
        else:
            lines.append(generate_noise_line())
    return "".join(lines)


def run_agent(input_data, timeout=15):
    return subprocess.run(
        ["python3", RUNNER],
        input=input_data,
        text=True,
        capture_output=True,
        check=False,
        timeout=timeout,
    )


def test_artifact_is_python_source():
    assert os.path.exists(ORACLE_PATH), f"Oracle binary missing at {ORACLE_PATH}"
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), "Agent script must be a regular file"

    with open(AGENT_SCRIPT, "rb") as f:
        submitted = f.read()
    with open(ORACLE_PATH, "rb") as f:
        oracle = f.read()

    assert submitted != oracle, "Agent submission must not be the legacy executable"
    assert not submitted.startswith(b"\x7fELF"), "Agent submission is not Python source"
    try:
        source = submitted.decode("utf-8")
        ast.parse(source, filename=AGENT_SCRIPT)
    except (UnicodeDecodeError, SyntaxError) as exc:
        pytest.fail(f"pipeline.py is not valid UTF-8 Python source: {exc}")


def test_known_behavior_without_oracle_answers():
    input_data = (
        "irrelevant noise\n"
        "pre ID=ABC-zzz X=3.00 trailing Y=4.00\n"
        "ID=bad ID=Q9 X=2.50 X=99.00 Y=1.20\n"
        "ID=A1 X=.5 Y=2.00\n"
        "ID=Z X=0.00 Y=0.00\n"
    )
    expected = (
        "ABC,Alpha,17.00\n"
        "ABC,Beta,9.00\n"
        "Q9,Alpha,8.65\n"
        "Q9,Beta,0.50\n"
        "Z,Alpha,0.00\n"
        "Z,Beta,0.00\n"
    )
    proc = run_agent(input_data)
    assert proc.returncode == 0, proc.stderr
    assert proc.stdout == expected


def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle binary missing at {ORACLE_PATH}"
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"

    random.seed(42)
    for i in range(100):
        input_data = generate_input_stream()

        oracle_proc = subprocess.run(
            [ORACLE_PATH],
            input=input_data,
            text=True,
            capture_output=True,
            check=False,
        )
        oracle_out = oracle_proc.stdout

        agent_proc = run_agent(input_data)
        agent_out = agent_proc.stdout

        if agent_proc.returncode != 0 or oracle_out != agent_out:
            pytest.fail(
                f"Output mismatch on iteration {i}.\n\n"
                f"--- Input preview (first 300 chars) ---\n{input_data[:300]}\n...\n\n"
                f"--- Oracle output preview ---\n{oracle_out[:300]}\n...\n\n"
                f"--- Agent output preview ---\n{agent_out[:300]}\n...\n\n"
                f"--- Agent stderr preview ---\n{agent_proc.stderr[:300]}"
            )


def test_large_stream_is_processed_incrementally():
    limit_bytes = 64 * 1024 * 1024
    stream_bytes = 80 * 1024 * 1024

    def apply_limit():
        resource.setrlimit(resource.RLIMIT_AS, (limit_bytes, limit_bytes))

    block = ("noise-only-line\n" * 4096).encode("ascii")
    with tempfile.TemporaryFile() as stream:
        remaining = stream_bytes
        while remaining:
            piece = block[:min(len(block), remaining)]
            stream.write(piece)
            remaining -= len(piece)
        stream.seek(0)

        proc = subprocess.run(
            ["python3", RUNNER],
            stdin=stream,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            check=False,
            timeout=30,
            preexec_fn=apply_limit,
        )

    assert proc.returncode == 0, proc.stderr.decode("utf-8", "replace")[:500]
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
