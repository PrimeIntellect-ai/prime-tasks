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
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
from pathlib import Path

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
API_KEY = "sec_prod_99x8a7f6b5c4d3e2f1"
HEADERS = {
    "Authorization": f"Bearer {API_KEY}",
    "Content-Type": "application/json",
}
PROJECT = Path("/app/data-ingestor")
BINARY = PROJECT / "target/release/ticker-service"


def listening_pids_on_8080():
    target = "0100007F:1F90"  # 127.0.0.1:8080 in /proc/net/tcp
    listening = []
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if fields[3] == "0A" and fields[1].endswith(":1F90"):
                listening.append((table, fields[1], fields[9]))

    assert listening, "No process is listening on port 8080"
    assert all(table == "/proc/net/tcp" and address == target for table, address, _ in listening), \
        f"Port 8080 must be bound exactly to 127.0.0.1, found: {listening}"

    inodes = {inode for _, _, inode in listening}
    owners = set()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    if os.readlink(fd) in {f"socket:[{inode}]" for inode in inodes}:
                        owners.add(int(proc.name))
                        break
                except OSError:
                    pass
        except OSError:
            pass
    assert owners, "Could not identify the process listening on 127.0.0.1:8080"
    return owners


def test_release_artifact_and_implementation():
    assert BINARY.is_file(), f"Missing Cargo release binary: {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Release binary is not executable: {BINARY}"
    assert BINARY.read_bytes()[:4] == b"\x7fELF", "Release artifact is not an ELF executable"

    sources = sorted((PROJECT / "src").glob("**/*.rs"))
    assert sources, "Rust source files are missing"
    source = "\n".join(path.read_text() for path in sources)
    code_without_comments = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    code_without_comments = re.sub(r"//.*", "", code_without_comments)

    assert re.search(r"\bprice\s*:\s*f64\b", code_without_comments), "Tick.price was not upgraded to f64"
    assert re.search(r"\bvwap\s*:\s*f64\b", code_without_comments), "VWAP response was not upgraded to f64"
    assert re.search(r"\btotal_value\s*:\s*f64\b", code_without_comments), "VWAP accumulator was not upgraded to f64"
    assert not re.search(r"\bf32\b", code_without_comments), "Active Rust implementation still uses f32"

    newest_input = max([PROJECT / "Cargo.toml", *sources], key=lambda p: p.stat().st_mtime)
    assert BINARY.stat().st_mtime >= newest_input.stat().st_mtime, \
        "Release binary is older than the submitted source; run cargo build --release"

    expected_exe = str(BINARY.resolve())
    owners = listening_pids_on_8080()
    matching = []
    for pid in owners:
        try:
            exe = os.path.realpath(f"/proc/{pid}/exe")
            environ = Path(f"/proc/{pid}/environ").read_bytes().split(b"\0")
        except OSError:
            continue
        if exe == expected_exe:
            matching.append((pid, environ))

    assert matching, f"The listener is not the Cargo release binary {expected_exe}"
    assert any(f"UPSTREAM_API_KEY={API_KEY}".encode() in env for _, env in matching), \
        "The running release service does not have the recovered UPSTREAM_API_KEY in its environment"


def test_service_is_listening():
    try:
        requests.get(BASE_URL, timeout=2)
    except requests.exceptions.ConnectionError:
        pytest.fail(f"Service is not listening on {BASE_URL}. Did you start it in the background?")
    except requests.exceptions.Timeout:
        pytest.fail(f"Service at {BASE_URL} timed out.")


def test_unauthorized_request_rejected():
    try:
        res = requests.post(f"{BASE_URL}/tick", json={"symbol": "TEST", "price": 100.0, "qty": 10}, timeout=2)
        assert res.status_code in (401, 403), f"Expected 401 or 403 for missing auth, got {res.status_code}"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to service: {e}")


def test_qty_zero_bad_request():
    payload = {"symbol": "ZERO", "price": 50000.0, "qty": 0}
    try:
        res = requests.post(f"{BASE_URL}/tick", headers=HEADERS, json=payload, timeout=2)
        assert res.status_code == 400, f"Expected 400 Bad Request for qty=0, got {res.status_code}. Body: {res.text}"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to service: {e}")


def test_vwap_precision_f64():
    symbol = "PRECISION_TEST"
    tick1 = {"symbol": symbol, "price": 60000.12345678901, "qty": 10}
    tick2 = {"symbol": symbol, "price": 60000.98765432109, "qty": 5}

    try:
        res1 = requests.post(f"{BASE_URL}/tick", headers=HEADERS, json=tick1, timeout=2)
        assert res1.status_code == 200, f"Failed to post tick 1: {res1.status_code} - {res1.text}"
        res2 = requests.post(f"{BASE_URL}/tick", headers=HEADERS, json=tick2, timeout=2)
        assert res2.status_code == 200, f"Failed to post tick 2: {res2.status_code} - {res2.text}"
        res_vwap = requests.get(f"{BASE_URL}/vwap?symbol={symbol}", headers=HEADERS, timeout=2)
        assert res_vwap.status_code == 200, f"Failed to get VWAP: {res_vwap.status_code} - {res_vwap.text}"
        data = res_vwap.json()
        assert "vwap" in data, f"Response JSON missing 'vwap' field: {data}"
        expected_vwap = (tick1["price"] * tick1["qty"] + tick2["price"] * tick2["qty"]) / (tick1["qty"] + tick2["qty"])
        actual_vwap = data["vwap"]
        assert math.isclose(actual_vwap, expected_vwap, rel_tol=1e-12), \
            f"VWAP precision issue. Expected {expected_vwap}, got {actual_vwap}. Are you sure you upgraded to f64?"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to service: {e}")


def test_randomized_vwap_and_zero_quantity_drop():
    rng = secrets.SystemRandom()
    for _ in range(5):
        symbol = f"AUDIT_{secrets.token_hex(12)}"
        ticks = []
        for _ in range(rng.randint(3, 6)):
            price = rng.randint(8_000_000, 90_000_000) + rng.randrange(1, 1_000_000_000) / 1_000_000_000
            qty = rng.randint(1, 10000)
            ticks.append({"symbol": symbol, "price": price, "qty": qty})

        for tick in ticks:
            res = requests.post(f"{BASE_URL}/tick", headers=HEADERS, json=tick, timeout=2)
            assert res.status_code == 200, f"Random tick failed: {res.status_code} - {res.text}"

        zero_tick = {"symbol": symbol, "price": rng.uniform(1.0, 100000000.0), "qty": 0}
        res = requests.post(f"{BASE_URL}/tick", headers=HEADERS, json=zero_tick, timeout=2)
        assert res.status_code == 400, f"Random qty=0 tick was not rejected: {res.status_code} - {res.text}"

        res = requests.get(f"{BASE_URL}/vwap", headers=HEADERS, params={"symbol": symbol}, timeout=2)
        assert res.status_code == 200, f"Random VWAP request failed: {res.status_code} - {res.text}"
        data = res.json()
        assert data.get("symbol") == symbol, f"Wrong symbol in VWAP response: {data}"
        expected = math.fsum(t["price"] * t["qty"] for t in ticks) / sum(t["qty"] for t in ticks)
        assert isinstance(data.get("vwap"), (int, float)), f"Invalid VWAP response: {data}"
        assert math.isclose(data["vwap"], expected, rel_tol=2e-13), \
            f"Randomized VWAP mismatch: expected {expected}, got {data['vwap']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
