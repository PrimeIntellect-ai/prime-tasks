#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import math
import os
import time

import cv2
import numpy as np
import requests

VIDEO_PATH = "/app/surveillance.mp4"


def install_random_test_video():
    """Replace the video with an unpredictable fixture before exercising the API."""
    rng = np.random.default_rng(int.from_bytes(os.urandom(16), "big"))
    temp_path = "/app/verifier-surveillance.mp4"
    width, height = 96, 64
    writer = cv2.VideoWriter(
        temp_path,
        cv2.VideoWriter_fourcc(*"mp4v"),
        30.0,
        (width, height),
    )
    assert writer.isOpened(), "Could not create verifier video fixture"

    yy, xx = np.indices((height, width))
    for i in range(45):
        phase = int(rng.integers(0, 256))
        scale = int(rng.integers(1, 8))
        noise = rng.integers(0, 80, size=(height, width), dtype=np.uint8)
        base = ((xx * scale + yy * (scale + 3) + phase + i * 11) % 256).astype(np.uint8)
        gray = ((base.astype(np.uint16) + noise.astype(np.uint16)) % 256).astype(np.uint8)
        frame = cv2.merge((gray, np.roll(gray, i % 9, axis=1), np.roll(gray, i % 7, axis=0)))
        writer.write(frame)
    writer.release()
    assert os.path.exists(temp_path) and os.path.getsize(temp_path) > 0
    os.replace(temp_path, VIDEO_PATH)


def expected_motion_index(start_frame, end_frame):
    cap = cv2.VideoCapture(VIDEO_PATH)
    assert cap.isOpened(), "Could not open verifier video fixture"
    cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame)
    frames = []
    for _ in range(end_frame - start_frame):
        ret, frame = cap.read()
        if not ret:
            break
        frames.append(cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY))
    cap.release()

    if len(frames) < 2:
        return 0.0

    values = []
    for previous, current in zip(frames, frames[1:]):
        diff = np.abs(current.astype(np.float32) - previous.astype(np.float32))
        variance = float(np.var(diff))
        assert variance >= 0.0 and not math.isnan(variance)
        values.append(math.sqrt(variance))
    return sum(values) / len(values)


def assert_motion_response(response, expected, description):
    assert response.status_code == 200, (
        f"Expected 200 OK for {description}, got {response.status_code}. "
        f"Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        assert False, f"Response is not valid JSON: {response.text}"

    assert "motion_index" in data, "Response missing 'motion_index' key"
    assert isinstance(data["motion_index"], (float, int)), "motion_index must be a number"
    actual = float(data["motion_index"])
    assert math.isfinite(actual), "motion_index must be finite"
    assert math.isclose(actual, expected, rel_tol=1e-5, abs_tol=1e-4), (
        f"Incorrect motion_index for {description}: expected {expected}, got {actual}"
    )


def test_api_server_responses():
    install_random_test_video()
    url = "http://127.0.0.1:8080/analyze"
    headers = {"X-Ops-Token": "triage-2024"}

    max_retries = 5
    for i in range(max_retries):
        try:
            params1 = {"start_frame": 10, "end_frame": 30}
            resp1 = requests.get(url, params=params1, headers=headers, timeout=5)
            break
        except requests.exceptions.ConnectionError:
            if i == max_retries - 1:
                assert False, "API server is not running or not reachable on 127.0.0.1:8080"
            time.sleep(1)

    assert_motion_response(resp1, expected_motion_index(10, 30), "frames 10 through 30")

    params2 = {"start_frame": 0, "end_frame": 2}
    resp2 = requests.get(url, params=params2, headers=headers, timeout=5)
    assert_motion_response(resp2, expected_motion_index(0, 2), "frames 0 through 2")


def _same_expression(left, right):
    return ast.dump(left, include_attributes=False) == ast.dump(right, include_attributes=False)


def _asserts_nonnegative(node, expression):
    for candidate in ast.walk(node):
        if not isinstance(candidate, ast.Compare) or len(candidate.ops) != 1 or len(candidate.comparators) != 1:
            continue
        left, right = candidate.left, candidate.comparators[0]
        if isinstance(candidate.ops[0], ast.GtE) and _same_expression(left, expression):
            if isinstance(right, ast.Constant) and right.value == 0:
                return True
        if isinstance(candidate.ops[0], ast.LtE) and _same_expression(right, expression):
            if isinstance(left, ast.Constant) and left.value == 0:
                return True
    return False


def _is_isnan_call(node, expression):
    if not isinstance(node, ast.Call) or len(node.args) != 1:
        return False
    function = node.func
    name = function.attr if isinstance(function, ast.Attribute) else function.id if isinstance(function, ast.Name) else None
    return name == "isnan" and _same_expression(node.args[0], expression)


def _asserts_not_nan(node, expression):
    for candidate in ast.walk(node):
        if isinstance(candidate, ast.UnaryOp) and isinstance(candidate.op, ast.Not):
            if _is_isnan_call(candidate.operand, expression):
                return True
        if isinstance(candidate, ast.Compare) and len(candidate.ops) == 1:
            if isinstance(candidate.ops[0], (ast.Is, ast.Eq)):
                sides = (candidate.left, candidate.comparators[0])
                if any(_same_expression(side, expression) for side in sides):
                    other = sides[1] if _same_expression(sides[0], expression) else sides[0]
                    if isinstance(other, ast.Constant) and other.value == other.value:
                        return True
    return False


def _validated_sqrt_exists(statement_list):
    for index, statement in enumerate(statement_list):
        sqrt_calls = []
        for candidate in ast.walk(statement):
            if isinstance(candidate, ast.Call):
                function = candidate.func
                name = function.attr if isinstance(function, ast.Attribute) else function.id if isinstance(function, ast.Name) else None
                if name == "sqrt" and candidate.args:
                    sqrt_calls.append(candidate)

        for call in sqrt_calls:
            validation = []
            previous = index - 1
            while previous >= 0 and isinstance(statement_list[previous], ast.Assert):
                validation.append(statement_list[previous].test)
                previous -= 1
            if validation and any(_asserts_nonnegative(test, call.args[0]) for test in validation) and any(
                _asserts_not_nan(test, call.args[0]) for test in validation
            ):
                return True

        for field in ("body", "orelse", "finalbody"):
            child = getattr(statement, field, None)
            if isinstance(child, list) and _validated_sqrt_exists(child):
                return True
        for handler in getattr(statement, "handlers", []):
            if _validated_sqrt_exists(handler.body):
                return True
    return False


def test_api_code_assertions():
    api_path = "/home/user/api.py"
    assert os.path.exists(api_path), f"File not found: {api_path}"

    with open(api_path, "r") as file:
        content = file.read()

    assert "assert " in content, "No 'assert' statement found in the code. You must add assertion-based intermediate validation."
    tree = ast.parse(content, filename=api_path)
    assert _validated_sqrt_exists(tree.body), (
        "The variance passed to sqrt must be immediately preceded by assertion-based "
        "validation that it is nonnegative and not NaN"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
