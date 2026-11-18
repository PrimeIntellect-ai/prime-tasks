#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import secrets
import stat
import subprocess
import tempfile
import urllib.error
import urllib.request

import pytest

BINARY = "/home/user/app/verifier/target/release/verifier"
GATEWAY = "http://127.0.0.1:8080/submit"
SENT_CLEAN = []
SENT_EVIL = []


def run_verifier(payload):
    with tempfile.NamedTemporaryFile(mode="w", prefix="mobiledep_", suffix=".manifest", delete=False) as f:
        f.write(payload)
        path = f.name
    try:
        return subprocess.run([BINARY, path], capture_output=True, timeout=5).returncode
    finally:
        os.unlink(path)


def submit(payload):
    req = urllib.request.Request(GATEWAY, data=payload.encode(), method="POST")
    req.add_header("Content-Type", "text/plain")
    try:
        response = urllib.request.urlopen(req, timeout=5)
        return response.status
    except urllib.error.HTTPError as e:
        return e.code


def manifest(app, constraint, resolved, package="pkg", version="1.2.3"):
    return (
        f"APP: {app}\n"
        f"VERSION: {version}\n"
        "DEPS:\n"
        f"  - pkg: {package}, ver: {constraint}, resolved: {resolved}\n"
        "END\n"
    )


def generated_semver_cases(count=20):
    clean = []
    evil = []
    nonce = secrets.token_hex(8)
    for i in range(count):
        major = 1 + secrets.randbelow(30)
        minor = secrets.randbelow(30)
        patch = secrets.randbelow(30)
        app = f"Build{nonce}_{i}"
        package = f"lib{nonce}_{i}"

        if i % 3 == 0:
            constraint = f">={major}.{minor}.{patch}"
            good = f"{major}.{minor}.{patch + secrets.randbelow(10)}"
            bad = f"{major - 1}.999.999"
        elif i % 3 == 1:
            constraint = f"^{major}.{minor}.{patch}"
            good = f"{major}.{minor}.{patch + secrets.randbelow(10)}"
            bad = f"{major + 1}.0.0"
        else:
            constraint = f"^0.{minor}.{patch}"
            good = f"0.{minor}.{patch + secrets.randbelow(10)}"
            bad = f"0.{minor + 1}.0"

        clean.append(manifest(app, constraint, good, package))
        evil.append(manifest(app, constraint, bad, package))
    return clean, evil


def test_rust_verifier_binary_exists():
    assert os.path.isfile(BINARY), f"Rust verifier binary not found at {BINARY}. Did you compile with --release?"
    assert os.access(BINARY, os.X_OK), f"Rust verifier binary at {BINARY} is not executable."


def test_adversarial_corpus():
    clean_dir = "/home/user/corpora/clean/"
    evil_dir = "/home/user/corpora/evil/"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    failed_clean = []
    for f in clean_files:
        result = subprocess.run([BINARY, f], capture_output=True)
        if result.returncode != 0:
            failed_clean.append(os.path.basename(f))

    failed_evil = []
    for f in evil_files:
        result = subprocess.run([BINARY, f], capture_output=True)
        if result.returncode == 0:
            failed_evil.append(os.path.basename(f))

    error_msgs = []
    if failed_clean:
        error_msgs.append(f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_clean)}")
    if failed_evil:
        error_msgs.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed: {', '.join(failed_evil)}")

    assert not error_msgs, " | ".join(error_msgs)


def test_generated_state_machine_and_semver_cases():
    nonce = secrets.token_hex(10)
    clean, evil = generated_semver_cases(24)
    clean.extend([
        f"APP: EmptyDeps{nonce}\nVERSION: 0.0.0\nDEPS:\nEND\n",
        manifest(f"Numeric{nonce}", ">=2.10.9", "10.0.0"),
        manifest(f"CaretBelow{nonce}", "^3.4.5", "3.999.999"),
        manifest(f"ZeroCaret{nonce}", "^0.4.5", "0.4.999"),
    ])

    base = manifest(f"Shape{nonce}", ">=1.2.3", "1.2.3")
    evil.extend([
        f"VERSION: 1.2.3\nAPP: Shape{nonce}\nDEPS:\nEND\n",
        f"APP: Shape{nonce}\nDEPS:\nVERSION: 1.2.3\nEND\n",
        f"APP: Shape{nonce}\nVERSION: 1.2.3\nEND\n",
        f"APP: Shape{nonce}\nVERSION: 1.2.3\nDEPS:\n",
        base + "EXTRA\n",
        f"APP: Shape{nonce}\nVERSION: 1.2.3\nDEPS:\n\nEND\n",
        f"APP: Shape{nonce}\nVERSION: 1.2.3\nDEPS:\n - pkg: x, ver: >=1.0.0, resolved: 1.0.0\nEND\n",
        f"APP: Shape{nonce}\nVERSION: 1.2.3\nDEPS:\n  - pkg: x, ver: >1.0.0, resolved: 2.0.0\nEND\n",
        f"APP: Shape{nonce}\nVERSION: 1.2.3\nDEPS:\n  - pkg: x, ver: >=1.0, resolved: 2.0.0\nEND\n",
        f"APP: Shape{nonce}\nVERSION: 1.2.3\nDEPS:\n  - pkg: x, ver: >=1.0.0, resolved: 1.0\nEND\n",
        f"APP: Shape{nonce}\nVERSION: 1.2\nDEPS:\nEND\n",
        f"APP: Shape{nonce}\nVERSION: 1.2.3\nDEPS:\nEND\n  - pkg: x, ver: >=1.0.0, resolved: 1.0.0\n",
        manifest(f"Upper{nonce}", "^7.8.9", "8.0.0"),
        manifest(f"ZeroUpper{nonce}", "^0.8.9", "0.9.0"),
    ])

    for payload in clean:
        assert run_verifier(payload) == 0, f"Generated valid manifest was rejected:\n{payload}"
    for payload in evil:
        assert run_verifier(payload) == 1, f"Generated invalid manifest was not rejected with exit 1:\n{payload}"


