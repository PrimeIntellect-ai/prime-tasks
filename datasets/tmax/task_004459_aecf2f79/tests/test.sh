#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import json
import os
import signal
import stat
import subprocess
import tempfile
import time
import urllib.request
import uuid

import pytest
import redis

APP = "/home/user/app"
CLI = f"{APP}/worker/cli_test.js"
ARCHIVE = f"{APP}/archive"


def wrapped_payload(payload):
    return base64.b64encode(json.dumps(payload).encode()).decode()


def make_payload(item_id, log, checksum=None, **extra):
    payload = {
        "id": item_id,
        "log": log,
        "checksum": checksum if checksum is not None else hashlib.sha256(log.encode()).hexdigest(),
    }
    payload.update(extra)
    return payload


def test_archive_permissions():
    assert os.path.isdir(ARCHIVE), f"Archive directory missing: {ARCHIVE}"
    permissions = stat.S_IMODE(os.stat(ARCHIVE).st_mode)
    assert permissions == 0o700, f"Expected permissions 0o700 for {ARCHIVE}, got {oct(permissions)}"


def test_cli_wrapper_exists():
    assert os.path.isfile(CLI), f"CLI wrapper missing: {CLI}"


def test_adversarial_corpus():
    clean_dir = "/home/user/corpora/clean"
    evil_dir = "/home/user/corpora/evil"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith(".json")]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith(".json")]
    assert clean_files, "No clean files found."
    assert evil_files, "No evil files found."

    clean_failed = []
    for fpath in clean_files:
        result = subprocess.run(["node", CLI, fpath], capture_output=True, timeout=5)
        if result.returncode != 0:
            clean_failed.append(os.path.basename(fpath))

    evil_failed = []
    for fpath in evil_files:
        result = subprocess.run(["node", CLI, fpath], capture_output=True, timeout=5)
        if result.returncode != 1:
            evil_failed.append(os.path.basename(fpath))

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed[:5])}")
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed[:5])}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_cli_on_unpredictable_paths_and_payloads():
    nonce = uuid.uuid4().hex
    cases = [
        (make_payload(710001, f"Routine service event {nonce}"), 0),
        (make_payload(710002, f"User note {nonce}", metadata={"csp": "default-src 'self'; script-src 'self'"}), 0),
        (make_payload(710003, f"Event {nonce} <ScRiPt>alert('x')</sCrIpT>"), 1),
        (make_payload(710004, f"Query {nonce} dRoP TABLE audit_events;"), 1),
        (make_payload(710005, f"Integrity test {nonce}", checksum="0" * 64), 1),
        (make_payload(710006, f"CSP test {nonce}", metadata={"csp": "script-src 'self' https://attacker.invalid"}), 1),
        (make_payload(710007, f"Inline CSP test {nonce}", metadata={"csp": "script-src 'self' 'unsafe-inline'"}), 1),
    ]

    with tempfile.TemporaryDirectory(prefix="policy-input-") as directory:
        for index, (payload, expected) in enumerate(cases):
            path = os.path.join(directory, f"sample-{uuid.uuid4().hex}-{index}.json")
            with open(path, "w") as handle:
                json.dump(payload, handle)
            result = subprocess.run(["node", CLI, path], capture_output=True, timeout=5)
            assert result.returncode == expected, (
                f"CLI returned {result.returncode}, expected {expected} for generated case {index}; "
                f"stdout={result.stdout!r}, stderr={result.stderr!r}"
            )


@pytest.fixture(scope="module")
def running_services():
    subprocess.run(["redis-cli", "-p", "6379", "shutdown", "nosave"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-f", "/home/user/app/api/gateway.py"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-f", "/home/user/app/worker/enforcer.js"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.3)

    start = f"{APP}/start.sh"
    assert os.path.isfile(start), f"Startup script missing: {start}"
    assert os.access(start, os.X_OK), f"Startup script is not executable: {start}"
    proc = subprocess.Popen([start], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, preexec_fn=os.setsid)

    deadline = time.time() + 15
    last_error = None
    client = None
    while time.time() < deadline:
        try:
            client = redis.Redis(host="127.0.0.1", port=6379, socket_connect_timeout=1, socket_timeout=1)
            assert client.ping()
            request = urllib.request.Request("http://127.0.0.1:8080/submit", data=b"", method="POST")
            try:
                urllib.request.urlopen(request, timeout=1).close()
            except urllib.error.HTTPError as exc:
                if exc.code >= 500:
                    raise
            break
        except Exception as exc:
            last_error = exc
            time.sleep(0.25)
    else:
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
        except ProcessLookupError:
            pass
        pytest.fail(f"start.sh did not bring up Redis and the API gateway: {last_error}")

    client.delete("log_queue")
    try:
        yield client
    finally:
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
        except ProcessLookupError:
            pass
        subprocess.run(["redis-cli", "-p", "6379", "shutdown", "nosave"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def post_to_gateway(encoded):
    request = urllib.request.Request(
        "http://127.0.0.1:8080/submit",
        data=encoded.encode(),
        headers={"Content-Type": "application/octet-stream"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=3) as response:
        assert response.status == 200


def test_gateway_redis_worker_and_archive_integration(running_services):
    client = running_services
    seed = int(time.time() * 1000000) % 800000000 + 100000000
    nonce = uuid.uuid4().hex

    api_clean = make_payload(seed, f"Clean API event {nonce}")
    redis_clean = make_payload(seed + 1, f"Clean broker event {nonce}")
    api_xss = make_payload(seed + 2, f"Attack {nonce} <script>alert(1)</script>")
    redis_bad_hash = make_payload(seed + 3, f"Forged event {nonce}", checksum="badhash")
    redis_bad_csp = make_payload(
        seed + 4,
        f"CSP event {nonce}",
        metadata={"csp": "default-src 'self'; script-src https://attacker.invalid"},
    )

    payloads = [api_clean, redis_clean, api_xss, redis_bad_hash, redis_bad_csp]
    paths = {p["id"]: os.path.join(ARCHIVE, f"{p['id']}.json") for p in payloads}
    for path in paths.values():
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    post_to_gateway(wrapped_payload(api_clean))
    client.lpush("log_queue", wrapped_payload(redis_clean))
    post_to_gateway(wrapped_payload(api_xss))
    client.lpush("log_queue", wrapped_payload(redis_bad_hash))
    client.lpush("log_queue", wrapped_payload(redis_bad_csp))

    deadline = time.time() + 12
    while time.time() < deadline:
        if os.path.isfile(paths[api_clean["id"]]) and os.path.isfile(paths[redis_clean["id"]]) and client.llen("log_queue") == 0:
            break
        time.sleep(0.2)
    else:
        pytest.fail("The API/Redis/worker pipeline did not archive both generated clean messages and drain log_queue")

    time.sleep(1)
    for expected in (api_clean, redis_clean):
        with open(paths[expected["id"]]) as handle:
            archived = json.load(handle)
        assert archived.get("id") == expected["id"]
        assert archived.get("log") == expected["log"]

    for rejected in (api_xss, redis_bad_hash, redis_bad_csp):
        assert not os.path.exists(paths[rejected["id"]]), f"Rejected payload {rejected['id']} was archived"

    permissions = stat.S_IMODE(os.stat(ARCHIVE).st_mode)
    assert permissions == 0o700, f"start.sh changed archive permissions to {oct(permissions)}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
