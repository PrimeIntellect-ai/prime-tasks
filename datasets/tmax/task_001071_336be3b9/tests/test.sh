#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import subprocess
import pytest

VALID_LOCALES = {"en-US", "fr-FR", "zh-CN", "pt-BR"}


def generate_fuzz_input(seed: int) -> str:
    random.seed(seed)
    num_lines = random.randint(0, 500)
    lines = []
    locales = ["en-US", "fr-FR", "zh-CN", "pt-BR", "invalid-LOC"]

    current_ts = 1600000000
    for _ in range(num_lines):
        if random.random() < 0.2:
            if random.random() < 0.5:
                lines.append("not a json line {")
            else:
                obj = {}
                if random.random() < 0.5:
                    obj["ts"] = current_ts
                if random.random() < 0.5:
                    obj["loc"] = random.choice(locales)
                lines.append(json.dumps(obj))
        else:
            if random.random() < 0.1:
                current_ts += random.randint(1000, 5000)
            elif random.random() < 0.3:
                current_ts += random.randint(60, 300)
            elif random.random() < 0.2:
                pass
            else:
                current_ts += random.randint(1, 59)

            obj = {
                "ts": current_ts,
                "loc": random.choice(locales),
                "lat": random.uniform(10.0, 1000.0),
            }
            if random.random() < 0.05:
                obj["ts"] = str(obj["ts"])
            if random.random() < 0.05:
                obj["lat"] = str(obj["lat"])
            lines.append(json.dumps(obj))

    return "\n".join(lines)


def expected_output(input_data: str) -> dict:
    data = {}
    for line in input_data.splitlines():
        try:
            obj = json.loads(line)
        except (ValueError, TypeError):
            continue

        if not isinstance(obj, dict) or not all(k in obj for k in ("ts", "loc", "lat")):
            continue

        ts = obj["ts"]
        loc = obj["loc"]
        lat = obj["lat"]

        # JSON strings and booleans are not integer/float telemetry fields.
        if isinstance(ts, bool) or not isinstance(ts, int):
            continue
        if isinstance(lat, bool) or not isinstance(lat, (int, float)):
            continue
        if not isinstance(loc, str) or loc not in VALID_LOCALES:
            continue
        if not math.isfinite(float(lat)):
            continue

        data.setdefault(loc, {}).setdefault(ts, []).append(float(lat))

    out = {}
    for loc, by_ts in data.items():
        if len(by_ts) < 2:
            continue

        deduped = [
            (ts, sum(by_ts[ts]) / len(by_ts[ts]))
            for ts in sorted(by_ts)
        ]
        all_latencies = []
        imputed_count = 0

        for i, (ts_a, lat_a) in enumerate(deduped):
            all_latencies.append(lat_a)
            if i == len(deduped) - 1:
                continue

            ts_b, lat_b = deduped[i + 1]
            ts_impute = ts_a + 60
            while ts_impute < ts_b:
                all_latencies.append(
                    lat_a + (lat_b - lat_a) * (ts_impute - ts_a) / (ts_b - ts_a)
                )
                imputed_count += 1
                ts_impute += 60

        average = math.floor((sum(all_latencies) / len(all_latencies)) * 100) / 100.0
        out[loc] = {
            "start_ts": deduped[0][0],
            "end_ts": deduped[-1][0],
            "original_points": len(deduped),
            "imputed_points": imputed_count,
            "avg_lat": average,
        }

    return out


def run_script(script_path: str, input_data: str) -> dict:
    try:
        result = subprocess.run(
            ["python3", script_path],
            input=input_data,
            text=True,
            capture_output=True,
            check=True,
            timeout=5,
        )
    except subprocess.CalledProcessError as exc:
        pytest.fail(
            f"Script {script_path} failed with exit code {exc.returncode}.\n"
            f"Stderr: {exc.stderr}"
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Script {script_path} timed out.")

    try:
        output = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        pytest.fail(
            f"Script {script_path} produced invalid JSON output.\n"
            f"Stdout: {result.stdout}\nError: {exc}"
        )

    assert isinstance(output, dict), "Program output must be a single JSON object."
    return output


def test_fuzz_equivalence():
    agent_script = "/home/user/process.py"
    assert os.path.isfile(agent_script), f"Agent script {agent_script} is missing."

    for seed in range(200):
        input_data = generate_fuzz_input(seed)
        expected = expected_output(input_data)
        actual = run_script(agent_script, input_data)
        if actual != expected:
            pytest.fail(
                f"Mismatch on seed {seed}!\n"
                f"Input lines: {len(input_data.splitlines())}\n"
                f"Expected output: {json.dumps(expected, indent=2)}\n"
                f"Agent output: {json.dumps(actual, indent=2)}\n"
                f"Input data:\n{input_data}"
            )


def test_declared_field_types_are_enforced():
    input_data = "\n".join([
        json.dumps({"ts": "100", "loc": "en-US", "lat": 10.0}),
        json.dumps({"ts": 100, "loc": "en-US", "lat": "10.0"}),
        json.dumps({"ts": True, "loc": "fr-FR", "lat": 20.0}),
        json.dumps({"ts": 100, "loc": "fr-FR", "lat": False}),
        json.dumps({"ts": 100, "loc": "en-US", "lat": 20.0}),
        json.dumps({"ts": 220, "loc": "en-US", "lat": 40.0}),
    ])
    assert run_script("/home/user/process.py", input_data) == expected_output(input_data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