def test_gateway_actually_invokes_binary_on_temp_file():
    backup = BINARY + ".pytest-backup"
    marker = "/tmp/gateway_verifier_called"
    captured = "/tmp/gateway_verifier_payload"
    mode = "/tmp/gateway_verifier_mode"
    token = secrets.token_hex(16)
    accepted_probe = f"not a manifest {token}\n"
    rejected_probe = f"APP: Probe{token}\nVERSION: 1.0.0\nDEPS:\nEND\n"

    for path in (marker, captured, mode, backup):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    os.replace(BINARY, backup)
    try:
        script = f'''#!/bin/sh
printf '%s' "$1" > {marker}
cat "$1" > {captured}
exit "$(cat {mode})"
'''
        with open(BINARY, "w") as f:
            f.write(script)
        os.chmod(BINARY, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR | stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)

        with open(mode, "w") as f:
            f.write("0")
        assert submit(accepted_probe) == 200
        assert os.path.isfile(marker), "Gateway did not execute the verifier binary"
        with open(marker) as f:
            temp_path = f.read()
        assert temp_path and temp_path != BINARY, "Gateway did not pass a temporary manifest path"
        with open(captured) as f:
            assert f.read() == accepted_probe, "Gateway did not write the request body to the file passed to the verifier"

        with open(mode, "w") as f:
            f.write("1")
        assert submit(rejected_probe) == 400, "Gateway did not map verifier exit 1 to HTTP 400"
        with open(captured) as f:
            assert f.read() == rejected_probe
    finally:
        try:
            os.unlink(BINARY)
        except FileNotFoundError:
            pass
        os.replace(backup, BINARY)
        subprocess.run(["redis-cli", "DEL", "valid_builds"], capture_output=True)


def test_gateway_integration():
    clean_dir = "/home/user/corpora/clean/"
    evil_dir = "/home/user/corpora/evil/"
    subprocess.run(["redis-cli", "DEL", "valid_builds"], check=True, capture_output=True)

    clean_files = sorted([os.path.join(clean_dir, f) for f in os.listdir(clean_dir)])[:5]
    evil_files = sorted([os.path.join(evil_dir, f) for f in os.listdir(evil_dir)])[:5]

    for f in clean_files:
        with open(f, "rb") as file:
            data = file.read()
        req = urllib.request.Request(GATEWAY, data=data, method="POST")
        req.add_header("Content-Type", "text/plain")
        try:
            response = urllib.request.urlopen(req, timeout=5)
            assert response.status == 200, f"Expected HTTP 200 for clean file {f}, got {response.status}"
            SENT_CLEAN.append(data.decode())
        except urllib.error.HTTPError as e:
            pytest.fail(f"Expected HTTP 200 for clean file {f}, but got HTTP {e.code}")
        except Exception as e:
            pytest.fail(f"Failed to connect to gateway for clean file {f}: {e}")

    for f in evil_files:
        with open(f, "rb") as file:
            data = file.read()
        req = urllib.request.Request(GATEWAY, data=data, method="POST")
        req.add_header("Content-Type", "text/plain")
        try:
            response = urllib.request.urlopen(req, timeout=5)
            pytest.fail(f"Expected HTTP 400 for evil file {f}, but got HTTP {response.status}")
        except urllib.error.HTTPError as e:
            assert e.code == 400, f"Expected HTTP 400 for evil file {f}, got {e.code}"
            SENT_EVIL.append(data.decode())
        except Exception as e:
            pytest.fail(f"Failed to connect to gateway for evil file {f}: {e}")

    generated_clean, generated_evil = generated_semver_cases(9)
    generated_evil.extend([
        f"APP: Gateway{secrets.token_hex(8)}\nVERSION: 1.0.0\nEND\n",
        f"APP: Gateway{secrets.token_hex(8)}\nVERSION: 1.0.0\nDEPS:\nEND\nEXTRA\n",
    ])

    for payload in generated_clean:
        assert submit(payload) == 200, f"Gateway rejected generated valid payload:\n{payload}"
        SENT_CLEAN.append(payload)
    for payload in generated_evil:
        assert submit(payload) == 400, f"Gateway accepted generated invalid payload:\n{payload}"
        SENT_EVIL.append(payload)


def test_redis_integration():
    try:
        result = subprocess.run(["redis-cli", "LLEN", "valid_builds"], capture_output=True, text=True, check=True)
        count = int(result.stdout.strip())
        assert count >= 5, f"Expected at least 5 items in valid_builds Redis list, got {count}"

        result = subprocess.run(["redis-cli", "--raw", "LRANGE", "valid_builds", "0", "-1"], capture_output=True, text=True, check=True)
        entries = result.stdout.splitlines()
        expected = [payload.rstrip("\n") for payload in SENT_CLEAN]
        rejected = {payload.rstrip("\n") for payload in SENT_EVIL}
        assert collections.Counter(entries) == collections.Counter(expected), "Redis must contain exactly the accepted manifest texts"
        assert rejected.isdisjoint(entries), "A rejected manifest was pushed to Redis"
    except Exception as e:
        pytest.fail(f"Failed to check Redis: {e}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
