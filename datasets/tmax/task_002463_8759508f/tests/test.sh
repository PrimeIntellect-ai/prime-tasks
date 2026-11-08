#!/bin/bash
mkdir -p /logs/verifier
# Default to failure so every verifier exit path leaves a reward.
echo "0" > /logs/verifier/reward.txt

cat << 'TEST_EOF' > /tmp/test_final_state.py
import bz2
import gzip
import lzma
import os
import secrets
import shutil
import stat
import subprocess
import time
import urllib.error
import urllib.request

import pytest

ARTIFACTS_DIR = "/home/user/artifacts"
INCOMING_DIR = "/home/user/incoming"
SCRIPT = "/home/user/curate.sh"
STATE = {}


def _write_input(name, author, raw):
    hex_lines = [raw[i:i + 32].hex() for i in range(0, len(raw), 32)]
    chunk_size = 11000
    for index, start in enumerate(range(0, len(hex_lines), chunk_size), 1):
        path = os.path.join(INCOMING_DIR, f"{name}.part{index:02d}")
        with open(path, "w", encoding="ascii") as handle:
            handle.write("\n".join(hex_lines[start:start + chunk_size]) + "\n")

    with open(os.path.join(INCOMING_DIR, f"{name}.meta"), "wb") as handle:
        handle.write(f"Author: {author}\n".encode("utf-16le"))
    open(os.path.join(INCOMING_DIR, f"{name}.done"), "wb").close()


def _decompress(path):
    if path.endswith(".xz"):
        with lzma.open(path, "rb") as handle:
            return handle.read()
    if path.endswith(".gz"):
        with gzip.open(path, "rb") as handle:
            return handle.read()
    if path.endswith(".bz2"):
        with bz2.open(path, "rb") as handle:
            return handle.read()
    raise AssertionError(f"Unsupported compressed artifact: {path}")


