#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import subprocess
import urllib.request

import pytest


def api_prediction(feature):
    payload = json.dumps({"feature": feature}).encode("utf-8")
    req = urllib.request.Request(
        "http://127.0.0.1:5000/predict",
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=2) as response:
        assert response.status == 200
        body = json.loads(response.read().decode("utf-8"))
    assert "prediction" in body
    return float(body["prediction"])


def expected_output(user_id, v1, v2, multiplier):
    base_array = [v1, v2, v1 - v2, v1 + v2]
    rng = random.Random(user_id)
    means = []
    for _ in range(100):
        sample = rng.choices(base_array, k=4)
        means.append(sum(sample) / 4.0)
    engineered_feature = sum(means) / 100.0
    prediction = engineered_feature * multiplier * 2.5 + 1.1
    return f"{prediction:.4f}"


def test_pipeline_fuzz_equivalence():
    agent_path = "/home/user/pipeline.py"
    assert os.path.exists(agent_path), f"Agent path {agent_path} does not exist."
    assert os.path.isfile(agent_path), f"Agent path {agent_path} is not a file."

    try:
        import redis
        r = redis.Redis(host="127.0.0.1", port=6379, db=0)
        r.ping()
    except Exception as e:
        pytest.fail(
            "Could not connect to Redis. Is Redis running on 127.0.0.1:6379? "
            f"Error: {e}"
        )

    # Verify that the agent-modifiable API still implements the supplied model;
    # a constant-response replacement must not serve as a shared fake oracle.
    probe_rng = secrets.SystemRandom()
    try:
        for _ in range(12):
            feature = probe_rng.uniform(-1000.0, 1000.0)
            actual = api_prediction(feature)
            expected = feature * 2.5 + 1.1
            assert actual == pytest.approx(expected, rel=1e-12, abs=1e-9)
    except Exception as e:
        pytest.fail(
            "Flask API is not running correctly at 127.0.0.1:5000 or does not "
            f"implement the supplied regression model. Error: {e}"
        )

    cases = []
    used_ids = set()
    for index in range(100):
        while True:
            user_id = probe_rng.randint(1, 2_000_000_000)
            if user_id not in used_ids:
                used_ids.add(user_id)
                break
        v1 = probe_rng.uniform(-50.0, 50.0)
        v2 = probe_rng.uniform(-50.0, 50.0)
        key = f"multiplier_{user_id}"

        if index % 2 == 0:
            multiplier = probe_rng.uniform(0.1, 5.0)
            r.set(key, repr(multiplier))
        else:
            r.delete(key)
            multiplier = 1.0

        cases.append((user_id, v1, v2, multiplier))

    for user_id, v1, v2, multiplier in cases:
        input_data = {"user_id": user_id, "v1": v1, "v2": v2}
        input_str = json.dumps(input_data)
        expected = expected_output(user_id, v1, v2, multiplier)

        try:
            result = subprocess.run(
                ["python3", agent_path, input_str],
                capture_output=True,
                text=True,
                check=True,
                timeout=5,
            )
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent script failed on input {input_str}:\n{e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out on input {input_str}")

        actual = result.stdout.strip()
        assert actual == expected, (
            f"Mismatch on input: {input_str}\n"
            f"Expected output: {expected}\n"
            f"Agent output:    {actual}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
