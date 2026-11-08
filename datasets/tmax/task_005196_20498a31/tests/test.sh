#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_localeserver.py
import os
import secrets
import socket
import time

import pytest
import requests

HTTP_BASE_URL = "http://127.0.0.1:8080"
TCP_HOST = "127.0.0.1"
TCP_PORT = 9000
PHASE = os.environ.get("PHASE", "initial")


def get_translation(locale, key, expected_status=200):
    try:
        response = requests.get(
            f"{HTTP_BASE_URL}/translate",
            params={"locale": locale, "key": key},
            timeout=2,
        )
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"HTTP request failed: {exc}")
    assert response.status_code == expected_status, (
        f"Expected HTTP {expected_status}, got {response.status_code}. "
        f"Response: {response.text}"
    )
    if expected_status == 200:
        data = response.json()
        assert "translation" in data, f"Missing translation field: {data}"
        return data["translation"]
    return None


def wait_for_translation(locale, key, expected, timeout=3):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            response = requests.get(
                f"{HTTP_BASE_URL}/translate",
                params={"locale": locale, "key": key},
                timeout=0.5,
            )
            if response.status_code == 200:
                last = response.json().get("translation")
                if last == expected:
                    return
        except Exception:
            pass
        time.sleep(0.05)
    pytest.fail(f"Expected {locale}:{key}={expected!r}, last value was {last!r}")


def send_updates(*lines):
    try:
        with socket.create_connection((TCP_HOST, TCP_PORT), timeout=2) as sock:
            for line in lines:
                sock.sendall((line + "\n").encode())
    except Exception as exc:
        pytest.fail(f"TCP connection or send failed: {exc}")


def test_server_ready():
    deadline = time.time() + 5
    while time.time() < deadline:
        try:
            requests.get(f"{HTTP_BASE_URL}/translate", timeout=0.5)
            with socket.create_connection((TCP_HOST, TCP_PORT), timeout=0.5):
                pass
            return
        except Exception:
            time.sleep(0.1)
    pytest.fail("HTTP and TCP listeners did not become ready")


def test_http_en_greeting():
    assert get_translation("en", "greeting") == "Welcome"


def test_http_eng_greeting():
    get_translation("ENG", "greeting", 404)


def test_all_remaining_cleaned_rows():
    assert get_translation("es", "greeting") == "Hola"
    assert get_translation("fr", "farewell") == "Adieu"


@pytest.mark.skipif(PHASE != "initial", reason="audio override is tested on the agent's running server")
def test_http_fr_greeting_audio_override():
    assert get_translation("fr", "greeting") == "salut"


@pytest.mark.skipif(PHASE != "initial", reason="preserved original fixed TCP assertion")
def test_tcp_ingestion_and_http_read():
    send_updates("es:farewell:Adios")
    wait_for_translation("es", "farewell", "Adios")


def test_arbitrary_streaming_tcp_updates():
    token = secrets.token_hex(12)
    key1 = "new_" + secrets.token_hex(8)
    key2 = "other_" + secrets.token_hex(8)
    value1 = "value_" + token
    value2 = "second_" + secrets.token_hex(12)

    send_updates(f"zz:{key1}:{value1}", f"xy:{key2}:{value2}")
    wait_for_translation("zz", key1, value1)
    wait_for_translation("xy", key2, value2)

    replacement = "replacement_" + secrets.token_hex(12)
    send_updates(f"zz:{key1}:{replacement}")
    wait_for_translation("zz", key1, replacement)


def test_tcp_rejects_invalid_locales():
    key = "invalid_" + secrets.token_hex(10)
    value = "should_not_exist_" + secrets.token_hex(10)
    send_updates(
        f"ENG:{key}:{value}",
        f"e1:{key}:{value}",
        f"E n:{key}:{value}",
    )
    time.sleep(0.15)
    get_translation("ENG", key, 404)
    get_translation("e1", key, 404)
    get_translation("E n", key, 404)
TEST_EOF

ok=1
PHASE=initial python3 -m pytest /tmp/test_localeserver.py -x --tb=short 2>&1 || ok=0

if [ "$ok" -eq 1 ]; then
    if [ ! -f /home/user/localeserver/main.go ]; then
        echo "Missing /home/user/localeserver/main.go"
        ok=0
    elif ! go build -o /tmp/localeserver-submission /home/user/localeserver/*.go; then
        echo "The submitted Go source did not build"
        ok=0
    fi
fi

if [ "$ok" -eq 1 ]; then
    # Stop whichever processes own the two required listening sockets so the
    # verifier can execute and test the submitted Go artifact itself.
    python3 << 'KILL_EOF'
import os
import signal
import time

ports = {8080, 9000}
inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                port = int(fields[1].split(":")[1], 16)
                state = fields[3]
                if port in ports and state == "0A":
                    inodes.add(fields[9])
    except FileNotFoundError:
        pass

victims = set()
for name in os.listdir("/proc"):
    if not name.isdigit() or int(name) == os.getpid():
        continue
    fd_dir = f"/proc/{name}/fd"
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                victims.add(int(name))
                break
    except OSError:
        pass

for pid in victims:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
time.sleep(0.4)
for pid in victims:
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
KILL_EOF

    (cd /home/user/localeserver && exec /tmp/localeserver-submission >/tmp/localeserver-verifier.log 2>&1) &
    server_pid=$!
    PHASE=restarted python3 -m pytest /tmp/test_localeserver.py -x --tb=short 2>&1 || ok=0
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
fi

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
