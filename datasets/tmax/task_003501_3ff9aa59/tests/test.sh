#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import resource
import secrets
import subprocess
from contextlib import contextmanager

SCRIPT = "/home/user/datagen.sh"
CONFIG = "/home/user/config.env"
LOG = "/home/user/sequence.log"
SOLUTION = "/home/user/solution.txt"
TARGET_MAX = 9000000000000000000


def _limits():
    os.setsid()
    resource.setrlimit(resource.RLIMIT_CPU, (3, 3))
    resource.setrlimit(resource.RLIMIT_FSIZE, (2 * 1024 * 1024, 2 * 1024 * 1024))


def run_command(command, timeout=5, env=None):
    return subprocess.run(
        command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        env=env,
        preexec_fn=_limits,
    )


def run_datagen():
    env = os.environ.copy()
    env.pop("CONFIG_PATH", None)
    return run_command([SCRIPT], env=env)


@contextmanager
def temporary_config(start, step):
    with open(CONFIG, "rb") as f:
        original = f.read()
    try:
        with open(CONFIG, "w") as f:
            f.write(f"START_VAL={start}\nSTEP_SIZE={step}\n")
        yield
    finally:
        with open(CONFIG, "wb") as f:
            f.write(original)


def expected_sequence(start, step):
    values = []
    current = start
    while current < TARGET_MAX:
        values.append(str(current))
        current += step
    return values


def test_solution_file_content():
    """Verify the fixed answer and that a real clean run produces it."""
    assert os.path.isfile(SOLUTION), f"Solution file {SOLUTION} is missing."
    with open(SOLUTION) as f:
        content = f.read().strip()

    expected_value = "8000000000000001000"
    assert content == expected_value, (
        f"Expected {SOLUTION} to contain exactly '{expected_value}', but got '{content}'."
    )

    if os.path.exists(LOG):
        os.remove(LOG)
    result = run_datagen()
    assert result.returncode == 0, f"datagen.sh failed or was killed: {result.stderr}"
    assert "OVERFLOW_ERROR" not in result.stdout.splitlines(), result.stdout
    assert os.path.isfile(LOG), "datagen.sh did not create sequence.log"

    expected = expected_sequence(1000, 1000000000000000000)
    with open(LOG) as f:
        actual = [line.strip() for line in f if line.strip()]
    assert actual == expected, f"Clean run generated incorrect sequence: {actual}"
    assert actual[-1] == content


def test_datagen_script_modifications():
    """Retain the required script checks and verify the environment repair."""
    assert os.path.isfile(SCRIPT), f"Script file {SCRIPT} is missing."
    assert os.access(SCRIPT, os.X_OK), f"Script file {SCRIPT} is not executable."

    with open(SCRIPT) as f:
        content = f.read()
    assert "OVERFLOW_ERROR" in content, (
        f"The script {SCRIPT} does not contain the required 'OVERFLOW_ERROR' string."
    )
    assert "break" in content, f"The script {SCRIPT} does not contain a 'break' statement to exit the loop."

    env = os.environ.copy()
    env.pop("CONFIG_PATH", None)
    probe = run_command(
        ["bash", "-c", f"unset CONFIG_PATH; source {SCRIPT}; printf '\\n__CONFIG__%s\\n' \"$(printenv CONFIG_PATH)\""],
        env=env,
    )
    assert probe.returncode == 0, f"Could not source repaired script: {probe.stderr}"
    assert "__CONFIG__/home/user/config.env" in probe.stdout, (
        "datagen.sh does not set/export CONFIG_PATH to /home/user/config.env"
    )


def test_script_uses_config_and_handles_real_overflow():
    """Exercise derived inputs so comments or a hardcoded answer cannot pass."""
    start = 1000000 + secrets.randbelow(9000000)
    step = 1000000000000000000 + secrets.randbelow(10000000)
    expected = expected_sequence(start, step)

    with temporary_config(start, step):
        result = run_datagen()
        assert result.returncode == 0, f"Configured run failed: {result.stderr}"
        assert "OVERFLOW_ERROR" not in result.stdout.splitlines(), result.stdout
        with open(LOG) as f:
            actual = [line.strip() for line in f if line.strip()]
        assert actual == expected, "datagen.sh did not process the supplied correct configuration"

    overflow_start = 6000000000000000000 + secrets.randbelow(1000000)
    overflow_step = 6000000000000000000 + secrets.randbelow(1000000)
    with temporary_config(overflow_start, overflow_step):
        result = run_datagen()
        assert result.returncode == 0, f"Overflow run did not terminate cleanly: {result.stderr}"
        lines = result.stdout.splitlines()
        assert lines.count("OVERFLOW_ERROR") == 1, (
            f"Overflow run must print exactly one OVERFLOW_ERROR line; stdout was {result.stdout!r}"
        )
        assert os.path.getsize(LOG) < 1024, "Overflow run continued writing instead of breaking"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
