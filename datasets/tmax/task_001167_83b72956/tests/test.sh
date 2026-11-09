#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import stat
import subprocess
import tempfile

import pytest

BASE = "/home/user/telemetry_diag"
AGENT = os.path.join(BASE, "agent_fixed")
SOURCE = os.path.join(BASE, "agent.cpp")
SENSOR = os.path.join(BASE, "sensor_dummy")
REPORT = os.path.join(BASE, "diagnostic_report.txt")


def run_program(path):
    env = os.environ.copy()
    env["DIAG_MODE"] = "1"
    result = subprocess.run(
        [path], cwd=BASE, env=env, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, (
        f"{path} exited with status {result.returncode}. stderr:\n"
        f"{result.stderr.decode(errors='replace')}"
    )
    return result.stdout


def parse_rms(output):
    text = output.decode("utf-8", errors="strict")
    match = re.fullmatch(
        r"RMS:\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)\s*",
        text,
    )
    assert match, f"Unexpected program output: {text!r}"
    value = float(match.group(1))
    assert math.isfinite(value), f"RMS must be finite, got {value}"
    return value


def expected_rms(values):
    return math.sqrt(sum(v * v for v in values) / len(values))


@pytest.fixture(scope="session")
def rebuilt_agent():
    assert os.path.isfile(SOURCE), f"File {SOURCE} does not exist."
    fd, output_path = tempfile.mkstemp(prefix="agent_from_source_")
    os.close(fd)
    os.unlink(output_path)
    result = subprocess.run(
        ["g++", "-std=c++17", SOURCE, "-o", output_path],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, (
        "The repaired agent.cpp does not compile:\n"
        + result.stderr.decode(errors="replace")
    )
    yield output_path
    if os.path.exists(output_path):
        os.unlink(output_path)


def test_agent_fixed_exists_and_executable():
    agent_fixed_path = "/home/user/telemetry_diag/agent_fixed"
    assert os.path.isfile(agent_fixed_path), f"File {agent_fixed_path} does not exist. Did you recompile the agent as 'agent_fixed'?"
    assert os.access(agent_fixed_path, os.X_OK), f"File {agent_fixed_path} is not executable."
    with open(agent_fixed_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "agent_fixed must be a compiled ELF executable."


def test_diagnostic_report_exists_and_correct():
    report_path = "/home/user/telemetry_diag/diagnostic_report.txt"
    assert os.path.isfile(report_path), f"File {report_path} does not exist. Did you run the fixed agent and redirect its output?"

    with open(report_path, "r") as f:
        content = f.read()

    assert "RMS:" in content, "The diagnostic report does not contain the 'RMS:' prefix."

    # The expected RMS is approx 50662.277...
    # We check for 50662 to allow for different decimal formatting.
    assert "50662" in content, f"The calculated RMS value is incorrect or missing. Expected a value around 50662, but got:\n{content}"


def test_real_sensor_execution_and_report(rebuilt_agent):
    env = os.environ.copy()
    env["DIAG_MODE"] = "1"
    sensor_result = subprocess.run(
        [SENSOR], cwd=BASE, env=env, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=10, check=True
    )
    values = [int(line) for line in sensor_result.stdout.decode("ascii").splitlines()]
    assert values, "The diagnostic sensor emitted no readings."
    expected = expected_rms(values)

    fixed_output = run_program(AGENT)
    rebuilt_output = run_program(rebuilt_agent)
    assert math.isclose(parse_rms(fixed_output), expected, rel_tol=1e-7, abs_tol=0.01)
    assert math.isclose(parse_rms(rebuilt_output), expected, rel_tol=1e-7, abs_tol=0.01)

    with open(REPORT, "rb") as f:
        report_output = f.read()
    assert report_output == fixed_output, (
        "diagnostic_report.txt is not exactly the current stdout of agent_fixed."
    )


def test_rms_is_computed_without_integer_overflow(rebuilt_agent):
    original_data = open(SENSOR, "rb").read()
    original_mode = stat.S_IMODE(os.stat(SENSOR).st_mode)
    values = [
        random.SystemRandom().randint(46350, 62000),
        random.SystemRandom().randint(70000, 85000),
        random.SystemRandom().randint(90000, 110000),
    ]
    script = "#!/bin/sh\nprintf '%s\\n' " + " ".join(str(v) for v in values) + "\n"

    try:
        with open(SENSOR, "w") as f:
            f.write(script)
        os.chmod(SENSOR, 0o755)

        expected = expected_rms(values)
        for executable in (AGENT, rebuilt_agent):
            actual = parse_rms(run_program(executable))
            assert math.isclose(actual, expected, rel_tol=1e-7, abs_tol=0.01), (
                f"{executable} computed {actual}, expected {expected} for {values}. "
                "The squaring or accumulation still overflows."
            )
    finally:
        with open(SENSOR, "wb") as f:
            f.write(original_data)
        os.chmod(SENSOR, original_mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
