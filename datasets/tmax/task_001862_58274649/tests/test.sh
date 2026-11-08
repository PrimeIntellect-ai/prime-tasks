#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import uuid


def run_filter(script_path, raw_input):
    if isinstance(raw_input, (dict, list)):
        raw_input = json.dumps(raw_input, separators=(",", ":"))
    return subprocess.run(
        ["python3", script_path],
        input=raw_input,
        text=True,
        capture_output=True,
        timeout=5,
    )


def test_jq_built_successfully():
    source_dir = "/app/jq-1.6"
    jq_path = os.path.join(source_dir, "jq")

    # Rebuild from the vendored tree so a pre-created executable cannot stand in
    # for repairing the broken build configuration.
    clean = subprocess.run(
        ["make", "clean"], cwd=source_dir, capture_output=True, text=True, timeout=120
    )
    assert clean.returncode == 0, f"make clean failed: {clean.stdout}\n{clean.stderr}"

    build = subprocess.run(
        ["make", "-j2"], cwd=source_dir, capture_output=True, text=True, timeout=300
    )
    assert build.returncode == 0, f"jq failed to rebuild: {build.stdout}\n{build.stderr}"

    assert os.path.isfile(jq_path), f"jq binary not found at {jq_path}. Did you fix the Makefile and run make?"
    assert os.access(jq_path, os.X_OK), f"jq binary at {jq_path} is not executable."
    with open(jq_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "jq is not a compiled ELF executable"

    # Preserve the original execution check and verify the requested version.
    result = subprocess.run([jq_path, "--version"], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"jq binary failed to execute. stderr: {result.stderr}"
    assert result.stdout.strip() == "jq-1.6", f"unexpected jq version: {result.stdout!r}"

    # Exercise real jq parsing, filtering, aggregation, and math functionality
    # using values generated only when verification runs.
    items = []
    for _ in range(12):
        items.append({
            "name": uuid.uuid4().hex,
            "v": secrets.randbelow(10000),
            "ok": bool(secrets.randbelow(2)),
        })
    factor = secrets.randbelow(1000) + 1
    document = {"items": items, "factor": factor}
    query = "{sum: ([.items[].v] | add), names: [.items[] | select(.ok) | .name], scaled: (.factor * 3)}"
    transformed = subprocess.run(
        [jq_path, "-c", query],
        input=json.dumps(document),
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert transformed.returncode == 0, transformed.stderr
    assert json.loads(transformed.stdout) == {
        "sum": sum(item["v"] for item in items),
        "names": [item["name"] for item in items if item["ok"]],
        "scaled": factor * 3,
    }

    math_result = subprocess.run(
        [jq_path, "-n", "pow(2; 10) + sqrt(81)"],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert math_result.returncode == 0, math_result.stderr
    assert json.loads(math_result.stdout) == 1033

    malformed = subprocess.run(
        [jq_path, "."], input="{not-json", text=True, capture_output=True, timeout=10
    )
    assert malformed.returncode != 0, "jq accepted malformed JSON"


def test_telemetry_filter_adversarial_corpus():
    script_path = "/home/user/telemetry_filter.py"
    assert os.path.isfile(script_path), f"Telemetry filter script not found at {script_path}"

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith(".json")]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith(".json")]

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_failed = []
    for path in clean_files:
        with open(path, "r") as f:
            result = run_filter(script_path, f.read())
        if result.returncode != 0:
            clean_failed.append(os.path.basename(path))

    evil_failed = []
    for path in evil_files:
        with open(path, "r") as f:
            result = run_filter(script_path, f.read())
        if result.returncode != 1:
            evil_failed.append(os.path.basename(path))

    error_messages = []
    if clean_failed:
        error_messages.append(
            f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}"
        )
    if evil_failed:
        error_messages.append(
            f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}"
        )
    assert not error_messages, " | ".join(error_messages)


def test_telemetry_filter_generated_cases_without_validator():
    script_path = "/home/user/telemetry_filter.py"
    assert os.path.isfile(script_path), f"Telemetry filter script not found at {script_path}"

    validator = "/usr/local/bin/token_validator"
    held_validator = f"/tmp/token_validator-held-{uuid.uuid4().hex}"
    validator_was_present = os.path.exists(validator)
    if validator_was_present:
        os.replace(validator, held_validator)

    try:
        valid_cases = []
        invalid_cases = []

        # Paired, runtime-generated cases prevent classification by fixed corpus
        # values or superficial fields. Expected tokens are derived independently.
        for i in range(40):
            probe_id = secrets.randbelow(2_000_000)
            token = (probe_id * 1337) % 100000
            total = secrets.randbelow(1_000_000) + 1
            uptime = secrets.randbelow(total + 1)
            base = {
                "probe_id": probe_id,
                "token": token,
                "uptime_sec": uptime,
                "total_sec": total,
            }
            if i == 0:
                base["extra"] = uuid.uuid4().hex
            valid_cases.append(base)

            bad_token = dict(base)
            bad_token["token"] = token + 1
            invalid_cases.append(bad_token)

            too_large = dict(base)
            too_large["uptime_sec"] = total + secrets.randbelow(1000) + 1
            invalid_cases.append(too_large)

            negative_uptime = dict(base)
            negative_uptime["uptime_sec"] = -(secrets.randbelow(1000) + 1)
            invalid_cases.append(negative_uptime)

            nonpositive_total = dict(base)
            nonpositive_total["total_sec"] = 0 if i % 2 == 0 else -(secrets.randbelow(1000) + 1)
            invalid_cases.append(nonpositive_total)

        # Boundary-valid numeric telemetry, including fractional time fields.
        boundary_probe = secrets.randbelow(2_000_000)
        valid_cases.extend([
            {"probe_id": boundary_probe, "token": (boundary_probe * 1337) % 100000,
             "uptime_sec": 0, "total_sec": 1},
            {"probe_id": boundary_probe, "token": (boundary_probe * 1337) % 100000,
             "uptime_sec": 17.5, "total_sec": 17.5},
        ])

        for payload in valid_cases:
            result = run_filter(script_path, payload)
            assert result.returncode == 0, (
                f"valid generated payload rejected ({result.returncode}): {payload}; stderr={result.stderr!r}"
            )

        for payload in invalid_cases:
            result = run_filter(script_path, payload)
            assert result.returncode == 1, (
                f"invalid generated payload not rejected with status 1 ({result.returncode}): {payload}"
            )

        template_probe = secrets.randbelow(2_000_000)
        template = {
            "probe_id": template_probe,
            "token": (template_probe * 1337) % 100000,
            "uptime_sec": 1,
            "total_sec": 2,
        }
        structural_bad = []
        for field in ("probe_id", "token", "uptime_sec", "total_sec"):
            payload = dict(template)
            del payload[field]
            structural_bad.append(payload)
        for field in ("probe_id", "token", "uptime_sec", "total_sec"):
            payload = dict(template)
            payload[field] = None
            structural_bad.append(payload)
            payload = dict(template)
            payload[field] = "1"
            structural_bad.append(payload)
            payload = dict(template)
            payload[field] = True
            structural_bad.append(payload)
        structural_bad.extend([[], [template], {}, "telemetry"])

        for payload in structural_bad:
            result = run_filter(script_path, payload)
            assert result.returncode == 1, f"nonconforming payload was not rejected: {payload!r}"

        for raw in ("", "{", "not json", "[] trailing", "NaN", '{"probe_id":1,}'):
            result = run_filter(script_path, raw)
            assert result.returncode == 1, f"malformed JSON was not rejected with status 1: {raw!r}"
    finally:
        if validator_was_present:
            os.replace(held_validator, validator)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
