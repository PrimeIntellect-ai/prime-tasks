#!/bin/bash
set -u
mkdir -p /logs/verifier

run_verification() {
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/rust
    export PATH=/opt/rust/bin:$PATH
    project=/home/user/deployment_validator

    test -f "$project/Cargo.toml" || return 1
    test -d "$project/src" || return 1

    # Stop the agent-started listener so the verifier can execute the submitted artifact itself.
    python3 - <<'PY' || return 1
import os, signal, time

def listeners():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    cols = line.split()
                    if len(cols) >= 10 and cols[3] == "0A":
                        local = cols[1]
                        if int(local.rsplit(":", 1)[1], 16) == 3030:
                            inodes.add(cols[9])
        except FileNotFoundError:
            pass
    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except OSError:
            pass
    return pids

for pid in listeners():
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
time.sleep(1)
for pid in listeners():
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
PY

    cd "$project" || return 1
    timeout 180 cargo test --manifest-path "$project/Cargo.toml" || return 1
    timeout 180 cargo build --manifest-path "$project/Cargo.toml" --message-format=json > /tmp/deployment_validator_build.json || return 1

    executable=$(python3 - <<'PY'
import json
project = "/home/user/deployment_validator/"
found = []
with open("/tmp/deployment_validator_build.json") as f:
    for line in f:
        try:
            item = json.loads(line)
        except json.JSONDecodeError:
            continue
        target = item.get("target", {})
        exe = item.get("executable")
        src = target.get("src_path", "")
        if exe and "bin" in target.get("kind", []) and src.startswith(project):
            found.append(exe)
if not found:
    raise SystemExit(1)
print(found[-1])
PY
    ) || return 1
    test -x "$executable" || return 1

    nohup "$executable" >/tmp/deployment_validator_server.log 2>&1 &
    server_pid=$!

    python3 - <<'PY' || return 1
import socket, time
for _ in range(100):
    try:
        with socket.create_connection(("127.0.0.1", 3030), timeout=0.2):
            raise SystemExit(0)
    except OSError:
        time.sleep(0.1)
raise SystemExit("server did not listen on 127.0.0.1:3030")
PY

    cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import urllib.error
import urllib.request

URL = "http://127.0.0.1:3030/validate"


def request_status(data):
    if not isinstance(data, bytes):
        data = json.dumps(data).encode("utf-8")
    req = urllib.request.Request(
        URL,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status
    except urllib.error.HTTPError as error:
        return error.code


def expected_status(value):
    if not isinstance(value, dict):
        return 400
    required = ("previous_version", "target_version", "pre_deploy_hook", "services")
    if any(key not in value for key in required):
        return 400
    if not all(isinstance(value[key], str) for key in required[:3]):
        return 400
    services = value["services"]
    if not isinstance(services, list) or not services:
        return 400
    for service in services:
        if not isinstance(service, dict):
            return 400
        if not isinstance(service.get("name"), str) or not isinstance(service.get("image"), str):
            return 400
    if value["target_version"] == "v2" and "exec" in value["pre_deploy_hook"]:
        return 400
    return 200


def test_status_file():
    path = "/home/user/status.txt"
    assert os.path.isfile(path), f"Status file missing at {path}"
    with open(path) as f:
        content = f.read().strip()
    assert "DONE" in content, f"Status file does not contain DONE, got: {content}"


def test_shipped_corpus_against_documented_rule():
    for directory in ("/app/corpus/clean", "/app/corpus/evil"):
        assert os.path.isdir(directory), f"Missing corpus directory at {directory}"
        files = [os.path.join(directory, name) for name in os.listdir(directory) if name.endswith(".json")]
        assert files, f"No corpus files found in {directory}"
        failures = []
        for path in files:
            with open(path, "rb") as f:
                raw = f.read()
            try:
                value = json.loads(raw)
                expected = expected_status(value)
            except Exception:
                expected = 400
            actual = request_status(raw)
            if actual != expected:
                failures.append((os.path.basename(path), expected, actual))
        assert not failures, f"Corpus responses did not match the documented rule: {failures}"


def test_fresh_general_validation_cases():
    nonce = secrets.token_hex(12)

    valid = []
    invalid = []
    for i in range(12):
        token = f"{nonce}-{i}-{secrets.token_hex(4)}"
        services = [
            {"name": f"service-{token}", "image": f"registry.invalid/{token}:latest"},
            {"name": f"worker-{token}", "image": f"registry.invalid/worker-{token}:1"},
        ]
        valid.append({
            "previous_version": "v1",
            "target_version": "v2",
            "pre_deploy_hook": f"echo preparing-{token}",
            "services": services,
        })
        # The migration constraint applies only when the target is v2.
        valid.append({
            "previous_version": "v1",
            "target_version": "v1",
            "pre_deploy_hook": f"echo {token} && exec /tmp/{token}",
            "services": services,
        })
        invalid.append({
            "previous_version": "v1",
            "target_version": "v2",
            "pre_deploy_hook": f"echo {token} && xxexecyy /tmp/{token}",
            "services": services,
        })
        invalid.append({
            "previous_version": "v2",
            "target_version": "v2",
            "pre_deploy_hook": f"exec custom-{token}.sh",
            "services": services,
        })

    base = {
        "previous_version": "v1",
        "target_version": "v2",
        "pre_deploy_hook": f"echo {nonce}",
        "services": [{"name": f"web-{nonce}", "image": f"image-{nonce}:1"}],
    }
    invalid.extend([
        {**base, "services": []},
        {**base, "services": "not-an-array"},
        {**base, "services": [{}]},
        {**base, "services": [{"name": "web"}]},
        {**base, "services": [{"name": 7, "image": "img"}]},
        {**base, "target_version": 2},
        {**base, "pre_deploy_hook": None},
        {key: value for key, value in base.items() if key != "services"},
        {key: value for key, value in base.items() if key != "pre_deploy_hook"},
    ])

    for payload in valid:
        assert expected_status(payload) == 200
        assert request_status(payload) == 200, payload
    for payload in invalid:
        assert expected_status(payload) == 400
        assert request_status(payload) == 400, payload

    malformed = [b"", b"not json", b"{", b"[]", b"null", b"42"]
    for raw in malformed:
        assert request_status(raw) == 400, raw
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
    result=$?
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
    return "$result"
}

if run_verification 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
