#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import subprocess
import tempfile
import urllib.request
import urllib.error
import binascii
import struct
import time
import pytest


def test_configs_fixed():
    upload_config_path = "/home/user/config/upload_config.json"
    assert os.path.exists(upload_config_path), f"Missing {upload_config_path}"
    with open(upload_config_path, "r") as f:
        u_conf = json.load(f)
    assert u_conf.get("upload_dir") == "/home/user/uploads/", "upload_config.json does not have the correct upload_dir"

    stats_config_path = "/home/user/config/stats_config.json"
    assert os.path.exists(stats_config_path), f"Missing {stats_config_path}"
    with open(stats_config_path, "r") as f:
        s_conf = json.load(f)
    assert s_conf.get("redis_port") == 6379, "stats_config.json does not have the correct redis_port"


def make_cbf(payload=b"payload", version=1, flags=0, magic=b"BKUP", declared_size=None, crc=None, suffix=b""):
    if declared_size is None:
        declared_size = len(payload)
    if crc is None:
        crc = binascii.crc32(payload) & 0xffffffff
    return (magic + struct.pack("<H", version) + struct.pack("<H", flags) +
            struct.pack("<I", declared_size) + payload + struct.pack("<I", crc) + suffix)


def run_filter(files, config=None):
    binary_path = "/home/user/cbf_filter"
    assert os.path.isfile(binary_path), "cbf_filter binary is missing"
    assert os.access(binary_path, os.X_OK), "cbf_filter is not executable"
    with tempfile.TemporaryDirectory() as root:
        input_dir = os.path.join(root, "input")
        output_dir = os.path.join(root, "output")
        os.makedirs(input_dir)
        os.makedirs(output_dir)
        for relpath, data in files.items():
            path = os.path.join(input_dir, relpath)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as f:
                f.write(data)
        config_path = os.path.join(root, "config.json")
        if config is None:
            config = {"allowed_versions": [1, 2], "max_payload_size": 64}
        with open(config_path, "w") as f:
            json.dump(config, f)
        subprocess.run([binary_path, config_path, input_dir, output_dir], check=True, timeout=15)
        result = {}
        for name in os.listdir(output_dir):
            path = os.path.join(output_dir, name)
            assert os.path.isfile(path), f"Unexpected non-file output: {name}"
            with open(path, "rb") as f:
                result[name] = f.read()
        return result


def test_adversarial_corpus():
    # Retain checks against the supplied corpus.
    binary_path = "/home/user/cbf_filter"
    config_path = "/home/user/config/filter_config.json"
    assert os.path.isfile(binary_path), "cbf_filter binary is missing"
    assert os.access(binary_path, os.X_OK), "cbf_filter is not executable"

    with tempfile.TemporaryDirectory() as out_dir:
        subprocess.run([binary_path, config_path, "/app/corpus/clean", out_dir], check=True, timeout=15)
        clean_files = os.listdir("/app/corpus/clean")
        out_files = os.listdir(out_dir)
        failed_clean = [cf for cf in clean_files if f"{cf}.verified" not in out_files]

    with tempfile.TemporaryDirectory() as out_dir:
        subprocess.run([binary_path, config_path, "/app/corpus/evil", out_dir], check=True, timeout=15)
        evil_files = os.listdir("/app/corpus/evil")
        out_files = os.listdir(out_dir)
        failed_evil = [ef for ef in evil_files if f"{ef}.verified" in out_files]

    error_msg = f"{len(failed_evil)} of {len(evil_files)} evil bypassed: {failed_evil}, {len(failed_clean)} of {len(clean_files)} clean modified/dropped: {failed_clean}"
    assert not failed_clean and not failed_evil, error_msg

    # Generated cases exercise every stated validation rule, exact output bytes,
    # recursive traversal, flattening, and configuration-dependent limits.
    valid_a = make_cbf(b"generated-valid-A", version=1, flags=0xffff)
    valid_b = make_cbf(bytes(range(32)), version=2)
    empty_valid = make_cbf(b"", version=1)
    cases = {
        "nested/deeper/valid-a.bin": valid_a,
        "valid-b.dat": valid_b,
        "empty.cbf": empty_valid,
        "bad-magic": make_cbf(b"x", magic=b"NOPE"),
        "bad-version": make_cbf(b"x", version=3),
        "bad-crc": make_cbf(b"crc", crc=0),
        "trailing": make_cbf(b"x", suffix=b"extra"),
        "truncated-header": b"BKUP\x01",
        "truncated-payload": make_cbf(b"abc")[:-5],
        "declared-too-small": make_cbf(b"abc", declared_size=2),
        "declared-too-large": make_cbf(b"abc", declared_size=4),
        "over-limit": make_cbf(b"Z" * 65),
    }
    outputs = run_filter(cases)
    expected = {
        "valid-a.bin.verified": valid_a,
        "valid-b.dat.verified": valid_b,
        "empty.cbf.verified": empty_valid,
    }
    assert outputs == expected, f"Generated corpus mismatch: expected {sorted(expected)}, got {sorted(outputs)}"

    # Ensure allowed_versions and max_payload_size are actually read from the supplied config.
    v7 = make_cbf(b"12345", version=7)
    v1 = make_cbf(b"1234", version=1)
    outputs = run_filter(
        {"allowed.cbf": v7, "wrong-version.cbf": v1, "too-big.cbf": make_cbf(b"123456", version=7)},
        {"allowed_versions": [7], "max_payload_size": 5},
    )
    assert outputs == {"allowed.cbf.verified": v7}