@pytest.fixture(scope="session", autouse=True)
def run_submission():
    assert os.path.exists(SCRIPT), f"Required script {SCRIPT} does not exist"
    assert not os.path.islink(SCRIPT), f"{SCRIPT} must be a regular script, not a symlink"
    assert stat.S_ISREG(os.stat(SCRIPT).st_mode), f"{SCRIPT} is not a regular file"

    os.makedirs(INCOMING_DIR, exist_ok=True)
    os.makedirs(ARTIFACTS_DIR, exist_ok=True)
    for directory in (INCOMING_DIR, ARTIFACTS_DIR):
        for entry in os.listdir(directory):
            path = os.path.join(directory, entry)
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)

    # Use full-sized but compressible telemetry. Each artifact contains a fresh,
    # unpredictable 16 KiB block repeated to 1 MiB, so lossless compression can
    # meet the stated threshold while the verifier can check exact recovery.
    probe_name = "probe_" + secrets.token_hex(6)
    probe_author = "Verifier " + secrets.token_hex(8)
    specs = {
        "alpha": "Dr. Turing",
        "beta": "Dr. Lovelace",
        probe_name: probe_author,
    }
    expected_raw = {}
    for name, author in specs.items():
        block = os.urandom(16 * 1024)
        raw = block * 64
        expected_raw[name] = raw
        _write_input(name, author, raw)

    STATE["authors"] = specs
    STATE["raw"] = expected_raw

    # Remove prior service state so the submitted script must start and populate
    # the required services during this verification run.
    subprocess.run(["pkill", "-9", "nginx"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-9", "redis-server"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for path in ("/tmp/nginx.pid", "/var/lib/redis/dump.rdb"):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
    shutil.rmtree("/var/lib/redis/appendonlydir", ignore_errors=True)
    time.sleep(0.2)

    try:
        result = subprocess.run(
            ["bash", SCRIPT], capture_output=True, text=True, timeout=90
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{SCRIPT} did not complete within 90 seconds")
    assert result.returncode == 0, (
        f"{SCRIPT} failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_redis_metadata():
    """Check the original metadata assertions and a runtime-generated artifact."""
    expected = STATE["authors"]

    cmd_alpha = ["redis-cli", "get", "meta:author:alpha"]
    res_alpha = subprocess.run(cmd_alpha, capture_output=True, text=True)
    assert res_alpha.returncode == 0, "Failed to run redis-cli"
    alpha_val = res_alpha.stdout.strip()
    assert alpha_val == "Dr. Turing", f"Incorrect Redis alpha metadata. Expected 'Dr. Turing', got '{alpha_val}'"

    cmd_beta = ["redis-cli", "get", "meta:author:beta"]
    res_beta = subprocess.run(cmd_beta, capture_output=True, text=True)
    assert res_beta.returncode == 0, "Failed to run redis-cli"
    beta_val = res_beta.stdout.strip()
    assert beta_val == "Dr. Lovelace", f"Incorrect Redis beta metadata. Expected 'Dr. Lovelace', got '{beta_val}'"

    for name, author in expected.items():
        result = subprocess.run(
            ["redis-cli", "get", f"meta:author:{name}"],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, f"Failed to query Redis metadata for {name}"
        assert result.stdout.strip() == author, f"Incorrect Redis metadata for {name}"


def test_artifact_contents():
    """Decompress every required artifact and compare it with its input chunks."""
    assert os.path.exists(ARTIFACTS_DIR), f"Directory {ARTIFACTS_DIR} does not exist"
    files = [
        f for f in os.listdir(ARTIFACTS_DIR)
        if os.path.isfile(os.path.join(ARTIFACTS_DIR, f))
    ]

    selected = {}
    for name, expected in STATE["raw"].items():
        candidates = [
            f"{name}.bin.xz",
            f"{name}.bin.gz",
            f"{name}.bin.bz2",
        ]
        present = [f for f in candidates if f in files]
        assert len(present) == 1, (
            f"Expected exactly one supported compressed artifact for {name}; found {present}"
        )
        path = os.path.join(ARTIFACTS_DIR, present[0])
        try:
            decoded = _decompress(path)
        except Exception as exc:
            pytest.fail(f"Could not decompress {present[0]}: {exc}")
        assert decoded == expected, (
            f"Decompressed data for {name} does not match the numerically merged hex chunks"
        )
        selected[name] = present[0]
    STATE["artifact_files"] = selected


def test_artifacts_size():
    """Check that the total size of the artifacts directory is under the threshold."""
    assert os.path.exists(ARTIFACTS_DIR), f"Directory {ARTIFACTS_DIR} does not exist"

    size_cmd = subprocess.run(['du', '-sb', ARTIFACTS_DIR], capture_output=True, text=True)
    assert size_cmd.returncode == 0, "Failed to run du command"

    total_size = int(size_cmd.stdout.split()[0])
    threshold = 850000

    assert total_size <= threshold, f"Artifacts too large: {total_size} bytes > {threshold} bytes. Did you convert hex to binary before compressing?"
    assert total_size > 4096, f"Artifacts directory size ({total_size} bytes) is suspiciously small, likely empty."


def test_nginx_serving():
    """Check that Nginx serves all generated files and the verified artifacts exactly."""
    assert os.path.exists(ARTIFACTS_DIR), f"Directory {ARTIFACTS_DIR} does not exist"

    files = [f for f in os.listdir(ARTIFACTS_DIR) if os.path.isfile(os.path.join(ARTIFACTS_DIR, f))]
    assert len(files) > 0, "No files found in artifacts directory to serve"

    for filename in files:
        url = f"http://127.0.0.1:8080/{filename}"
        try:
            with urllib.request.urlopen(urllib.request.Request(url), timeout=5) as response:
                assert response.status == 200, f"Failed to fetch {filename} from Nginx (status {response.status})"
                content = response.read()
                assert len(content) > 0, f"File {filename} served by Nginx is empty"
                with open(os.path.join(ARTIFACTS_DIR, filename), "rb") as handle:
                    assert content == handle.read(), f"Nginx did not serve the on-disk contents of {filename}"
        except urllib.error.URLError as exc:
            pytest.fail(f"Failed to fetch {filename} from Nginx at {url}: {exc}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
