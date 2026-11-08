#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import secrets
import subprocess
from urllib.parse import urlencode, urlsplit

import pytest

CLI = "/app/vendored/uroute-0.5.1/uroute_cli"
PROJECT = "/app/vendored/uroute-0.5.1"
SCRIPT = "/home/user/gateway_filter.py"


@pytest.fixture(scope="session", autouse=True)
def rebuild_router():
    """Require uroute_cli to be produced by the repaired vendored build."""
    clean = subprocess.run(
        ["make", "clean"], cwd=PROJECT, capture_output=True, text=True, timeout=20
    )
    assert clean.returncode == 0, f"make clean failed:\n{clean.stdout}\n{clean.stderr}"

    # Do not allow a pre-created executable or stale objects to satisfy the test.
    for path in glob.glob(os.path.join(PROJECT, "*.o")) + [CLI]:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    build = subprocess.run(
        ["make", "uroute_cli"], cwd=PROJECT, capture_output=True, text=True, timeout=20
    )
    assert build.returncode == 0, f"make uroute_cli failed:\n{build.stdout}\n{build.stderr}"
    assert os.path.isfile(CLI), "The repaired Makefile did not produce uroute_cli."
    with open(CLI, "rb") as f:
        assert f.read(4) == b"\x7fELF", "uroute_cli is not a compiled ELF executable."


def test_uroute_compiled():
    """Verify that the legacy C routing tool has been compiled successfully."""
    cli_path = "/app/vendored/uroute-0.5.1/uroute_cli"
    assert os.path.isfile(cli_path), f"Expected compiled executable at {cli_path} is missing."
    assert os.access(cli_path, os.X_OK), f"Executable {cli_path} is not executable."


def test_uroute_cli_behavior():
    """Check that uroute_cli behaves correctly for valid and invalid routes."""
    cli_path = "/app/vendored/uroute-0.5.1/uroute_cli"

    # Valid route
    res = subprocess.run([cli_path, "/api/v1/users"], capture_output=True)
    assert res.returncode == 0, f"uroute_cli failed on valid route /api/v1/users. Exit code: {res.returncode}"

    # Invalid route
    res = subprocess.run([cli_path, "/api/v1/admin"], capture_output=True)
    assert res.returncode != 0, f"uroute_cli incorrectly accepted invalid route /api/v1/admin. Exit code: {res.returncode}"


def test_uroute_cli_additional_behavior():
    for route in ("/api/v1/users", "/api/v1/posts"):
        res = subprocess.run([CLI, route], capture_output=True, timeout=5)
        assert res.returncode == 0, f"uroute_cli rejected valid route {route}"

    token = secrets.token_hex(10)
    invalid = [
        f"/api/v1/{token}",
        f"/api/v1/users/{token}",
        f"/{token}/api/v1/posts",
        "/api/v1/user",
        "/API/v1/users",
        "/api/v1/posts/",
        "",
    ]
    for route in invalid:
        res = subprocess.run([CLI, route], capture_output=True, timeout=5)
        assert res.returncode != 0, f"uroute_cli accepted unknown route {route!r}"

    assert subprocess.run([CLI], capture_output=True, timeout=5).returncode != 0


def test_gateway_filter_exists():
    """Ensure the gateway filter Python script exists."""
    script_path = "/home/user/gateway_filter.py"
    assert os.path.isfile(script_path), f"Python script {script_path} is missing."


def test_gateway_filter_against_corpora():
    """Test the gateway filter script against the clean and evil corpora."""
    script_path = "/home/user/gateway_filter.py"

    clean_dir = "/app/corpora/clean_requests"
    evil_dir = "/app/corpora/evil_requests"

    clean_files = glob.glob(os.path.join(clean_dir, "*.txt"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.txt"))

    assert len(clean_files) > 0, "No clean request files found."
    assert len(evil_files) > 0, "No evil request files found."

    clean_failures = []
    for cf in clean_files:
        with open(cf, 'r') as f:
            url = f.read().strip()
        res = subprocess.run(["python3", script_path, url], capture_output=True, text=True)
        output = res.stdout.strip()
        if output != "ACCEPT":
            clean_failures.append(os.path.basename(cf))

    evil_failures = []
    for ef in evil_files:
        with open(ef, 'r') as f:
            url = f.read().strip()
        res = subprocess.run(["python3", script_path, url], capture_output=True, text=True)
        output = res.stdout.strip()
        if output != "REJECT":
            evil_failures.append(os.path.basename(ef))

    error_msgs = []
    if clean_failures:
        error_msgs.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures)}")
    if evil_failures:
        error_msgs.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed/accepted: {', '.join(evil_failures)}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def path_checksum(path):
    value = 0
    for ch in path:
        value ^= ord(ch)
    return f"{value:02x}"


