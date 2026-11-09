#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import time
import uuid

APP_DIR = Path("/home/user/app")
VENV_DIR = Path("/home/user/venv")
GATEWAY_SH = APP_DIR / "gateway.sh"
PROCESS_PY = APP_DIR / "process.py"
MAKEFILE = APP_DIR / "Makefile"
HELPER_BIN = APP_DIR / "helper_bin"
PYTHON_BIN = VENV_DIR / "bin" / "python"


def run(command, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 15)
    return subprocess.run(command, **kwargs)


def fresh_ip():
    token = uuid.uuid4().int
    return f"198.18.{(token >> 8) % 250 + 1}.{token % 250 + 1}"


def normalized_response(output):
    return output.rstrip("\n")


def test_venv_and_pyyaml():
    assert VENV_DIR.is_dir(), f"Virtual environment directory {VENV_DIR} does not exist."
    assert PYTHON_BIN.is_file(), "Python executable not found in the virtual environment."

    result = run([str(PYTHON_BIN), "-c", "import yaml; print(yaml.__version__)"])
    assert result.returncode == 0, "pyyaml is not installed in the virtual environment."
    assert result.stdout.strip(), "The virtual environment did not import a real PyYAML module."


def test_makefile_and_compilation():
    assert MAKEFILE.is_file(), f"Makefile {MAKEFILE} does not exist."
    content = MAKEFILE.read_text()

    assert "\tgcc" in content, "Makefile should use tabs for indentation, not spaces."
    assert "-lm" in content, "Makefile should include the -lm flag for math library."

    assert HELPER_BIN.is_file(), "helper_bin was not compiled."
    assert os.access(HELPER_BIN, os.X_OK), "helper_bin is not executable."

    # Rebuild from the submitted Makefile instead of trusting a pre-created executable.
    HELPER_BIN.unlink()
    build = run(["make", "helper_bin"], cwd=str(APP_DIR))
    assert build.returncode == 0, f"Makefile could not build helper_bin:\n{build.stdout}\n{build.stderr}"
    assert HELPER_BIN.is_file(), "Makefile did not produce helper_bin."
    assert os.access(HELPER_BIN, os.X_OK), "Rebuilt helper_bin is not executable."
    assert HELPER_BIN.read_bytes()[:4] == b"\x7fELF", "helper_bin is not a compiled native executable."

    result = run([str(HELPER_BIN)], cwd=str(APP_DIR))
    assert result.returncode == 0, "helper_bin failed to execute."
    assert "Helper output: 4" in result.stdout, "helper_bin output is incorrect."
    assert result.stdout.strip() == "Helper output: 4", "helper_bin produced unexpected output."


def test_python_script_updated_and_executable():
    assert PROCESS_PY.is_file(), f"Python script {PROCESS_PY} does not exist."
    content = PROCESS_PY.read_text()

    assert "print " not in content, "Python 2 print statements still exist in process.py."
    assert "print(" in content, "Python 3 print() function is not used in process.py."
    assert "yaml.load(" not in content, "Deprecated yaml.load() is still used in process.py."
    assert "yaml.safe_load(" in content, "yaml.safe_load() is not used in process.py."

    result = run([str(PYTHON_BIN), str(PROCESS_PY)], cwd=str(APP_DIR))
    assert result.returncode == 0, f"process.py failed under the virtual environment Python: {result.stderr}"
    assert "Status: 200 OK" in result.stdout
    assert "Content-Type: text/plain" in result.stdout
    assert "Data: success" in result.stdout
    assert "System: Helper output: 4" in result.stdout

    # Ensure process.py really invokes helper_bin and passes its output through.
    original = HELPER_BIN.read_bytes()
    original_mode = stat.S_IMODE(HELPER_BIN.stat().st_mode)
    nonce = uuid.uuid4().hex
    try:
        HELPER_BIN.write_text(f"#!/bin/sh\nprintf '%s\\n' 'dynamic-helper-{nonce}'\n")
        HELPER_BIN.chmod(0o755)
        dynamic = run([str(PYTHON_BIN), str(PROCESS_PY)], cwd=str(APP_DIR))
        assert dynamic.returncode == 0, dynamic.stderr
        assert f"System: dynamic-helper-{nonce}" in dynamic.stdout, "process.py did not execute helper_bin and relay its output."
        assert "Data: success" in dynamic.stdout
    finally:
        HELPER_BIN.write_bytes(original)
        HELPER_BIN.chmod(original_mode)


