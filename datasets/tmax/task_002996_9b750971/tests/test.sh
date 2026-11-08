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
import json
import os
import random
import re
import shutil
import subprocess
from decimal import Decimal
from pathlib import Path

import pytest
import requests

SOURCE_DIR = Path("/app/datamash-1.8")
CSV_PATH = Path("/home/user/transactions.csv")
ETL_PATH = Path("/home/user/etl.sh")
SERVER_PATH = Path("/home/user/server.sh")
URL = "http://127.0.0.1:9090/"


def test_datamash_installed():
    """Verify the vendored package was fixed, configured, compiled, and installed."""
    found = shutil.which("datamash")
    assert found is not None, "datamash binary is not installed or not in PATH. The Makefile fix and installation may have failed."
    assert os.path.realpath(found) == os.path.realpath("/usr/local/bin/datamash"), \
        f"Expected the --prefix=/usr/local installation, but PATH resolves datamash to {found}"

    makefile_in = SOURCE_DIR / "Makefile.in"
    text = makefile_in.read_text()
    assert re.search(r"(?m)^bin_PROGRAMS\s*=\s*datamash\s*$", text), \
        "The bin_PROGRAMS typo in Makefile.in was not fixed to datamash"
    assert not re.search(r"(?m)^bin_PROGRAMS\s*=.*\bdatamas\b", text), \
        "Makefile.in still names the broken datamas target"

    generated_makefile = SOURCE_DIR / "Makefile"
    assert (SOURCE_DIR / "config.status").is_file(), "The vendored source was not configured"
    assert generated_makefile.is_file(), "configure did not generate a Makefile"
    assert re.search(r"(?m)^bin_PROGRAMS\s*=\s*datamash\s*$", generated_makefile.read_text()), \
        "The configured Makefile does not build datamash"

    installed = Path("/usr/local/bin/datamash")
    assert installed.is_file() and os.access(installed, os.X_OK), \
        "/usr/local/bin/datamash is not an installed executable file"
    assert installed.read_bytes()[:4] == b"\x7fELF", \
        "The installed datamash is not the compiled executable"

    version = subprocess.run(
        [str(installed), "--version"], text=True, capture_output=True, timeout=5, check=True
    ).stdout
    assert "GNU datamash" in version and re.search(r"\b1\.8\b", version), \
        f"Unexpected installed datamash version output: {version!r}"

    result = subprocess.run(
        [str(installed), "-g", "1", "sum", "2"],
        input="alpha\t1\nalpha\t2\nbeta\t4\n",
        text=True,
        capture_output=True,
        timeout=5,
        check=True,
    )
    assert result.stdout.splitlines() == ["alpha\t3", "beta\t4"], \
        f"Installed datamash failed a grouping operation: {result.stdout!r}"


def test_scripts_are_bash_executables():
    for path in (ETL_PATH, SERVER_PATH):
        assert path.is_file(), f"Required script {path} does not exist"
        assert os.access(path, os.X_OK), f"Required script {path} is not executable"
        first_line = path.read_text(errors="replace").splitlines()[0]
        assert "bash" in first_line, f"{path} is required to be a Bash script"
        subprocess.run(["bash", "-n", str(path)], timeout=5, check=True)


def fetch_json(url=URL):
    try:
        response = requests.get(url, timeout=5)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to the server at {url}. Is the server running? Error: {exc}")

    assert response.status_code == 200, \
        f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"
    content_type = response.headers.get("Content-Type", "")
    assert "application/json" in content_type, \
        f"Expected Content-Type: application/json, got '{content_type}'"
    try:
        return response.json()
    except (ValueError, json.JSONDecodeError):
        pytest.fail(f"Response body is not valid JSON. Response text: {response.text}")


def test_server_response():
    """Retain the original fixed-data response assertions."""
    data = fetch_json()
    expected_data = {
        "9223372036854775807": 150.75,
        "1234567890123456789": 150.00,
        "9999999999999999999": 10.00,
    }

    for key, expected_value in expected_data.items():
        assert key in data, \
            f"Expected user_id '{key}' is missing from the JSON response. Ensure 19-digit IDs are preserved as exact strings."
        actual_value = float(data[key])
        assert abs(actual_value - expected_value) < 1e-5, \
            f"Expected sum {expected_value} for user_id '{key}', got {actual_value}"

    for key in data.keys():
        assert key in expected_data, f"Unexpected user_id '{key}' found in JSON response."


def make_random_dataset():
    rng = random.SystemRandom()
    ids = set()
    while len(ids) < 4:
        ids.add(str(rng.randrange(10**18, 10**19)))
    ids = list(ids)

    rows = []
    expected_cents = {}
    tx_id = 1
    for user_id in ids:
        amounts = [rng.randrange(-250000, 250001), rng.randrange(-250000, 250001)]
        if user_id == ids[0]:
            amounts.append(rng.randrange(-250000, 250001))
        for cents in amounts:
            sign = "-" if cents < 0 else ""
            absolute = abs(cents)
            amount = f"{sign}{absolute // 100}.{absolute % 100:02d}"
            rows.append(f"{tx_id},{user_id},{amount}")
            expected_cents[user_id] = expected_cents.get(user_id, 0) + cents
            tx_id += 1
    rng.shuffle(rows)
    return "tx_id,user_id,amount\n" + "\n".join(rows) + "\n", expected_cents


def assert_aggregation(data, expected_cents):
    assert isinstance(data, dict), f"Expected a JSON object, got {type(data).__name__}"
    assert set(data) == set(expected_cents), \
        f"Expected exact user IDs {set(expected_cents)}, got {set(data)}"
    for user_id, cents in expected_cents.items():
        assert re.fullmatch(r"\d{19}", user_id)
        value = data[user_id]
        assert isinstance(value, (int, float)) and not isinstance(value, bool), \
            f"Amount for {user_id} must be a JSON number, got {value!r}"
        assert abs(Decimal(str(value)) - (Decimal(cents) / Decimal(100))) < Decimal("0.000001"), \
            f"Incorrect sum for exact user ID {user_id}: got {value}, expected {Decimal(cents) / Decimal(100)}"


def write_csv_atomically(contents):
    temporary = CSV_PATH.with_name("transactions.csv.verifier-tmp")
    temporary.write_text(contents)
    os.replace(temporary, CSV_PATH)


def test_etl_and_server_process_runtime_inputs():
    """Exercise etl.sh and prove the server reruns it for changing, unpredictable CSV data."""
    original = CSV_PATH.read_bytes()
    try:
        csv_one, expected_one = make_random_dataset()
        write_csv_atomically(csv_one)

        direct = subprocess.run(
            [str(ETL_PATH)], text=True, capture_output=True, timeout=10, check=True
        )
        try:
            direct_data = json.loads(direct.stdout)
        except json.JSONDecodeError as exc:
            pytest.fail(f"etl.sh did not output valid JSON: {exc}; output={direct.stdout!r}")
        assert_aggregation(direct_data, expected_one)
        assert_aggregation(fetch_json(URL + "runtime-check-one"), expected_one)

        csv_two, expected_two = make_random_dataset()
        write_csv_atomically(csv_two)
        assert expected_two != expected_one
        assert_aggregation(fetch_json(URL + "runtime-check-two?fresh=1"), expected_two)
    finally:
        CSV_PATH.write_bytes(original)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
