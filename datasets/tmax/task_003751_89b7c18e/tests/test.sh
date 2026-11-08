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
import math
import secrets
import socket
import pytest
import requests

URL = "http://127.0.0.1:3000/prepare"
REDIS_KEY = "experiment:latest:max_abs_val"


def get_redis_value():
    try:
        with socket.create_connection(("127.0.0.1", 6379), timeout=3) as s:
            s.settimeout(3)
            # The key is exactly 29 bytes long.
            command = b"*2\r\n$3\r\nGET\r\n$29\r\nexperiment:latest:max_abs_val\r\n"
            s.sendall(command)
            stream = s.makefile("rb")
            header = stream.readline()
            if not header:
                pytest.fail("Redis closed the connection without returning a response")
            if header == b"$-1\r\n":
                pytest.fail(f"Redis key '{REDIS_KEY}' not found or empty")
            if not header.startswith(b"$"):
                pytest.fail(f"Unexpected Redis response header: {header!r}")
            try:
                length = int(header[1:-2])
            except ValueError:
                pytest.fail(f"Malformed Redis bulk-string header: {header!r}")
            raw_value = stream.read(length)
            terminator = stream.read(2)
            if len(raw_value) != length or terminator != b"\r\n":
                pytest.fail("Incomplete Redis bulk-string response")
    except (OSError, socket.timeout) as e:
        pytest.fail(f"Failed to connect to Redis at 127.0.0.1:6379 or execute GET. Is it running? Error: {e}")

    try:
        return float(raw_value.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        pytest.fail(f"Redis value {raw_value!r} is not a valid float")


def post_prepare(payload):
    try:
        response = requests.post(URL, json=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the Rust web service at 127.0.0.1:3000. Is it running? Error: {e}")

    assert response.status_code == 200, \
        f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except (json.JSONDecodeError, requests.exceptions.JSONDecodeError):
        pytest.fail(f"Failed to parse JSON response from the Rust service. Response: {response.text}")

    assert "original" in data, "Response JSON missing 'original' key"
    assert "bootstraps" in data, "Response JSON missing 'bootstraps' key"
    return data


def expected_scaled(payload, sample_std):
    rows = len(payload)
    cols = len(payload[0])
    means = [sum(row[j] for row in payload) / rows for j in range(cols)]
    denominator = rows - 1 if sample_std else rows
    stds = [
        math.sqrt(sum((row[j] - means[j]) ** 2 for row in payload) / denominator)
        for j in range(cols)
    ]
    return [
        [0.0 if stds[j] == 0.0 else (row[j] - means[j]) / stds[j] for j in range(cols)]
        for row in payload
    ]


def rows_close(actual, expected):
    return len(actual) == len(expected) and all(
        len(a_row) == len(e_row) and all(
            isinstance(a, (int, float)) and math.isfinite(a) and
            math.isclose(a, e, rel_tol=1e-3, abs_tol=1e-4)
            for a, e in zip(a_row, e_row)
        )
        for a_row, e_row in zip(actual, expected)
    )


def assert_complete_result(data, payload, label):
    original = data["original"]
    bootstraps = data["bootstraps"]
    num_rows = len(payload)
    num_cols = len(payload[0])

    assert isinstance(original, list), f"{label}: 'original' must be an array"
    assert len(original) == num_rows, \
        f"{label}: expected {num_rows} rows in 'original', got {len(original)}"
    for i, row in enumerate(original):
        assert isinstance(row, list) and len(row) == num_cols, \
            f"{label}: expected {num_cols} columns in original row {i}"

    assert isinstance(bootstraps, list), f"{label}: 'bootstraps' must be an array"
    assert len(bootstraps) == 5, f"{label}: expected 5 bootstraps, got {len(bootstraps)}"

    pop_expected = expected_scaled(payload, sample_std=False)
    sample_expected = expected_scaled(payload, sample_std=True)
    if rows_close(original, pop_expected):
        expected = pop_expected
    elif rows_close(original, sample_expected):
        expected = sample_expected
    else:
        pytest.fail(
            f"{label}: original data was not scaled using statistics from only the input dataset. "
            f"Payload: {payload!r}; response: {original!r}"
        )

    for i in range(num_rows):
        for j in range(num_cols):
            assert math.isclose(original[i][j], expected[i][j], rel_tol=1e-3, abs_tol=1e-4), \
                f"{label}: mismatch in 'original' at [{i}][{j}]. Expected {expected[i][j]}, got {original[i][j]}"

    for b_idx, boot in enumerate(bootstraps):
        assert isinstance(boot, list) and len(boot) == num_rows, \
            f"{label}: expected {num_rows} rows in bootstrap {b_idx}, got {len(boot) if isinstance(boot, list) else type(boot)}"
        for r_idx, row in enumerate(boot):
            assert isinstance(row, list) and len(row) == num_cols, \
                f"{label}: expected {num_cols} columns in bootstrap {b_idx} row {r_idx}"
            assert all(isinstance(v, (int, float)) and math.isfinite(v) for v in row), \
                f"{label}: bootstrap {b_idx} row {r_idx} contains a non-finite or non-numeric value"
            matched = any(
                all(math.isclose(row[j], exp_row[j], rel_tol=1e-3, abs_tol=1e-4) for j in range(num_cols))
                for exp_row in expected
            )
            assert matched, \
                f"{label}: bootstrap {b_idx} row {r_idx} ({row}) does not match any correctly scaled original row. Data leak might still exist."

    return max(abs(value) for row in expected for value in row)


def test_rust_service_and_redis():
    # Preserve the original fixed case and its detailed numerical checks.
    payload = [[10.0, 20.0], [20.0, 20.0], [30.0, 80.0]]
    data = post_prepare(payload)
    original = data["original"]
    bootstraps = data["bootstraps"]

    assert len(original) == 3, f"Expected 3 rows in 'original', got {len(original)}"
    assert len(original[0]) == 2, f"Expected 2 columns in 'original', got {len(original[0])}"
    assert len(bootstraps) == 5, f"Expected 5 bootstraps, got {len(bootstraps)}"

    val_0_0 = original[0][0]
    if math.isclose(val_0_0, -1.224744871391589, rel_tol=1e-3):
        std_0 = math.sqrt(200 / 3)
        std_1 = math.sqrt(800)
    elif math.isclose(val_0_0, -1.0, rel_tol=1e-3):
        std_0 = 10.0
        std_1 = math.sqrt(1200)
    else:
        pytest.fail(f"Scaling is incorrect. Expected first element to be approx -1.2247 (pop std) or -1.0 (sample std), got {val_0_0}")

    expected_original = [
        [(10.0 - 20.0) / std_0, (20.0 - 40.0) / std_1],
        [(20.0 - 20.0) / std_0, (20.0 - 40.0) / std_1],
        [(30.0 - 20.0) / std_0, (80.0 - 40.0) / std_1],
    ]

    for i in range(3):
        for j in range(2):
            assert math.isclose(original[i][j], expected_original[i][j], rel_tol=1e-3, abs_tol=1e-4), \
                f"Mismatch in 'original' at [{i}][{j}]. Expected {expected_original[i][j]}, got {original[i][j]}"

    for b_idx, boot in enumerate(bootstraps):
        assert len(boot) == 3, f"Expected 3 rows in bootstrap {b_idx}, got {len(boot)}"
        for r_idx, row in enumerate(boot):
            assert len(row) == 2, f"Expected 2 columns in bootstrap {b_idx} row {r_idx}, got {len(row)}"
            matched = any(
                math.isclose(row[0], exp_row[0], rel_tol=1e-3, abs_tol=1e-4) and
                math.isclose(row[1], exp_row[1], rel_tol=1e-3, abs_tol=1e-4)
                for exp_row in expected_original
            )
            assert matched, f"Bootstrap {b_idx} row {r_idx} ({row}) does not match any correctly scaled original row. Data leak might still exist."

    max_abs_val = max(abs(val) for row in expected_original for val in row)
    redis_val = get_redis_value()
    assert math.isclose(redis_val, max_abs_val, rel_tol=1e-3, abs_tol=1e-4), \
        f"Redis max_abs_val mismatch. Expected approx {max_abs_val}, got {redis_val}"

    # Exercise the implementation on verifier-generated values so fixed responses cannot pass.
    rng = secrets.SystemRandom()
    random_payload = []
    bases = [rng.uniform(-500.0, 500.0) for _ in range(3)]
    scales = [rng.uniform(2.0, 40.0) for _ in range(3)]
    patterns = [(-3.0, 2.0, 7.0), (-1.0, -4.0, 3.0), (2.0, 5.0, -6.0), (6.0, -1.0, 1.0)]
    for pattern in patterns:
        random_payload.append([bases[j] + scales[j] * pattern[j] for j in range(3)])

    random_data = post_prepare(random_payload)
    random_max_abs = assert_complete_result(random_data, random_payload, "generated case")
    random_redis_val = get_redis_value()
    assert math.isclose(random_redis_val, random_max_abs, rel_tol=1e-3, abs_tol=1e-4), \
        f"Redis max_abs_val was not updated for generated input. Expected approx {random_max_abs}, got {random_redis_val}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