def make_url(path, ops, *, correct_checksum=True, rng=None):
    rng = rng or random.SystemRandom()
    checksum = int(path_checksum(path), 16)
    if not correct_checksum:
        checksum ^= rng.randrange(1, 256)
    chk = f"{checksum:02X}" if rng.randrange(2) else f"{checksum:02x}"
    ops_text = ops.hex().upper() if rng.randrange(2) else ops.hex()
    params = [("chk", chk), ("ops", ops_text), ("nonce", secrets.token_hex(5))]
    rng.shuffle(params)
    host = f"gw-{secrets.token_hex(5)}.example"
    return f"http://{host}{path}?{urlencode(params)}"


def run_filter(url, expected):
    res = subprocess.run(
        ["python3", SCRIPT, url], capture_output=True, text=True, timeout=8
    )
    assert res.returncode == 0, f"gateway_filter exited {res.returncode} for {url!r}: {res.stderr}"
    assert res.stdout == expected + "\n", (
        f"Expected exactly {expected!r} for {url!r}, got stdout {res.stdout!r}"
    )


def test_gateway_filter_generated_checksum_vm_and_routes():
    rng = random.SystemRandom()
    valid_routes = ["/api/v1/users", "/api/v1/posts"]

    # Randomized PUSH values prevent a classifier for the shipped corpus.
    for _ in range(8):
        route = rng.choice(valid_routes)
        safe = rng.randrange(0, 101)
        run_filter(make_url(route, bytes([0x01, safe]), rng=rng), "ACCEPT")

        malicious = rng.randrange(101, 256)
        run_filter(make_url(route, bytes([0x01, malicious]), rng=rng), "REJECT")

    # Exercise ADD and 8-bit wraparound with generated operands.
    for _ in range(8):
        route = rng.choice(valid_routes)
        a = rng.randrange(180, 256)
        target = rng.randrange(0, 101)
        b = (target - a) & 0xff
        ops = bytes([0x01, a, 0x01, b, 0x02])
        run_filter(make_url(route, ops, rng=rng), "ACCEPT")

    # Exercise MUL and derive the expected decision independently.
    for _ in range(12):
        route = rng.choice(valid_routes)
        a = rng.randrange(0, 256)
        b = rng.randrange(0, 256)
        result = (a * b) & 0xff
        ops = bytes([0x01, a, 0x01, b, 0x03])
        run_filter(make_url(route, ops, rng=rng), "ACCEPT" if result <= 100 else "REJECT")

    # Explicit stack-underflow cases.
    for ops in (bytes([0x02]), bytes([0x03]), bytes([0x01, 7, 0x02])):
        run_filter(make_url(rng.choice(valid_routes), ops, rng=rng), "REJECT")

    # Correct payloads must not override checksum or route rejection.
    safe_ops = bytes([0x01, rng.randrange(0, 101)])
    run_filter(make_url(rng.choice(valid_routes), safe_ops, correct_checksum=False, rng=rng), "REJECT")
    unknown = f"/api/v1/{secrets.token_hex(9)}"
    run_filter(make_url(unknown, safe_ops, rng=rng), "REJECT")


def test_gateway_filter_invokes_compiled_router():
    """Observe the required subprocess call rather than trusting duplicated route logic."""
    token = secrets.token_hex(10)
    saved_cli = f"/tmp/uroute_cli.real.{token}"
    marker = f"/tmp/uroute_cli.called.{token}"
    os.replace(CLI, saved_cli)
    try:
        with open(CLI, "w") as f:
            f.write("#!/bin/sh\n")
            f.write(f"printf '%s' \"$1\" > '{marker}'\n")
            f.write(f"exec '{saved_cli}' \"$@\"\n")
        os.chmod(CLI, 0o755)

        route = "/api/v1/posts"
        url = make_url(route, bytes([0x01, secrets.randbelow(101)]))
        run_filter(url, "ACCEPT")
        assert os.path.isfile(marker), "gateway_filter did not invoke uroute_cli"
        with open(marker, "r") as f:
            assert f.read() == route, "gateway_filter did not pass the URL path to uroute_cli"
    finally:
        try:
            os.remove(CLI)
        except FileNotFoundError:
            pass
        os.replace(saved_cli, CLI)
        try:
            os.remove(marker)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
