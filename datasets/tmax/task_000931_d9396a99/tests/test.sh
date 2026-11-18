#!/bin/bash
set -u
mkdir -p /logs/verifier

APP=/home/user/app
GW=$APP/services/python_gateway
RUST=$APP/services/rust_signer
ok=1
RUN_PID=""

cleanup() {
    if [ -n "$RUN_PID" ]; then
        kill -- -"$RUN_PID" 2>/dev/null || true
    fi
    pkill -x rust_signer 2>/dev/null || true
    pkill -f 'python3 app.py' 2>/dev/null || true
    redis-cli shutdown nosave >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Do not allow an already-running substitute to satisfy the integration tests.
redis-cli shutdown nosave >/dev/null 2>&1 || true
pkill -x rust_signer 2>/dev/null || true
pkill -f 'python3 app.py' 2>/dev/null || true
if command -v fuser >/dev/null 2>&1; then
    fuser -k 50051/tcp >/dev/null 2>&1 || true
    fuser -k 8080/tcp >/dev/null 2>&1 || true
fi
sleep 1

# The requested Rust artifact must actually compile.
if ! (cd "$RUST" && cargo build); then
    ok=0
fi

# Python protobuf bindings must exist in the requested directory.
for f in "$GW/manifest_pb2.py" "$GW/manifest_pb2_grpc.py"; do
    if [ ! -f "$f" ]; then
        echo "Missing protobuf binding: $f" >&2
        ok=0
    fi
done

if [ "$ok" -eq 1 ]; then
    setsid "$APP/start.sh" >/tmp/app-start.log 2>&1 &
    RUN_PID=$!
fi

cat <<'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import importlib
import json
import os
import secrets
import subprocess
import sys
import time
import urllib.error
import urllib.request

import grpc
import pytest
import redis

APP = "/home/user/app"
GW = APP + "/services/python_gateway"
EVIL_DIR = APP + "/corpora/evil/"
CLEAN_DIR = APP + "/corpora/clean/"
ENDPOINT = "http://127.0.0.1:8080/validate"

sys.path.insert(0, GW)
manifest_pb2 = importlib.import_module("manifest_pb2")
manifest_pb2_grpc = importlib.import_module("manifest_pb2_grpc")
sanitizer = importlib.import_module("sanitizer")


def post_json(url, data):
    req = urllib.request.Request(
        url,
        data=json.dumps(data).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=4) as response:
            raw = response.read().decode("utf-8")
            try:
                body = json.loads(raw)
            except Exception:
                body = None
            return response.status, body
    except urllib.error.HTTPError as exc:
        try:
            body = json.loads(exc.read().decode("utf-8"))
        except Exception:
            body = None
        return exc.code, body
    except Exception:
        return None, None


def wait_for_stack():
    deadline = time.time() + 90
    while time.time() < deadline:
        status, body = post_json(ENDPOINT, {
            "app_name": "readiness",
            "version": "1",
            "command": "start",
        })
        if status == 200 and body == {"signature": "hash_readiness"}:
            return
        time.sleep(0.5)
    pytest.fail("start.sh did not launch a working integrated stack")


def test_complete_solution():
    # Verify these are bindings for the supplied schema, not placeholder modules.
    request_desc = manifest_pb2.ManifestRequest.DESCRIPTOR
    assert set(request_desc.fields_by_name) == {"app_name", "version", "command"}
    assert "Signer" in manifest_pb2.DESCRIPTOR.services_by_name
    assert hasattr(manifest_pb2_grpc, "SignerStub")
    assert hasattr(manifest_pb2_grpc, "SignerServicer")

    # Exercise the recursive sanitizer directly for every restricted substring.
    restricted = ["&&", "|", ";", "$", "../"]
    for token in restricted:
        assert sanitizer.is_safe({
            "app_name": "clean",
            "metadata": {"levels": [1, True, None, {"value": "aa" + token + "bb"}]},
        }) is False
    assert sanitizer.is_safe({
        "app_name": "safe-app",
        "nested": [{"value": "single & is okay"}, "dots/and/slashes", 7],
        "key;names;are;not;values": "clean",
    }) is True

    wait_for_stack()

    # Directly exercise the compiled Rust gRPC service and its signature result.
    channel = grpc.insecure_channel("localhost:50051")
    grpc.channel_ready_future(channel).result(timeout=10)
    stub = manifest_pb2_grpc.SignerStub(channel)
    direct_name = "direct-" + secrets.token_hex(6)
    reply = stub.SignManifest(manifest_pb2.ManifestRequest(
        app_name=direct_name, version="9.4", command="deploy"
    ), timeout=5)
    assert reply.signature == "hash_" + direct_name
    channel.close()

    # Retain the original corpus assertions.
    if not os.path.isdir(EVIL_DIR) or not os.path.isdir(CLEAN_DIR):
        pytest.fail("Corpus directories are missing.")
    evil_files = [f for f in os.listdir(EVIL_DIR) if f.endswith(".json")]
    clean_files = [f for f in os.listdir(CLEAN_DIR) if f.endswith(".json")]
    evil_bypassed = []
    clean_modified = []
    for filename in evil_files:
        with open(os.path.join(EVIL_DIR, filename), "r") as fp:
            data = json.load(fp)
        status, _ = post_json(ENDPOINT, data)
        if status != 400:
            evil_bypassed.append(filename)
    for filename in clean_files:
        with open(os.path.join(CLEAN_DIR, filename), "r") as fp:
            data = json.load(fp)
        status, _ = post_json(ENDPOINT, data)
        if status != 200:
            clean_modified.append(filename)
    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    if errors:
        pytest.fail(" | ".join(errors))

    # Exercise all restricted strings over HTTP, including recursively nested values.
    for index, token in enumerate(restricted):
        payload = {
            "app_name": "evil-" + secrets.token_hex(5),
            "version": "1",
            "command": "start",
            "metadata": {"items": [{"note": "prefix" + token + "suffix"}]},
        }
        status, _ = post_json(ENDPOINT, payload)
        assert status == 400, (index, token, status)

    # Verify a non-fixed clean request, response body, signature, and Redis cache.
    cache = redis.Redis(host="localhost", port=6379, db=0)
    clean_name = "clean-" + secrets.token_hex(8)
    cache.delete(clean_name)
    status, body = post_json(ENDPOINT, {
        "app_name": clean_name,
        "version": "2.7.1",
        "command": "rollout",
    })
    expected = "hash_" + clean_name
    assert status == 200
    assert body == {"signature": expected}
    assert cache.get(clean_name) == expected.encode()

    # Replace the signer with a verifier-controlled implementation returning an
    # unpredictable value. This proves the gateway obtains the response via gRPC
    # rather than locally fabricating the scaffold's known signature.
    subprocess.run(["pkill", "-x", "rust_signer"], check=False)
    time.sleep(1)
    challenge_name = "challenge-" + secrets.token_hex(8)
    challenge_sig = "verifier-" + secrets.token_hex(24)

    class ChallengeSigner(manifest_pb2_grpc.SignerServicer):
        def SignManifest(self, request, context):
            if (request.app_name, request.version, request.command) != (
                challenge_name, "73.5", "launch"
            ):
                context.abort(grpc.StatusCode.INVALID_ARGUMENT, "wrong protobuf fields")
            return manifest_pb2.SignResponse(signature=challenge_sig)

    server = grpc.server(concurrent.futures.ThreadPoolExecutor(max_workers=2))
    manifest_pb2_grpc.add_SignerServicer_to_server(ChallengeSigner(), server)
    assert server.add_insecure_port("[::]:50051") != 0
    server.start()
    try:
        cache.delete(challenge_name)
        deadline = time.time() + 12
        result = (None, None)
        while time.time() < deadline:
            result = post_json(ENDPOINT, {
                "app_name": challenge_name,
                "version": "73.5",
                "command": "launch",
            })
            if result[0] == 200:
                break
            time.sleep(0.4)
        assert result == (200, {"signature": challenge_sig})
        assert cache.get(challenge_name) == challenge_sig.encode()
    finally:
        server.stop(0).wait()
TEST_EOF

if [ "$ok" -eq 1 ] && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    if [ -f /tmp/app-start.log ]; then
        cat /tmp/app-start.log >&2 || true
    fi
    echo "0" > /logs/verifier/reward.txt
fi
