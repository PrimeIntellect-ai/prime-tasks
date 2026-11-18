#!/bin/bash
set -u
mkdir -p /logs/verifier

LEGACY=/app/migrator_legacy
HIDDEN=/app/migrator_legacy.verifier-hidden

# Recover cleanly if a previous verifier invocation was interrupted.
if [ ! -e "$LEGACY" ] && [ -e "$HIDDEN" ]; then
    mv "$HIDDEN" "$LEGACY"
fi

restore_legacy() {
    if [ -e "$HIDDEN" ] && [ ! -e "$LEGACY" ]; then
        mv "$HIDDEN" "$LEGACY"
        chmod +x "$LEGACY" 2>/dev/null || true
    fi
}
trap restore_legacy EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import shutil
import string
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

import pytest

EVIL_CORPUS_DIR = "/app/corpus/evil"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
URL = "http://127.0.0.1:8000/api/v2/migrate"
LEGACY_BINARY = "/app/migrator_legacy"
HIDDEN_LEGACY = "/app/migrator_legacy.verifier-hidden"
SERVER_SCRIPT = "/home/user/server.sh"


def send_post(url, data):
    req = urllib.request.Request(url, data=data, method="POST")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status, response.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8")
    except urllib.error.URLError as e:
        return None, str(e)
    except Exception as e:
        return None, str(e)


def get_legacy_output(data):
    result = subprocess.run(
        [LEGACY_BINARY], input=data, capture_output=True, timeout=5
    )
    if result.returncode != 0:
        return None
    return result.stdout.decode("utf-8")


def expected_migration(payload):
    uid = int(payload.get("uid", 0))
    cmd = str(payload.get("cmd", ""))
    params = str(payload.get("params", ""))
    return {
        "user": f"U{uid:04d}",
        "command": cmd.upper(),
        "config": dict(urllib.parse.parse_qsl(params)),
    }


def test_server_artifact():
    assert os.path.isfile(SERVER_SCRIPT), f"Missing {SERVER_SCRIPT}"
    assert os.access(SERVER_SCRIPT, os.X_OK), f"{SERVER_SCRIPT} is not executable"
    with open(SERVER_SCRIPT, "rb") as f:
        first_line = f.readline(256).decode("utf-8", "replace")
    assert first_line.startswith("#!") and "bash" in first_line, \
        f"{SERVER_SCRIPT} must be an executable Bash script"


def test_server_running():
    status, body = send_post(URL, b"{}")
    assert status is not None, (
        f"Server is not reachable or failed to respond at {URL}. Error: {body}"
    )


def test_evil_corpus():
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.json"))
    assert evil_files, f"No files found in {EVIL_CORPUS_DIR}"

    bypassed = []
    for file_path in sorted(evil_files):
        with open(file_path, "rb") as f:
            data = f.read()

        status, body = send_post(URL, data)
        if status != 403 or body.strip() != "REJECTED":
            bypassed.append(os.path.basename(file_path))

    if bypassed:
        pytest.fail(
            f"{len(bypassed)} of {len(evil_files)} evil bypassed. "
            f"Offending files: {', '.join(bypassed)}"
        )


def test_clean_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.json"))
    assert clean_files, f"No files found in {CLEAN_CORPUS_DIR}"

    modified = []
    for file_path in sorted(clean_files):
        with open(file_path, "rb") as f:
            data = f.read()

        expected_output_raw = get_legacy_output(data)
        assert expected_output_raw is not None, f"Legacy binary failed on {file_path}"
        expected_json = json.loads(expected_output_raw)

        status, body = send_post(URL, data)
        if status != 200:
            modified.append(os.path.basename(file_path))
            continue

        try:
            actual_json = json.loads(body)
            if actual_json != expected_json:
                modified.append(os.path.basename(file_path))
        except json.JSONDecodeError:
            modified.append(os.path.basename(file_path))

    if modified:
        pytest.fail(
            f"{len(modified)} of {len(clean_files)} clean modified. "
            f"Offending files: {', '.join(modified)}"
        )


def test_restart_without_legacy_binary():
    # Stop the submitted server, make the legacy executable unavailable, and
    # launch the submitted artifact afresh. A native implementation must still work.
    subprocess.run(
        ["pkill", "-TERM", "-f", "/home/user/server.sh"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    time.sleep(0.3)

    if shutil.which("fuser"):
        subprocess.run(
            ["fuser", "-k", "8000/tcp"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    else:
        for name in ("socat", "nc", "netcat"):
            subprocess.run(
                ["pkill", "-TERM", name],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
    time.sleep(0.3)

    assert os.path.exists(LEGACY_BINARY), "Legacy binary unexpectedly missing"
    assert not os.path.exists(HIDDEN_LEGACY), "Verifier hidden path already exists"
    os.rename(LEGACY_BINARY, HIDDEN_LEGACY)

    subprocess.Popen(
        [SERVER_SCRIPT],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
        close_fds=True,
    )

    deadline = time.time() + 8
    last_error = "no response"
    while time.time() < deadline:
        status, body = send_post(URL, b"{}")
        if status is not None:
            assert status == 200, f"Restarted server returned HTTP {status}: {body}"
            assert json.loads(body) == expected_migration({})
            return
        last_error = body
        time.sleep(0.2)
    pytest.fail(f"Server did not restart without the legacy binary: {last_error}")


def test_randomized_unseen_clean_and_evil_payloads():
    rng = random.SystemRandom()
    alphabet = string.ascii_lowercase

    clean_payloads = []
    for _ in range(18):
        uid = rng.randrange(1, 500000)
        cmd = "".join(rng.choice(alphabet) for _ in range(rng.randrange(4, 13)))
        pairs = []
        for _ in range(rng.randrange(1, 5)):
            key = "k" + "".join(rng.choice(alphabet) for _ in range(7))
            value = "v" + "".join(
                rng.choice(alphabet + string.digits + "_-")
                for _ in range(rng.randrange(5, 15))
            )
            pairs.append((key, value))
        clean_payloads.append(
            {"uid": uid, "cmd": cmd, "params": urllib.parse.urlencode(pairs)}
        )

    for payload in clean_payloads:
        # Random separators ensure these are not byte-identical fixed fixtures.
        separators = (",", ":") if rng.randrange(2) else (", ", ": ")
        data = json.dumps(payload, separators=separators).encode("utf-8")
        status, body = send_post(URL, data)
        assert status == 200, f"Unseen clean payload returned HTTP {status}: {payload}"
        try:
            actual = json.loads(body)
        except json.JSONDecodeError as exc:
            pytest.fail(f"Unseen clean payload returned invalid JSON: {exc}: {body!r}")
        assert actual == expected_migration(payload), (
            f"Wrong migration for unseen clean payload {payload}: {actual}"
        )

    metacharacters = [";", "|", "`"]
    evil_payloads = []
    for i in range(18):
        base = dict(clean_payloads[i])
        if i % 2 == 0:
            pos = rng.randrange(len(base["cmd"]) + 1)
            base["cmd"] = base["cmd"][:pos] + "!" + base["cmd"][pos:]
        else:
            marker = rng.choice(metacharacters)
            suffix = "".join(rng.choice(alphabet) for _ in range(7))
            base["params"] += marker + suffix
        evil_payloads.append(base)

    for payload in evil_payloads:
        data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        status, body = send_post(URL, data)
        assert status == 403, f"Unseen evil payload returned HTTP {status}: {payload}"
        assert body == "REJECTED", (
            f"Unseen evil payload did not return exact body REJECTED: {body!r}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