def create_valid_cbf(payload=b"Test Payload Data"):
    return make_cbf(payload=payload, version=1)


def wait_for_json(url, timeout=10):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=2) as response:
                return json.loads(response.read().decode("utf-8"))
        except Exception as e:
            last_error = e
            time.sleep(0.25)
    raise AssertionError(f"Failed to query {url}: {last_error}")


def test_e2e_flow():
    script_path = "/home/user/process_backups.sh"
    assert os.path.exists(script_path), f"Missing {script_path}"
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable"

    # Start the supplied multi-service stack and verify both HTTP services.
    subprocess.run(["/home/user/start_services.sh"], check=True, timeout=15)
    deadline = time.time() + 10
    while time.time() < deadline:
        if subprocess.run(["redis-cli", "ping"], capture_output=True, text=True).stdout.strip() == "PONG":
            break
        time.sleep(0.25)
    else:
        pytest.fail("Redis did not start on port 6379")

    # upload_api must accept an upload into the configured directory.
    upload_name = "api_probe.dat"
    upload_path = os.path.join("/home/user/uploads", upload_name)
    if os.path.exists(upload_path):
        os.remove(upload_path)
    body_data = create_valid_cbf(b"uploaded through API")
    boundary = "----cbfVerifierBoundary"
    body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{upload_name}\"\r\n"
            "Content-Type: application/octet-stream\r\n\r\n").encode() + body_data + f"\r\n--{boundary}--\r\n".encode()
    req = urllib.request.Request("http://localhost:8080/upload", data=body, method="POST",
                                 headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})
    deadline = time.time() + 10
    while True:
        try:
            with urllib.request.urlopen(req, timeout=2) as response:
                assert response.status == 200
            break
        except Exception as e:
            if time.time() >= deadline:
                pytest.fail(f"upload_api did not accept upload: {e}")
            time.sleep(0.25)
    assert os.path.isfile(upload_path) and open(upload_path, "rb").read() == body_data

    subprocess.run(["redis-cli", "del", "verified_backup_count"], check=True)
    verified_dir = "/home/user/verified_backups"
    os.makedirs(verified_dir, exist_ok=True)
    for f in os.listdir(verified_dir):
        path = os.path.join(verified_dir, f)
        if os.path.isfile(path) or os.path.islink(path):
            os.remove(path)

    # Isolate this count from any pre-existing uploads while retaining the API probe.
    uploads_dir = "/home/user/uploads"
    for f in os.listdir(uploads_dir):
        path = os.path.join(uploads_dir, f)
        if f != upload_name and (os.path.isfile(path) or os.path.islink(path)):
            os.remove(path)
    test_file_path = os.path.join(uploads_dir, "e2e_test.dat")
    test_data = create_valid_cbf()
    with open(test_file_path, "wb") as f:
        f.write(test_data)

    subprocess.run([script_path], check=True, timeout=15, cwd="/home/user")
    expected_verified = os.path.join(verified_dir, "e2e_test.dat.verified")
    assert os.path.isfile(expected_verified), "process_backups.sh did not produce the verified file"
    assert open(expected_verified, "rb").read() == test_data

    # stats_api defines /stats (not /); require the exact count exposed through it.
    data = wait_for_json("http://localhost:8081/stats")
    assert data.get("verified_backup_count") == 2, f"Stats API returned the wrong count: {data}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
