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
import os
import re
import secrets
import subprocess

import pytest
import redis
import requests

FASTA_PATH = "/home/user/sequences.fasta"
SCRIPT_PATH = "/home/user/process.sh"
API_URL = "http://127.0.0.1:8080/api/population"


def get_expected_populations(fasta_path):
    populations = {}
    if not os.path.exists(fasta_path):
        return populations

    with open(fasta_path, 'r') as f:
        seq_id = None
        seq = []
        for line in f:
            line = line.strip()
            if line.startswith(">"): 
                if seq_id:
                    s = "".join(seq)
                    gc = sum(1 for c in s if c in 'GCgc')
                    r = gc / len(s) if len(s) > 0 else 0
                    P = 10.0
                    for _ in range(10):
                        P += r * P * (1 - P / 100.0)
                    populations[seq_id] = P
                seq_id = line[1:]
                seq = []
            else:
                seq.append(line)
        if seq_id:
            s = "".join(seq)
            gc = sum(1 for c in s if c in 'GCgc')
            r = gc / len(s) if len(s) > 0 else 0
            P = 10.0
            for _ in range(10):
                P += r * P * (1 - P / 100.0)
            populations[seq_id] = P
    return populations


def run_process():
    result = subprocess.run(
        ["/bin/bash", SCRIPT_PATH],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"process.sh failed with exit code {result.returncode}. "
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )


def request_population(seq_id):
    url = f"{API_URL}?seq_id={seq_id}"
    try:
        return requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API for {seq_id} at {url}. Is the Flask app running? Error: {e}")


def test_process_script_exists():
    """Verify that the user created the process.sh script."""
    assert os.path.isfile(SCRIPT_PATH), f"Missing file: {SCRIPT_PATH} was not created."

    with open(SCRIPT_PATH, "r", errors="replace") as f:
        script = f.read()
    first_line = script.splitlines()[0] if script.splitlines() else ""
    assert re.search(r"^#!.*\b(?:ba)?sh\b", first_line), "process.sh must be a Bash script."
    assert re.search(r"\b(?:awk|gawk|bc)\b", script), (
        "process.sh must perform its processing using Bash and standard tools such as awk or bc."
    )
    assert not re.search(r"\b(?:python(?:2|3)?|perl|ruby|node)\b", script), (
        "process.sh must be primarily Bash rather than delegating the work to another language."
    )


def test_redis_port_configuration_and_service():
    app_path = "/app/api/app.py"
    assert os.path.isfile(app_path), f"Missing API file: {app_path}"
    with open(app_path, "r", errors="replace") as f:
        source = f.read()
    assert re.search(r"\bport\s*=\s*6379\b", source), "The API Redis connection is not configured for port 6379."

    client = redis.Redis(host="127.0.0.1", port=6379, db=0, decode_responses=True)
    try:
        assert client.ping() is True
    except redis.RedisError as e:
        pytest.fail(f"Redis is not running on port 6379: {e}")


def test_process_script_handles_derived_inputs_and_ingests_redis():
    """Execute process.sh on unpredictable FASTA data and verify Redis and API behavior."""
    client = redis.Redis(host="127.0.0.1", port=6379, db=0, decode_responses=True)
    with open(FASTA_PATH, "rb") as f:
        original_fasta = f.read()

    token = secrets.token_hex(6)
    records = []
    for index, length in enumerate((7, 10, 13, 16), start=1):
        seq_id = f"audit_{token}_{index}"
        sequence = "".join(secrets.choice("ACGT") for _ in range(length))
        records.append((seq_id, sequence))
    dynamic_fasta = "".join(f">{seq_id}\n{sequence}\n" for seq_id, sequence in records).encode()

    try:
        with open(FASTA_PATH, "wb") as f:
            f.write(dynamic_fasta)
        client.flushdb()
        run_process()

        with open(FASTA_PATH, "rb") as f:
            assert f.read() == dynamic_fasta, "process.sh modified the FASTA input file."

        expected = get_expected_populations(FASTA_PATH)
        assert set(expected) == {seq_id for seq_id, _ in records}
        assert set(client.keys("*")) == set(expected), (
            "process.sh did not ingest exactly the dynamically supplied FASTA records into Redis."
        )

        for seq_id, expected_p in expected.items():
            raw = client.get(seq_id)
            assert raw is not None, f"process.sh did not store Redis key {seq_id}."
            try:
                stored = float(raw)
            except (TypeError, ValueError):
                pytest.fail(f"Redis value for {seq_id} is not a float: {raw!r}")
            assert abs(stored - expected_p) <= 0.01, (
                f"Incorrect Redis population for {seq_id}: expected {expected_p}, got {stored}."
            )

            resp = request_population(seq_id)
            assert resp.status_code == 200, f"Expected HTTP 200 for {seq_id}, got {resp.status_code}. Response: {resp.text}"
            try:
                data = resp.json()
            except ValueError:
                pytest.fail(f"API did not return valid JSON for {seq_id}. Response: {resp.text}")
            assert "population" in data, f"Response for {seq_id} missing 'population' key. JSON: {data}"
            assert abs(data["population"] - round(expected_p, 2)) <= 0.05, (
                f"API population mismatch for {seq_id}: expected {round(expected_p, 2)}, got {data['population']}."
            )

        # Prove that the running API actually reads Redis rather than computing or hardcoding responses.
        probe_id = records[0][0]
        probe_value = 37.89123
        client.set(probe_id, repr(probe_value))
        resp = request_population(probe_id)
        assert resp.status_code == 200, f"API failed Redis mutation probe: {resp.text}"
        assert abs(resp.json().get("population") - round(probe_value, 2)) <= 0.001, (
            "The API response did not follow a direct Redis value change."
        )
    finally:
        with open(FASTA_PATH, "wb") as f:
            f.write(original_fasta)
        try:
            client.flushdb()
            run_process()
        except Exception:
            pass


def test_api_responses():
    """Verify that the API is running and returning the correct population values."""
    fasta_path = FASTA_PATH
    assert os.path.isfile(fasta_path), f"Missing FASTA file: {fasta_path}"

    expected_pops = get_expected_populations(fasta_path)
    assert expected_pops, "No sequences found to test."

    for seq_id, expected_p in expected_pops.items():
        resp = request_population(seq_id)
        assert resp.status_code == 200, f"Expected HTTP 200 for {seq_id}, got {resp.status_code}. Response: {resp.text}"

        try:
            data = resp.json()
        except ValueError:
            pytest.fail(f"API did not return valid JSON for {seq_id}. Response: {resp.text}")

        assert "population" in data, f"Response for {seq_id} missing 'population' key. JSON: {data}"

        actual_p = data["population"]
        expected_rounded = round(expected_p, 2)
        assert abs(actual_p - expected_rounded) <= 0.05, (
            f"Population mismatch for {seq_id}. Expected approx {expected_rounded}, got {actual_p}."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
