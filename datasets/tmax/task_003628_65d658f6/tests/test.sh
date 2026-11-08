#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shlex
import subprocess
from pathlib import Path

PROJECT_DIR = "/home/user/polyglot-eval"
BUILD_SH_PATH = os.path.join(PROJECT_DIR, "build.sh")
CONFIG_PATH = os.path.join(PROJECT_DIR, "ci_config.json")
LOG_PATH = "/home/user/build_out.log"


def test_build_sh_exists_and_executable():
    assert os.path.isfile(BUILD_SH_PATH), f"Script missing: {BUILD_SH_PATH}"
    assert os.access(BUILD_SH_PATH, os.X_OK), f"Script is not executable: {BUILD_SH_PATH}"


def test_build_sh_uses_jq():
    with open(BUILD_SH_PATH, "r") as f:
        content = f.read()
    assert "jq " in content, "build.sh does not appear to use 'jq' to parse ci_config.json"


def test_python_tests_fixed():
    env = os.environ.copy()
    env["PYTHONPATH"] = "src"

    result = subprocess.run(
        ["python3", "-m", "unittest", "discover", "-s", "tests"],
        cwd=PROJECT_DIR,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )

    assert result.returncode == 0, (
        f"Python tests failed or are not isolated.\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    )
    assert "OK" in result.stderr or "OK" in result.stdout, "Tests did not run successfully."


def test_python_tests_pass_in_reverse_order_in_one_process():
    env = os.environ.copy()
    env["PYTHONPATH"] = os.pathsep.join([
        os.path.join(PROJECT_DIR, "src"),
        os.path.join(PROJECT_DIR, "tests"),
    ])
    code = r'''import unittest
import test_a_parser
import test_b_config
suite = unittest.TestSuite()
suite.addTest(test_b_config.TestConfig("test_disable_strict_mode"))
suite.addTest(test_a_parser.TestParser("test_parse_strict"))
result = unittest.TextTestRunner(verbosity=2).run(suite)
raise SystemExit(0 if result.wasSuccessful() else 1)
'''
    result = subprocess.run(
        ["python3", "-c", code],
        cwd=PROJECT_DIR,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        "Tests are not isolated when config runs before parser.\n"
        f"STDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    )
    assert "OK" in result.stdout or "OK" in result.stderr


def test_build_out_log_contents():
    try:
        os.remove(LOG_PATH)
    except FileNotFoundError:
        pass

    result = subprocess.run(
        [BUILD_SH_PATH],
        cwd=PROJECT_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )

    assert result.returncode == 0, (
        f"build.sh failed.\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    )
    assert os.path.isfile(LOG_PATH), f"Log file missing: {LOG_PATH}"

    with open(LOG_PATH, "r") as f:
        log_content = f.read()

    assert "BenchmarkEvaluate" in log_content, "Go benchmark output not found in build_out.log"
    assert "OK" in log_content, "Python test success (OK) not found in build_out.log"
    assert "FAILED" not in log_content.upper(), "Found 'FAILED' in build_out.log, tests might be failing."


def test_build_extracts_with_jq_and_executes_both_commands_in_order():
    nonce = secrets.token_hex(16)
    first_out = "GO_STDOUT_" + nonce
    first_err = "GO_STDERR_" + nonce
    second_out = "PY_STDOUT_" + nonce
    second_err = "PY_STDERR_" + nonce
    state_path = f"/tmp/polyglot_order_{nonce}"

    first_code = (
        "import pathlib,sys;"
        f"pathlib.Path({state_path!r}).write_text({nonce!r});"
        f"print({first_out!r});"
        f"print({first_err!r}, file=sys.stderr)"
    )
    second_code = (
        "import pathlib,sys;"
        f"assert pathlib.Path({state_path!r}).read_text() == {nonce!r};"
        f"print({second_out!r});"
        f"print({second_err!r}, file=sys.stderr)"
    )
    dynamic_config = {
        "go_bench_cmd": "python3 -c " + shlex.quote(first_code),
        "py_test_cmd": "python3 -c " + shlex.quote(second_code),
    }

    config_original = Path(CONFIG_PATH).read_bytes()
    jq_path = Path("/usr/bin/jq")
    real_jq = Path(f"/tmp/real_jq_{nonce}")
    jq_calls = Path(f"/tmp/jq_calls_{nonce}")
    jq_output = Path(f"/tmp/jq_output_{nonce}")
    wrapper_installed = False

    try:
        Path(CONFIG_PATH).write_text(json.dumps(dynamic_config), encoding="utf-8")
        Path(LOG_PATH).unlink(missing_ok=True)
        Path(state_path).unlink(missing_ok=True)

        jq_path.rename(real_jq)
        wrapper = f'''#!/bin/bash
printf '%s\\n' "invoked" >> {shlex.quote(str(jq_calls))}
set -o pipefail
{shlex.quote(str(real_jq))} "$@" | tee -a {shlex.quote(str(jq_output))}
'''
        jq_path.write_text(wrapper, encoding="utf-8")
        jq_path.chmod(0o755)
        wrapper_installed = True

        result = subprocess.run(
            [BUILD_SH_PATH],
            cwd=PROJECT_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )

        assert result.returncode == 0, (
            f"build.sh failed with commands read from ci_config.json.\n"
            f"STDOUT: {result.stdout}\nSTDERR: {result.stderr}"
        )
        assert jq_calls.is_file() and jq_calls.read_text().strip(), "build.sh did not execute jq"
        extracted = jq_output.read_text() if jq_output.is_file() else ""
        assert first_out in extracted and second_out in extracted, (
            "jq did not extract both configured command values from ci_config.json"
        )

        assert Path(LOG_PATH).is_file(), f"Log file missing: {LOG_PATH}"
        log_content = Path(LOG_PATH).read_text()
        for marker in (first_out, first_err, second_out, second_err):
            assert marker in log_content, f"Output from an executed configured command is missing: {marker}"

        leaked_terminal_output = result.stdout + result.stderr
        for marker in (first_out, first_err, second_out, second_err):
            assert marker not in leaked_terminal_output, (
                "Command output was not fully redirected to /home/user/build_out.log"
            )
        assert Path(state_path).read_text() == nonce, "The first configured command was not executed"
    finally:
        Path(CONFIG_PATH).write_bytes(config_original)
        Path(state_path).unlink(missing_ok=True)
        if wrapper_installed:
            jq_path.unlink(missing_ok=True)
        if real_jq.exists():
            real_jq.rename(jq_path)
        jq_calls.unlink(missing_ok=True)
        jq_output.unlink(missing_ok=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
