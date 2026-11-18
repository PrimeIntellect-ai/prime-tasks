#!/bin/bash
set -e
mkdir -p /logs/verifier

ORIGINAL_PROCESSOR=/app/legacy_processor
HIDDEN_PROCESSOR=/app/.legacy_processor.verifier-original
CALL_LOG=/tmp/verifier_legacy_calls

cleanup() {
    if [ -e "$HIDDEN_PROCESSOR" ]; then
        rm -f "$ORIGINAL_PROCESSOR"
        mv "$HIDDEN_PROCESSOR" "$ORIGINAL_PROCESSOR"
        chmod +x "$ORIGINAL_PROCESSOR"
    fi
}
trap cleanup EXIT

rm -f "$CALL_LOG"
touch "$CALL_LOG"
chmod 666 "$CALL_LOG"

if [ -e "$HIDDEN_PROCESSOR" ]; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi
mv "$ORIGINAL_PROCESSOR" "$HIDDEN_PROCESSOR"
cat > "$ORIGINAL_PROCESSOR" <<'WRAPPER_EOF'
#!/bin/bash
printf '%s\n' "$1" >> /tmp/verifier_legacy_calls
exec /app/.legacy_processor.verifier-original "$@"
WRAPPER_EOF
chmod 755 "$ORIGINAL_PROCESSOR"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
from pathlib import Path

import pytest
import requests

SERVICE_ROOT = Path("/home/user/service_root")
ORACLE_PROCESSOR = "/app/.legacy_processor.verifier-original"
CALL_LOG = Path("/tmp/verifier_legacy_calls")

FIXED_VALID = "48656c6c6f"
RANDOM_VALID = [secrets.token_hex(n) for n in (1, 2, 3, 7, 16, 31)]
RANDOM_VALID.append(secrets.token_hex(12).upper())
VALID_PAYLOADS = [FIXED_VALID] + RANDOM_VALID

FIXED_INVALID = "invalidhex!"
ODD_INVALID = secrets.token_hex(9) + secrets.choice("0123456789abcdef")
EVEN_INVALID = "zz" + secrets.token_hex(10)
INVALID_PAYLOADS = [FIXED_INVALID, ODD_INVALID, EVEN_INVALID]


def test_service_root_exists():
    assert os.path.isdir("/home/user/service_root/bin"), "The build script was not run successfully; /home/user/service_root/bin is missing."
    assert os.path.isfile("/home/user/service_root/bin/socat"), "socat is missing from the service root bin directory."
    assert os.path.isfile("/home/user/service_root/bin/jq"), "jq is missing from the service root bin directory."
    assert os.path.isfile("/home/user/service_root/server.sh"), "server.sh is missing from the generated service root."


def test_build_system_runs_and_generates_tools():
    build_script = Path("/app/builder/build.sh")
    assert build_script.is_file(), "The build script is missing."

    bin_dir = SERVICE_ROOT / "bin"
    saved_bin = SERVICE_ROOT / ".verifier-saved-bin"
    assert not saved_bin.exists(), "Unexpected verifier backup path already exists."

    if bin_dir.exists():
        bin_dir.rename(saved_bin)

    try:
        try:
            proc = subprocess.run(
                ["bash", str(build_script)],
                capture_output=True,
                text=True,
                timeout=10,
            )
        except subprocess.TimeoutExpired:
            pytest.fail("build.sh did not terminate; the circular source dependency is still present.")

        assert proc.returncode == 0, f"build.sh failed:\nstdout: {proc.stdout}\nstderr: {proc.stderr}"
        assert (bin_dir / "socat").is_file(), "build.sh did not generate bin/socat."
        assert (bin_dir / "jq").is_file(), "build.sh did not generate bin/jq."
        assert os.access(bin_dir / "socat", os.X_OK), "Generated socat is not executable."
        assert os.access(bin_dir / "jq", os.X_OK), "Generated jq is not executable."

        socat_check = subprocess.run([str(bin_dir / "socat"), "-V"], capture_output=True, timeout=5)
        jq_check = subprocess.run([str(bin_dir / "jq"), "--version"], capture_output=True, timeout=5)
        assert socat_check.returncode == 0, "Generated socat is not a working socat executable."
        assert jq_check.returncode == 0, "Generated jq is not a working jq executable."
    finally:
        if bin_dir.exists():
            shutil.rmtree(bin_dir)
        if saved_bin.exists():
            saved_bin.rename(bin_dir)


def get_expected_result(hex_payload: str) -> str:
    proc = subprocess.run(
        [ORACLE_PROCESSOR, hex_payload],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise ValueError("Invalid payload for legacy processor")
    return proc.stdout.strip()


def assert_json_headers(response):
    assert "application/json" in response.headers.get("Content-Type", ""), "Expected Content-Type to be application/json"
    assert "Content-Length" in response.headers, "Expected a Content-Length header"
    try:
        declared_length = int(response.headers["Content-Length"])
    except ValueError:
        pytest.fail(f"Content-Length was not an integer: {response.headers['Content-Length']!r}")
    assert declared_length == len(response.content), (
        f"Content-Length was {declared_length}, but the response body contained {len(response.content)} bytes"
    )


@pytest.mark.parametrize("payload", VALID_PAYLOADS)
def test_server_valid_request(payload):
    expected_output = get_expected_result(payload)

    try:
        response = requests.post(
            "http://127.0.0.1:9000/api/process",
            json={"payload": payload},
            timeout=5,
        )
    except requests.exceptions.ConnectionError:
        pytest.fail("Could not connect to the server at 127.0.0.1:9000. Is the server running?")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    assert_json_headers(response)

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response was not valid JSON: {response.text}")

    assert "result" in data, f"Expected 'result' key in JSON response, got {data}"
    assert data["result"] == expected_output, f"Expected result '{expected_output}', got '{data['result']}'"


@pytest.mark.parametrize("payload", INVALID_PAYLOADS)
def test_server_invalid_request(payload):
    try:
        response = requests.post(
            "http://127.0.0.1:9000/api/process",
            json={"payload": payload},
            timeout=5,
        )
    except requests.exceptions.ConnectionError:
        pytest.fail("Could not connect to the server at 127.0.0.1:9000. Is the server running?")

    assert response.status_code == 400, f"Expected status code 400 for invalid payload, got {response.status_code}. Response: {response.text}"
    assert_json_headers(response)

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response was not valid JSON: {response.text}")

    assert "error" in data, f"Expected 'error' key in JSON response, got {data}"
    assert data["error"] == "invalid payload", f"Expected error message 'invalid payload', got '{data['error']}'"


def test_server_invoked_legacy_processor_for_requests():
    calls = CALL_LOG.read_text().splitlines()
    for payload in VALID_PAYLOADS + INVALID_PAYLOADS:
        assert payload in calls, f"The server did not pass payload {payload!r} to /app/legacy_processor."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
