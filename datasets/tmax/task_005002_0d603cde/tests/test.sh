#!/bin/bash
set -u
mkdir -p /logs/verifier

run_checks() {
cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_rust_project_exists():
    project_dir = "/home/user/anomaly_detector"
    assert os.path.isdir(project_dir), f"The Rust project directory {project_dir} does not exist."

    cargo_toml = os.path.join(project_dir, "Cargo.toml")
    assert os.path.isfile(cargo_toml), f"Cargo.toml not found in {project_dir}. Is it a valid Rust project?"

def test_anomalies_json_exists_and_valid():
    json_path = "/home/user/anomalies.json"
    assert os.path.isfile(json_path), f"The output file {json_path} does not exist."

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse {json_path} as JSON: {e}")

    assert isinstance(data, list), f"Expected the JSON root to be a list, but got {type(data).__name__}."
    for item in data:
        assert isinstance(item, str), f"Expected all items in the JSON array to be strings, but found {type(item).__name__}."

def test_anomalies_content():
    json_path = "/home/user/anomalies.json"
    if not os.path.isfile(json_path):
        pytest.fail(f"File {json_path} is missing.")

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Invalid JSON in {json_path}.")

    # The expected base IPs
    expected_base_ips = {"10.0.0.42", "10.1.2.3", "192.168.1.15", "8.8.8.8"}

    # The actual IPs found
    actual_ips = set(data)

    # Check that all base IPs are present
    missing_ips = expected_base_ips - actual_ips
    assert not missing_ips, f"The following expected IPs are missing from the output: {missing_ips}"

    # Check for unexpected IPs (allowing 256.256.256.256)
    allowed_extra_ips = {"256.256.256.256"}
    unexpected_ips = actual_ips - expected_base_ips - allowed_extra_ips
    assert not unexpected_ips, f"Found unexpected IPs in the output: {unexpected_ips}"

    # Check that the list is sorted alphabetically
    assert data == sorted(data), "The JSON array of IPs is not sorted alphabetically."
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1

    export RUSTUP_HOME=/opt/rustup
    export CARGO_HOME=/opt/cargo
    export PATH="/opt/cargo/bin:${PATH}"

    cd /home/user/anomaly_detector || return 1
    timeout 180 cargo build --release || return 1

    # Replace the served inputs with a fresh challenge so a fixed output cannot pass.
    python3 - << 'PY_EOF' || return 1
import csv
import ipaddress
import json
import os
import random
import re
import secrets

root = "/home/user/server_data"
os.makedirs(root, exist_ok=True)
rng = random.Random(secrets.randbits(128))

valid = [
    f"11.{rng.randint(1, 254)}.{rng.randint(0, 255)}.{rng.randint(1, 254)}",
    f"172.{rng.randint(16, 31)}.{rng.randint(0, 255)}.{rng.randint(1, 254)}",
    f"198.51.{rng.randint(0, 255)}.{rng.randint(1, 254)}",
    f"203.0.{rng.randint(0, 255)}.{rng.randint(1, 254)}",
]
while len(set(valid)) != len(valid):
    valid[-1] = f"203.0.{rng.randint(0, 255)}.{rng.randint(1, 254)}"

files = {
    "data1.csv": [
        ["2026-01-01T00:00:00Z", "alpha", f"E-500: Failed connection from {valid[0]}"],
        ["2026-01-01T00:00:01Z", "beta", "INFO: normal operation, all systems ready"],
        ["2026-01-01T00:00:02Z", "gamma", f"E-500: Failed connection from {valid[1]}"],
    ],
    "data2.csv": [
        ["2026-01-01T00:01:00Z", "delta", f"E-500: Failed connection from {valid[0]}"],
        ["2026-01-01T00:01:01Z", "epsilon", "E-500: Failed connection from 256.256.256.256"],
        ["2026-01-01T00:01:02Z", "zeta", f"E-400: Failed connection from {valid[2]}"],
        [f"E-500: Failed connection from {valid[2]}", "eta", "INFO: timestamp text must not be parsed"],
    ],
    "data3.csv": [
        ["2026-01-01T00:02:00Z", "theta", f"E-500: Failed connection from {valid[2]}"],
        ["2026-01-01T00:02:01Z", "iota", "E-500: Failed connection from not.an.ip.address"],
        ["2026-01-01T00:02:02Z", "kappa", f"E-500: Failed connection from {valid[3]}"],
        ["2026-01-01T00:02:03Z", f"E-500: Failed connection from {valid[1]}", "INFO: server name must not be parsed"],
        ["2026-01-01T00:02:04Z", "lambda", f"E-500: Failed connection from {valid[3]}"],
    ],
}

for name, rows in files.items():
    temp = os.path.join(root, name + ".new")
    with open(temp, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["timestamp", "server_name", "log_message"])
        writer.writerows(rows)
    os.replace(temp, os.path.join(root, name))

pattern = re.compile(r"^E-500: Failed connection from ((?:[0-9]{1,3}\.){3}[0-9]{1,3})$")
expected = set()
for name in files:
    with open(os.path.join(root, name), newline="") as f:
        for row in csv.DictReader(f):
            match = pattern.fullmatch(row["log_message"])
            if not match:
                continue
            try:
                expected.add(str(ipaddress.IPv4Address(match.group(1))))
            except ipaddress.AddressValueError:
                pass

with open("/tmp/expected_dynamic.json", "w") as f:
    json.dump(sorted(expected), f)
PY_EOF

    if ! curl -fsS --max-time 2 http://127.0.0.1:8123/data1.csv >/dev/null; then
        (cd /home/user/server_data && nohup python3 -m http.server 8123 >/tmp/anomaly-http.log 2>&1 &)
        sleep 1
    fi
    curl -fsS --max-time 3 http://127.0.0.1:8123/data1.csv >/dev/null || return 1

    rm -f /home/user/anomalies.json
    cd /home/user/anomaly_detector || return 1
    timeout 60 cargo run --release --quiet || return 1

    python3 - << 'PY_EOF' || return 1
import ipaddress
import json
import os

output_path = "/home/user/anomalies.json"
assert os.path.isfile(output_path), "The executed Rust program did not generate anomalies.json"
with open(output_path) as f:
    actual = json.load(f)
with open("/tmp/expected_dynamic.json") as f:
    expected = json.load(f)

assert isinstance(actual, list), "The generated JSON root is not an array"
assert all(isinstance(item, str) for item in actual), "The generated array contains non-string values"
assert actual == sorted(actual), "The generated IP list is not sorted alphabetically"
assert len(actual) == len(set(actual)), "The generated IP list contains duplicate entries"
for item in actual:
    ipaddress.IPv4Address(item)
assert actual == expected, f"Output from fresh CSV inputs was {actual!r}; expected {expected!r}"
PY_EOF
}

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