def test_gateway_sh_executable_and_behavior():
    assert GATEWAY_SH.is_file(), f"Gateway script {GATEWAY_SH} does not exist."
    assert os.access(GATEWAY_SH, os.X_OK), "gateway.sh is not executable."
    first_line = GATEWAY_SH.read_text().splitlines()[0]
    assert first_line.startswith("#!") and "bash" in first_line, "gateway.sh must be a Bash script."
    syntax = run(["bash", "-n", str(GATEWAY_SH)])
    assert syntax.returncode == 0, f"gateway.sh has invalid Bash syntax: {syntax.stderr}"

    # Replace process.py temporarily with a dynamic probe. The unpredictable result
    # verifies that the gateway actually executes this path using the venv Python.
    original_process = PROCESS_PY.read_bytes()
    original_mode = stat.S_IMODE(PROCESS_PY.stat().st_mode)
    probe_input = uuid.uuid4().hex
    expected_digest = hashlib.sha256(probe_input.encode()).hexdigest()
    probe_source = '''import hashlib\nimport os\nimport sys\nvalue = os.environ["GATEWAY_PROBE_INPUT"]\nprint("PROBE:" + hashlib.sha256(value.encode()).hexdigest())\nprint("PYTHON:" + sys.executable)\n'''

    ip_a = fresh_ip()
    ip_b = fresh_ip()
    while ip_b == ip_a:
        ip_b = fresh_ip()

    try:
        PROCESS_PY.write_text(probe_source)
        PROCESS_PY.chmod(0o644)

        base_env = os.environ.copy()
        base_env["GATEWAY_PROBE_INPUT"] = probe_input

        # Invalid keys must be rejected exactly and must not execute or consume
        # the rate-limit slot for the address.
        bad_env = base_env.copy()
        bad_env["HTTP_X_API_KEY"] = "wrong_key"
        bad_env["REMOTE_ADDR"] = ip_a
        bad = run([str(GATEWAY_SH)], env=bad_env, cwd=tempfile.gettempdir())
        assert normalized_response(bad.stdout) == "Status: 403 Forbidden\n\nAccess Denied"
        assert expected_digest not in bad.stdout, "Unauthorized request executed process.py."

        good_a = base_env.copy()
        good_a["HTTP_X_API_KEY"] = "SecretMigrate99"
        good_a["REMOTE_ADDR"] = ip_a
        first = run([str(GATEWAY_SH)], env=good_a, cwd=tempfile.gettempdir())
        assert first.returncode == 0, first.stderr
        assert normalized_response(first.stdout) == f"PROBE:{expected_digest}\nPYTHON:{PYTHON_BIN}", \
            "Gateway did not pass through the dynamically executed process.py output."

        second = run([str(GATEWAY_SH)], env=good_a, cwd=tempfile.gettempdir())
        assert normalized_response(second.stdout) == "Status: 429 Too Many Requests\n\nRate Limited"
        assert expected_digest not in second.stdout, "Rate-limited request executed process.py."

        # Rate limiting must be per address, not a single global canned response.
        good_b = base_env.copy()
        good_b["HTTP_X_API_KEY"] = "SecretMigrate99"
        good_b["REMOTE_ADDR"] = ip_b
        independent = run([str(GATEWAY_SH)], env=good_b, cwd=tempfile.gettempdir())
        assert normalized_response(independent.stdout) == f"PROBE:{expected_digest}\nPYTHON:{PYTHON_BIN}"

        time.sleep(2.2)
        third = run([str(GATEWAY_SH)], env=good_a, cwd=tempfile.gettempdir())
        assert normalized_response(third.stdout) == f"PROBE:{expected_digest}\nPYTHON:{PYTHON_BIN}"
    finally:
        PROCESS_PY.write_bytes(original_process)
        PROCESS_PY.chmod(original_mode)

    # Retain the original end-to-end assertions against the migrated application.
    actual_env = os.environ.copy()
    actual_env["HTTP_X_API_KEY"] = "SecretMigrate99"
    actual_env["REMOTE_ADDR"] = fresh_ip()
    actual = run([str(GATEWAY_SH)], env=actual_env, cwd=tempfile.gettempdir())
    assert actual.returncode == 0, actual.stderr
    assert "Status: 200 OK" in actual.stdout, "Gateway did not return 'Status: 200 OK' on a valid request."
    assert "Helper output: 4" in actual.stdout, "Gateway did not correctly output the helper_bin result."
    assert "Data: success" in actual.stdout, "Gateway did not correctly output the parsed YAML data."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
