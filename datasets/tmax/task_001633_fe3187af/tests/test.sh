#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import secrets
import subprocess
import hashlib
from pathlib import Path
import pytest

FINAL_JSON_PATH = "/home/user/final_analysis.json"
SENSOR_PATH = "/home/user/sensor_data.txt"


def test_final_analysis_file_exists():
    """Verify that the final JSON output file exists."""
    assert os.path.exists(FINAL_JSON_PATH), f"The file {FINAL_JSON_PATH} does not exist."
    assert os.path.isfile(FINAL_JSON_PATH), f"The path {FINAL_JSON_PATH} is not a file."


def test_final_analysis_json_structure():
    """Verify that the JSON file contains the correct keys and data types."""
    with open(FINAL_JSON_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Could not parse {FINAL_JSON_PATH} as JSON: {e}")

    assert isinstance(data, dict), "The JSON root must be an object (dictionary)."

    expected_keys = {"mu_estimated", "analytical_prob", "mc_transmitted_count"}
    actual_keys = set(data.keys())

    missing_keys = expected_keys - actual_keys
    assert not missing_keys, f"Missing expected keys in JSON: {missing_keys}"

    assert isinstance(data["mu_estimated"], (int, float)), "mu_estimated must be a number."
    assert isinstance(data["analytical_prob"], (int, float)), "analytical_prob must be a number."
    assert isinstance(data["mc_transmitted_count"], int), "mc_transmitted_count must be an integer."


def test_final_analysis_values():
    """Verify that the estimated and calculated values are within acceptable bounds."""
    with open(FINAL_JSON_PATH, 'r') as f:
        data = json.load(f)

    mu = data["mu_estimated"]
    prob = data["analytical_prob"]
    mc_count = data["mc_transmitted_count"]

    expected_mu = 0.145
    assert math.isclose(mu, expected_mu, rel_tol=0.01), (
        f"Expected mu_estimated to be close to {expected_mu}, but got {mu}."
    )

    expected_prob = 0.1136
    assert math.isclose(prob, expected_prob, rel_tol=0.01), (
        f"Expected analytical_prob to be close to {expected_prob}, but got {prob}."
    )

    assert 112000 <= mc_count <= 115000, (
        f"Expected mc_transmitted_count to be between 112000 and 115000, but got {mc_count}."
    )


def _valid_dynamic_output(mu_raw):
    try:
        with open(FINAL_JSON_PATH, "r") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return False, "final_analysis.json was not produced as valid JSON"

    if set(data) != {"mu_estimated", "analytical_prob", "mc_transmitted_count"}:
        return False, "dynamic output did not contain exactly the required keys"
    if (not isinstance(data["mu_estimated"], (int, float)) or
            isinstance(data["mu_estimated"], bool) or
            not isinstance(data["analytical_prob"], (int, float)) or
            isinstance(data["analytical_prob"], bool) or
            not isinstance(data["mc_transmitted_count"], int) or
            isinstance(data["mc_transmitted_count"], bool)):
        return False, "dynamic output had incorrect value types"

    rounded_mu = round(mu_raw, 3)
    if abs(float(data["mu_estimated"]) - rounded_mu) > 0.00051:
        return False, f"dynamic mu was {data['mu_estimated']}, expected {rounded_mu}"

    raw_p = math.exp(-15.0 * mu_raw)
    rounded_p = math.exp(-15.0 * rounded_mu)
    reported_p = float(data["analytical_prob"])
    acceptable_probs = (round(raw_p, 4), round(rounded_p, 4))
    if min(abs(reported_p - p) for p in acceptable_probs) > 0.00011:
        return False, f"dynamic analytical probability was {reported_p}, expected one of {acceptable_probs}"

    count = data["mc_transmitted_count"]
    def count_close(p):
        sigma = math.sqrt(1_000_000 * p * (1.0 - p))
        return abs(count - 1_000_000 * p) <= max(2500, 10 * sigma)
    if not (count_close(raw_p) or count_close(rounded_p)):
        return False, f"dynamic Monte Carlo count {count} is inconsistent with 1,000,000 trials"
    return True, ""


def _cargo_commands():
    commands = []
    manifests = []
    for manifest in Path("/home/user").rglob("Cargo.toml"):
        text = str(manifest)
        if "/target/" in text or "/.cargo/" in text:
            continue
        manifests.append(manifest)

    for manifest in manifests:
        try:
            result = subprocess.run(
                ["cargo", "metadata", "--no-deps", "--format-version=1", "--manifest-path", str(manifest)],
                cwd="/home/user", text=True, capture_output=True, timeout=30
            )
            if result.returncode != 0:
                continue
            metadata = json.loads(result.stdout)
            for package in metadata.get("packages", []):
                for target in package.get("targets", []):
                    if "bin" in target.get("kind", []):
                        commands.append([
                            "cargo", "run", "--release", "--quiet",
                            "--manifest-path", str(manifest), "--bin", target["name"]
                        ])
        except Exception:
            continue
    return commands, manifests


def _standalone_commands(manifests):
    commands = []
    roots = [m.parent.resolve() for m in manifests]
    for source in Path("/home/user").rglob("*.rs"):
        resolved = source.resolve()
        text = str(resolved)
        if "/target/" in text or "/.cargo/" in text:
            continue
        if any(root == resolved.parent or root in resolved.parents for root in roots):
            continue
        binary = "/tmp/verified_rust_" + hashlib.sha256(str(resolved).encode()).hexdigest()[:16]
        compiled = subprocess.run(
            ["rustc", "-O", str(resolved), "-o", binary],
            cwd="/home/user", text=True, capture_output=True, timeout=90
        )
        if compiled.returncode == 0:
            commands.append([binary])
    return commands


def test_rust_artifact_executes_and_processes_sensor_data():
    """Run the submitted Rust artifact against fresh data and validate its computed output."""
    original_sensor = Path(SENSOR_PATH).read_bytes()
    original_json = Path(FINAL_JSON_PATH).read_bytes()

    rng = secrets.SystemRandom()
    if rng.randrange(2):
        chosen_mu = rng.uniform(0.075, 0.105)
    else:
        chosen_mu = rng.uniform(0.185, 0.215)

    lines = []
    first_average = None
    for x in (4, 9, 15):
        average = round(100000.0 * math.exp(-chosen_mu * x) + 200.0)
        if first_average is None:
            first_average = average
        # The individual readings deliberately differ; their average is the model value.
        for name, offset in (("sensor_A", -600), ("sensor_B", -300), ("sensor_C", 900)):
            lines.append(f"{name}|{x}|{average + offset}")

    mu_raw = -math.log((first_average - 200.0) / 100000.0) / 4.0
    commands = []
    errors = []

    try:
        Path(SENSOR_PATH).write_text("\n".join(lines) + "\n")
        try:
            os.remove(FINAL_JSON_PATH)
        except FileNotFoundError:
            pass

        cargo_commands, manifests = _cargo_commands()
        commands.extend(cargo_commands)
        commands.extend(_standalone_commands(manifests))
        assert commands, "No compilable/executable Rust program was found under /home/user"

        for command in commands:
            try:
                result = subprocess.run(
                    command, cwd="/home/user", text=True, capture_output=True, timeout=240
                )
                if result.returncode != 0:
                    errors.append(f"{' '.join(command)} exited {result.returncode}: {result.stderr[-500:]}")
                    continue
                valid, reason = _valid_dynamic_output(mu_raw)
                if valid:
                    return
                errors.append(f"{' '.join(command)}: {reason}")
            except subprocess.TimeoutExpired:
                errors.append(f"{' '.join(command)} timed out")

        pytest.fail("No submitted Rust executable produced the correct result for fresh sensor data. " + " | ".join(errors))
    finally:
        Path(SENSOR_PATH).write_bytes(original_sensor)
        Path(FINAL_JSON_PATH).write_bytes(original_json)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
