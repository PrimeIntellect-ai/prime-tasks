#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import secrets
import subprocess
import tempfile

RUNNER_PATH = "/home/user/ci_runner.sh"
PB_PATH = "/home/user/project/main.pb"
ENV_FILE = "/home/user/build_env.sh"
LOG_FILE = "/home/user/build_output.log"


def test_runner_exists_and_executable():
    assert os.path.isfile(RUNNER_PATH), f"Script {RUNNER_PATH} does not exist."
    assert os.access(RUNNER_PATH, os.X_OK), f"Script {RUNNER_PATH} is not executable."


def test_runner_success_path():
    assert os.path.isfile(PB_PATH), f"Test setup file {PB_PATH} is missing."

    result = subprocess.run([RUNNER_PATH, PB_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"Expected exit code 0, got {result.returncode}. Stderr: {result.stderr}\nStdout: {result.stdout}"

    assert os.path.isfile(ENV_FILE), f"{ENV_FILE} was not created."
    with open(ENV_FILE, "r") as f:
        env_content = f.read()

    assert "export THRESHOLD=24" in env_content, f"{ENV_FILE} missing 'export THRESHOLD=24'. Content:\n{env_content}"
    assert "export WORKERS=4" in env_content, f"{ENV_FILE} missing 'export WORKERS=4'. Content:\n{env_content}"

    assert os.path.isfile(LOG_FILE), f"{LOG_FILE} was not created."
    with open(LOG_FILE, "r") as f:
        log_content = f.read().strip()

    assert "[SUCCESS] CI Pipeline Passed" in log_content, f"Log file missing success message. Content:\n{log_content}"


def test_runner_checksum_failure():
    with tempfile.TemporaryDirectory() as tmpdir:
        dummy_file = os.path.join(tmpdir, "dummy.txt")
        with open(dummy_file, "w") as f:
            f.write("test data")

        pb_path = os.path.join(tmpdir, "fail.pb")
        with open(pb_path, "w") as f:
            f.write("CHECKSUM dummy.txt invalidhash123\n")

        result = subprocess.run([RUNNER_PATH, pb_path], capture_output=True, text=True)
        assert result.returncode == 1, f"Expected exit code 1 for checksum failure, got {result.returncode}"

        assert os.path.isfile(LOG_FILE), f"{LOG_FILE} was not created during checksum failure."
        with open(LOG_FILE, "r") as f:
            log_content = f.read().strip()
        assert "[ERROR] Checksum failed for dummy.txt" in log_content, f"Missing checksum error in log. Content:\n{log_content}"


def test_runner_build_failure():
    with tempfile.TemporaryDirectory() as tmpdir:
        pb_path = os.path.join(tmpdir, "fail_build.pb")
        with open(pb_path, "w") as f:
            f.write("BUILD exit 1\n")

        result = subprocess.run([RUNNER_PATH, pb_path], capture_output=True, text=True)
        assert result.returncode == 2, f"Expected exit code 2 for build failure, got {result.returncode}"

        assert os.path.isfile(LOG_FILE), f"{LOG_FILE} was not created during build failure."
        with open(LOG_FILE, "r") as f:
            log_content = f.read().strip()
        assert "[ERROR] Build failed: exit 1" in log_content, f"Missing build error in log. Content:\n{log_content}"


def test_runner_clears_log_and_env():
    with open(ENV_FILE, "w") as f:
        f.write("GARBAGE_ENV\n")
    with open(LOG_FILE, "w") as f:
        f.write("GARBAGE_LOG\n")

    with tempfile.TemporaryDirectory() as tmpdir:
        pb_path = os.path.join(tmpdir, "empty.pb")
        with open(pb_path, "w") as f:
            f.write("")

        subprocess.run([RUNNER_PATH, pb_path], capture_output=True, text=True)

        with open(ENV_FILE, "r") as f:
            env_content = f.read()
        assert "GARBAGE_ENV" not in env_content, f"{ENV_FILE} was not cleared before execution."

        with open(LOG_FILE, "r") as f:
            log_content = f.read()
        assert "GARBAGE_LOG" not in log_content, f"{LOG_FILE} was not cleared before execution."


def test_randomized_complete_pipeline():
    rng = random.SystemRandom()
    token = secrets.token_hex(6).upper()
    names = [f"PB_{token}_TOTAL", f"PB_{token}_QUOTIENT", f"PB_{token}_CHAIN"]

    a, b, c, d = [rng.randint(3, 30) for _ in range(4)]
    u, divisor, v, w = rng.randint(4, 25), rng.randint(2, 9), rng.randint(2, 20), rng.randint(2, 8)
    x, y, z = rng.randint(30, 70), rng.randint(2, 12), rng.randint(2, 12)

    expressions = [
        f"({a} + {b}) * {c} - {d}",
        f"(({u} * {divisor}) / {divisor} + {v}) * {w}",
        f"{x} - {y} - {z}",
    ]
    expected = {
        names[0]: (a + b) * c - d,
        names[1]: (u + v) * w,
        names[2]: x - y - z,
    }

    with tempfile.TemporaryDirectory() as tmpdir:
        payload_name = f"payload_{token}.bin"
        payload = os.path.join(tmpdir, payload_name)
        with open(payload, "wb") as f:
            f.write(secrets.token_bytes(257))

        verify_name = f"verify_{token}.py"
        verify_path = os.path.join(tmpdir, verify_name)
        with open(verify_path, "w") as f:
            f.write("import os\n")
            f.write(f"expected = {expected!r}\n")
            f.write("for key, value in expected.items():\n")
            f.write("    assert os.environ.get(key) == str(value), (key, os.environ.get(key), value)\n")
            f.write(f"assert os.getcwd() == {tmpdir!r}\n")
            f.write("with open('first_build.marker', 'w') as out:\n")
            f.write("    out.write('environment and cwd verified')\n")

        second_name = f"second_{token}.py"
        second_path = os.path.join(tmpdir, second_name)
        with open(second_path, "w") as f:
            f.write("import os\n")
            f.write(f"assert os.environ.get({names[1]!r}) == {str(expected[names[1]])!r}\n")
            f.write("assert os.path.exists('first_build.marker')\n")
            f.write("with open('second_build.marker', 'w') as out:\n")
            f.write("    out.write('second build ran')\n")

        def sha256(path):
            with open(path, "rb") as f:
                return hashlib.sha256(f.read()).hexdigest()

        pb_path = os.path.join(tmpdir, f"pipeline_{token}.pb")
        with open(pb_path, "w") as f:
            f.write(f"CHECKSUM {payload_name} {sha256(payload)}\n")
            f.write(f"CHECKSUM {verify_name} {sha256(verify_path)}\n")
            f.write(f"CHECKSUM {second_name} {sha256(second_path)}\n")
            for name, expression in zip(names, expressions):
                f.write(f"EXPR {name} = {expression}\n")
            f.write(f"BUILD python3 {verify_name}\n")
            f.write(f"BUILD python3 {second_name}\n")

        result = subprocess.run([RUNNER_PATH, pb_path], capture_output=True, text=True, timeout=20)
        assert result.returncode == 0, f"Random pipeline failed with {result.returncode}. stdout={result.stdout!r}, stderr={result.stderr!r}"
        assert os.path.isfile(os.path.join(tmpdir, "first_build.marker")), "First successful BUILD command was not executed"
        assert os.path.isfile(os.path.join(tmpdir, "second_build.marker")), "Second successful BUILD command was not executed"

        with open(ENV_FILE) as f:
            env_lines = [line.strip() for line in f if line.strip()]
        assert env_lines == [f"export {name}={expected[name]}" for name in names], f"Unexpected generated environment: {env_lines!r}"

        with open(LOG_FILE) as f:
            log_content = f.read()
        assert "[SUCCESS] CI Pipeline Passed" in log_content


def test_randomized_checksum_is_computed_and_stops_pipeline():
    token = secrets.token_hex(7)
    with tempfile.TemporaryDirectory() as tmpdir:
        data_name = f"asset_{token}.dat"
        data_path = os.path.join(tmpdir, data_name)
        original = secrets.token_bytes(193)
        with open(data_path, "wb") as f:
            f.write(original)
        expected_hash = hashlib.sha256(original).hexdigest()

        build_name = f"should_not_run_{token}.py"
        with open(os.path.join(tmpdir, build_name), "w") as f:
            f.write("open('forbidden.marker', 'w').write('ran')\n")

        pb_path = os.path.join(tmpdir, f"checksum_{token}.pb")
        with open(pb_path, "w") as f:
            f.write(f"CHECKSUM {data_name} {expected_hash}\n")
            f.write(f"BUILD python3 {build_name}\n")

        with open(data_path, "ab") as f:
            f.write(secrets.token_bytes(17))

        result = subprocess.run([RUNNER_PATH, pb_path], capture_output=True, text=True, timeout=20)
        assert result.returncode == 1, f"Changed file should fail its derived checksum, got {result.returncode}"
        assert not os.path.exists(os.path.join(tmpdir, "forbidden.marker")), "Pipeline continued after checksum failure"
        with open(LOG_FILE) as f:
            log_content = f.read()
        assert f"[ERROR] Checksum failed for {data_name}" in log_content
        assert "[SUCCESS] CI Pipeline Passed" not in log_content


def test_randomized_build_command_failure_is_executed_and_stops_pipeline():
    token = secrets.token_hex(7)
    failure_code = random.SystemRandom().randint(3, 9)
    with tempfile.TemporaryDirectory() as tmpdir:
        fail_name = f"fail_{token}.py"
        with open(os.path.join(tmpdir, fail_name), "w") as f:
            f.write("open('failing_build_ran.marker', 'w').write('ran')\n")
            f.write(f"raise SystemExit({failure_code})\n")

        after_name = f"after_{token}.py"
        with open(os.path.join(tmpdir, after_name), "w") as f:
            f.write("open('after_failure.marker', 'w').write('ran')\n")

        command = f"python3 {fail_name}"
        pb_path = os.path.join(tmpdir, f"build_failure_{token}.pb")
        with open(pb_path, "w") as f:
            f.write(f"BUILD {command}\n")
            f.write(f"BUILD python3 {after_name}\n")

        result = subprocess.run([RUNNER_PATH, pb_path], capture_output=True, text=True, timeout=20)
        assert result.returncode == 2, f"Expected runner status 2 for arbitrary failed build, got {result.returncode}"
        assert os.path.isfile(os.path.join(tmpdir, "failing_build_ran.marker")), "Failing BUILD command was not actually executed in the specification directory"
        assert not os.path.exists(os.path.join(tmpdir, "after_failure.marker")), "Runner did not stop immediately after a failed BUILD"
        with open(LOG_FILE) as f:
            log_content = f.read()
        assert f"[ERROR] Build failed: {command}" in log_content
        assert "[SUCCESS] CI Pipeline Passed" not in log_content
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
