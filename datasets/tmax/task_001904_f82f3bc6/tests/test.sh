#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import os
import secrets
import socket
import subprocess
import tarfile
import time

import pytest
import requests


def test_frontend_cwe_txt():
    path = "/home/user/frontend_cwe.txt"
    assert os.path.isfile(path), f"{path} is missing."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content in ["CWE-22", "CWE-78"], f"Expected CWE-22 or CWE-78 in {path}, got: {content}"


def test_backup_script_fixed():
    path = "/app/system_audit/backup.sh"
    assert os.path.isfile(path), f"{path} is missing."
    with open(path, "r") as f:
        content = f.read()

    # Preserve the original static assertions.
    assert "tar" in content, "The backup.sh script must still use 'tar'."
    for line in content.splitlines():
        if "tar " in line:
            assert "*" not in line, f"Wildcard '*' found in tar command: {line}"

    # Exercise the script with both ordinary content and GNU tar option-like
    # filenames. A wildcard-based invocation would execute the payload.
    token = secrets.token_hex(8)
    logs = "/app/logs"
    probe_dir = os.path.join(logs, f"verify_{token}")
    probe_file = os.path.join(probe_dir, "content.txt")
    payload_script = os.path.join(logs, f"exploit_{token}.sh")
    checkpoint = os.path.join(logs, "--checkpoint=1")
    action = os.path.join(logs, f"--checkpoint-action=exec=sh exploit_{token}.sh")
    marker = f"/tmp/backup_executed_{token}"
    archive = "/app/backup.tar"

    os.makedirs(probe_dir)
    expected = f"backup verification {token}\n"
    with open(probe_file, "w") as f:
        f.write(expected)
    with open(payload_script, "w") as f:
        f.write(f"#!/bin/sh\nprintf exploited > {marker}\n")
    os.chmod(payload_script, 0o755)
    open(checkpoint, "w").close()
    open(action, "w").close()
    if os.path.exists(marker):
        os.unlink(marker)
    if os.path.exists(archive):
        os.unlink(archive)

    try:
        started = time.time()
        result = subprocess.run(
            ["/bin/bash", path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"backup.sh failed with status {result.returncode}: {result.stderr}"
        )
        assert not os.path.exists(marker), (
            "backup.sh interpreted a crafted filename as a tar option and executed it"
        )
        assert os.path.isfile(archive), "backup.sh did not create /app/backup.tar"
        assert os.path.getmtime(archive) >= started - 1, "backup archive was not freshly produced"

        with tarfile.open(archive, "r") as tf:
            suffix = f"verify_{token}/content.txt"
            matches = [m for m in tf.getmembers() if m.name.lstrip("./").endswith(suffix)]
            assert matches, "The generated archive does not contain the verification log file"
            archived = tf.extractfile(matches[0])
            assert archived is not None, "Verification log entry is not a regular archived file"
            assert archived.read().decode() == expected, "Archived log content is incorrect"
    finally:
        for item in (action, checkpoint, payload_script):
            try:
                os.unlink(item)
            except FileNotFoundError:
                pass
        try:
            os.unlink(marker)
        except FileNotFoundError:
            pass
        try:
            os.unlink(probe_file)
            os.rmdir(probe_dir)
        except FileNotFoundError:
            pass


def test_flag_decrypted():
    path = "/home/user/flag.txt"
    assert os.path.isfile(path), f"{path} is missing."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "FLAG{x0r_1s_n0t_s3cur3_3ncrypt10n}", f"Incorrect flag in {path}"


def test_frontend_source_read_is_safe_and_functional():
    app_path = "/app/frontend/app.py"
    assert os.path.isfile(app_path), f"{app_path} is missing."

    token = secrets.token_hex(8)
    inside_name = f"allowed_{token}.txt"
    inside_path = os.path.join("/app/data", inside_name)
    outside_name = f"read_probe_{token}.txt"
    outside_path = os.path.join("/app", outside_name)
    secret = f"outside-secret-{secrets.token_hex(16)}"
    marker = f"/tmp/read_command_{token}"

    with open(inside_path, "w") as f:
        f.write(f"inside-{token}")
    with open(outside_path, "w") as f:
        f.write(secret)

    try:
        # Import and execute the submitted artifact itself, rather than trusting
        # only an already-running process.
        spec = importlib.util.spec_from_file_location(f"vault_frontend_{token}", app_path)
        assert spec is not None and spec.loader is not None, "Could not load frontend app.py"
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        assert hasattr(module, "app"), "frontend app.py does not define a Flask app"
        client = module.app.test_client()

        good = client.get("/read", query_string={"file": inside_name})
        assert good.status_code == 200, f"Legitimate /read request failed: {good.status_code}"
        assert good.get_data(as_text=True) == f"inside-{token}"

        traversal = f"../{outside_name}"
        bad = client.get("/read", query_string={"file": traversal})
        assert secret not in bad.get_data(as_text=True), "Source /read endpoint allows path traversal"
        assert bad.status_code != 200, "Traversal request was accepted by source /read endpoint"

        injection = f"missing;touch {marker};#"
        client.get("/read", query_string={"file": injection})
        assert not os.path.exists(marker), "Source /read endpoint permits command injection"

        # Also require the online service to be running the secured behavior.
        live_good = requests.get(
            "http://127.0.0.1:8080/read", params={"file": inside_name}, timeout=5
        )
        assert live_good.status_code == 200
        assert live_good.text == f"inside-{token}"

        live_bad = requests.get(
            "http://127.0.0.1:8080/read", params={"file": traversal}, timeout=5
        )
        assert secret not in live_bad.text, "Running /read endpoint allows path traversal"
        assert live_bad.status_code != 200, "Running service accepted a traversal request"

        requests.get(
            "http://127.0.0.1:8080/read", params={"file": injection}, timeout=5
        )
        assert not os.path.exists(marker), "Running /read endpoint permits command injection"
    finally:
        for item in (inside_path, outside_path, marker):
            try:
                os.unlink(item)
            except FileNotFoundError:
                pass


def test_service_configuration():
    with open("/app/frontend/.env", "r") as f:
        frontend_env = f.read()
    assert "CRYPTO_SERVICE_URL=http://127.0.0.1:5000" in frontend_env
    assert "REDIS_URL=redis://127.0.0.1:6379" in frontend_env


def test_frontend_health():
    url = "http://127.0.0.1:8080/health"
    try:
        response = requests.get(url, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to frontend health endpoint: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    try:
        json_data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert json_data.get("status") == "ok", f"Expected {{'status': 'ok'}}, got {json_data}"


def test_frontend_encrypt_proxy():
    # Use an unpredictable plaintext and independently derive the expected XOR
    # result, so a constant nonempty response cannot pass.
    text = "verify-" + secrets.token_hex(12)
    key = b"UEUQ"
    raw = text.encode()
    expected = bytes(raw[i] ^ key[i % len(key)] for i in range(len(raw))).hex()

    url = "http://127.0.0.1:8080/encrypt"
    try:
        response = requests.post(url, data={"text": text}, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to frontend encrypt endpoint: {e}")

    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    )
    assert response.text.strip(), "Expected a non-empty response from the encrypt endpoint."
    assert response.text.strip() == expected, "Frontend did not return the crypto service's correct result"

    direct = requests.post(
        "http://127.0.0.1:5000/encrypt", data={"text": text}, timeout=5
    )
    assert direct.status_code == 200
    assert direct.text.strip() == expected, "Crypto service returned incorrect encryption"


def test_crypto_service_listening():
    url = "http://127.0.0.1:5000"
    try:
        requests.get(url, timeout=5)
    except requests.ConnectionError:
        pytest.fail("Crypto service is not listening on 127.0.0.1:5000")
    except requests.RequestException:
        pass


def test_redis_service_listening():
    try:
        with socket.create_connection(("127.0.0.1", 6379), timeout=5) as sock:
            sock.sendall(b"*1\r\n$4\r\nPING\r\n")
            reply = sock.recv(128)
    except OSError as e:
        pytest.fail(f"Redis is not listening on 127.0.0.1:6379: {e}")
    assert reply.startswith(b"+PONG"), f"Redis did not answer PING correctly: {reply!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
