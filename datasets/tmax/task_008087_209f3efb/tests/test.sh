#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import glob
import os
import secrets
import subprocess

HOME = "/home/user"
LOG_PATH = os.path.join(HOME, "upload_access.log")
MALICIOUS_PATHS = os.path.join(HOME, "malicious_paths.txt")
PAYLOAD_PATH = os.path.join(HOME, "test_payload.txt")
TARGET_PATH = "../../../../home/user/proof.txt"


def run_script(path):
    try:
        result = subprocess.run(
            ["python3", path],
            cwd=HOME,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        return result.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def remove_if_present(path):
    try:
        os.remove(path)
    except FileNotFoundError:
        pass


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def test_scripts_and_final_outputs():
    scripts = [
        path for path in glob.glob(os.path.join(HOME, "*.py"))
        if os.path.isfile(path) and not os.path.islink(path)
    ]
    assert len(scripts) >= 2, "At least two Python script files are required in /home/user/."

    token = secrets.token_hex(8)
    dynamic_paths = [
        f"../../../etc/{token}.conf",
        f"../../tmp/{token}.sh",
        f"../var/{token}.dat",
    ]
    expected_dynamic = sorted(dynamic_paths)

    def encoded(value):
        return base64.b64encode(value.encode("utf-8")).decode("ascii")

    dynamic_log = "\n".join([
        f"[2026-01-01 01:00:00] 192.0.2.1 POST /api/upload?target={encoded(f'uploads/{token}.png')} HTTP/1.1 200",
        f"[2026-01-01 01:00:01] 192.0.2.2 POST /api/upload?target={encoded(dynamic_paths[0])} HTTP/1.1 200",
        f"[2026-01-01 01:00:02] 192.0.2.3 POST /api/upload?target={encoded(dynamic_paths[1])} HTTP/1.1 200",
        f"[2026-01-01 01:00:03] 192.0.2.4 POST /api/upload?target={encoded('../../denied/' + token)} HTTP/1.1 403",
        f"[2026-01-01 01:00:04] 192.0.2.5 POST /api/upload?target={encoded(dynamic_paths[2])} HTTP/1.1 200",
        f"[2026-01-01 01:00:05] 192.0.2.6 POST /api/upload?target={encoded('../not-success/' + token)} HTTP/1.1 500",
    ]) + "\n"

    with open(LOG_PATH, "rb") as f:
        original_log = f.read()

    parser_candidates = []
    payload_candidates = []

    try:
        with open(LOG_PATH, "w") as f:
            f.write(dynamic_log)

        for script in scripts:
            remove_if_present(MALICIOUS_PATHS)
            if run_script(script) and os.path.isfile(MALICIOUS_PATHS):
                try:
                    if read_nonempty_lines(MALICIOUS_PATHS) == expected_dynamic:
                        parser_candidates.append(script)
                except (OSError, UnicodeError):
                    pass

        for script in scripts:
            remove_if_present(PAYLOAD_PATH)
            if run_script(script) and os.path.isfile(PAYLOAD_PATH):
                try:
                    with open(PAYLOAD_PATH, "r") as f:
                        content = f.read().strip()
                    expected_payload = base64.b64encode(TARGET_PATH.encode("utf-8")).decode("utf-8")
                    if content == expected_payload:
                        payload_candidates.append(script)
                except (OSError, UnicodeError):
                    pass

        selected_pair = next(
            ((parser, payload) for parser in parser_candidates for payload in payload_candidates
             if parser != payload),
            None,
        )
        assert selected_pair is not None, (
            "Could not find two distinct Python scripts that generate the required files; "
            "the parser must handle fresh log data and the payload script must create test_payload.txt."
        )
    finally:
        with open(LOG_PATH, "wb") as f:
            f.write(original_log)

    parser_script, payload_script = selected_pair
    remove_if_present(MALICIOUS_PATHS)
    remove_if_present(PAYLOAD_PATH)
    assert run_script(parser_script), "The parsing script failed on /home/user/upload_access.log."
    assert run_script(payload_script), "The payload-generation script failed."

    # Original assertions: malicious_paths.txt must contain the exact sorted paths.
    file_path = "/home/user/malicious_paths.txt"
    assert os.path.isfile(file_path), f"The file {file_path} does not exist."

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_paths = [
        "../../tmp/hidden.sh",
        "../../var/www/html/shell.php",
        "../../../etc/passwd"
    ]
    expected_paths.sort()

    assert lines == expected_paths, f"The contents of {file_path} do not match the expected sorted malicious paths. Found: {lines}"

    # Original assertion: test_payload.txt must contain the exact Base64 payload.
    file_path = "/home/user/test_payload.txt"
    assert os.path.isfile(file_path), f"The file {file_path} does not exist."

    with open(file_path, "r") as f:
        content = f.read().strip()

    target_path = "../../../../home/user/proof.txt"
    expected_base64 = base64.b64encode(target_path.encode('utf-8')).decode('utf-8')

    assert content == expected_base64, f"The content of {file_path} does not match the expected Base64 payload. Expected '{expected_base64}', got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
