#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import inspect
import json
import os
import random
import string
import subprocess
import sys
import tempfile
import pytest


def test_custom_session_lib_installed():
    """Check if the custom_session_lib was fixed and installed successfully."""
    try:
        import custom_session_lib
    except ImportError:
        pytest.fail("custom_session_lib is not installed in the current environment. Ensure you fixed setup.py and ran pip install.")


def test_forge_py_exists():
    """Check if the forge.py script exists at the correct location."""
    assert os.path.isfile("/home/user/forge.py"), "/home/user/forge.py does not exist."


def test_forge_py_accuracy():
    """Test exact token forging and isolated validation for 50 random usernames."""
    try:
        import custom_session_lib
    except ImportError:
        pytest.fail("Cannot run accuracy test because custom_session_lib is not installed.")

    module_path = inspect.getsourcefile(custom_session_lib)
    assert module_path and os.path.isfile(module_path), "Cannot instrument the installed custom_session_lib."

    with open(module_path, "rb") as f:
        original_module = f.read()

    instrumentation = r'''

# Verification-time instrumentation: preserve the real function while recording
# which process called it and with which token.
_verifier_original_verify_token = verify_token

def verify_token(token_hex):
    try:
        return _verifier_original_verify_token(token_hex)
    finally:
        try:
            import json as _verifier_json
            import os as _verifier_os
            _verifier_log = _verifier_os.environ.get("SESSION_VERIFY_LOG")
            if _verifier_log:
                with open(_verifier_log, "a", encoding="utf-8") as _verifier_f:
                    _verifier_f.write(_verifier_json.dumps([_verifier_os.getpid(), str(token_hex)]) + "\n")
        except Exception:
            pass
'''

    with open(module_path, "ab") as f:
        if original_module and not original_module.endswith(b"\n"):
            f.write(b"\n")
        f.write(instrumentation.encode("utf-8"))

    correct_count = 0
    total_cases = 50
    key = "secret42"

    try:
        for _ in range(total_cases):
            username = ''.join(random.choices(string.ascii_lowercase + string.digits, k=8))
            expected_plaintext = f"username:{username},role:admin"
            expected_token = "".join(
                f"{ord(c) ^ ord(key[i % len(key)]):02x}"
                for i, c in enumerate(expected_plaintext)
            )

            fd, log_path = tempfile.mkstemp(prefix="session_verify_", suffix=".jsonl")
            os.close(fd)
            env = os.environ.copy()
            env["SESSION_VERIFY_LOG"] = log_path

            try:
                process = subprocess.Popen(
                    [sys.executable, "/home/user/forge.py", username],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    env=env,
                )
                try:
                    stdout, stderr = process.communicate(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.communicate()
                    continue

                if process.returncode != 0:
                    continue

                token = stdout.strip()

                # Keep the real library assertion and independently require the
                # exact username-specific admin ciphertext.
                try:
                    library_valid = bool(custom_session_lib.verify_token(token))
                except BaseException:
                    library_valid = False

                if not library_valid or token != expected_token:
                    continue

                # The instrumented real verification function must have been
                # called with this token by a process other than forge.py itself.
                isolated_validation = False
                try:
                    with open(log_path, "r", encoding="utf-8") as f:
                        for line in f:
                            try:
                                pid, validated_token = json.loads(line)
                            except Exception:
                                continue
                            if validated_token == expected_token and int(pid) != process.pid:
                                isolated_validation = True
                                break
                except OSError:
                    pass

                if isolated_validation:
                    correct_count += 1
            finally:
                try:
                    os.unlink(log_path)
                except OSError:
                    pass
    finally:
        with open(module_path, "wb") as f:
            f.write(original_module)

    accuracy = correct_count / float(total_cases)
    assert accuracy >= 1.0, (
        f"Metric threshold failed: Accuracy = {accuracy} (Threshold >= 1.0). "
        f"Only {correct_count} out of {total_cases} tokens were forged and validated correctly."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
