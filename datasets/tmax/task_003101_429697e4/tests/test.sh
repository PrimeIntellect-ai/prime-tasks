#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import difflib
import os
import random
import socket
import pytest

EXPECTED_CONTENT = [
    "125 /home/user/project/src/main.c",
    "16 /home/user/project/src/auth.sh",
    "10 /home/user/project/docs/readme.md"
]
EXPECTED_PATHS = [line.split(" ", 1)[1] for line in EXPECTED_CONTENT]


def test_ordered_files_content():
    ordered_files_path = "/home/user/ordered_files.txt"
    assert os.path.isfile(ordered_files_path), f"Missing {ordered_files_path}"

    with open(ordered_files_path, "r") as f:
        content = f.read().strip().splitlines()

    expected_content = EXPECTED_CONTENT

    assert content == expected_content, f"Contents of {ordered_files_path} do not match expected priorities and paths."


def test_order_diff_patch_exists():
    patch_path = "/home/user/order_diff.patch"
    assert os.path.isfile(patch_path), f"Missing {patch_path}"

    with open(patch_path, "r") as f:
        content = f.read()

    # Preserve the original unified-diff checks.
    assert "---" in content and "+++" in content, f"{patch_path} does not look like a unified diff"
    assert "/home/user/project/src/auth.sh" in content, "Patch missing expected file paths"

    # Verify that the patch is the actual unified diff from legacy_order.txt to
    # the extracted paths, allowing only filenames/timestamps in the headers to vary.
    with open("/home/user/legacy_order.txt", "r") as f:
        legacy_lines = f.readlines()
    extracted_lines = [path + "\n" for path in EXPECTED_PATHS]
    expected_diff = list(difflib.unified_diff(
        legacy_lines,
        extracted_lines,
        fromfile="/home/user/legacy_order.txt",
        tofile="extracted_paths"
    ))
    actual_diff = content.splitlines(keepends=True)

    assert len(actual_diff) >= 3, "Unified diff is incomplete"
    assert actual_diff[0].startswith("--- "), "Missing unified diff old-file header"
    assert actual_diff[1].startswith("+++ "), "Missing unified diff new-file header"
    assert "legacy_order.txt" in actual_diff[0], "Diff does not identify the legacy order file"
    assert actual_diff[2:] == expected_diff[2:], "Patch hunks do not match the actual path-order diff"


def send_query(query_str: str) -> str:
    host = "127.0.0.1"
    port = 9000
    try:
        with socket.create_connection((host, port), timeout=2) as s:
            s.settimeout(2)
            s.sendall(query_str.encode("utf-8"))
            response = b""
            while not response.endswith(b"\n"):
                chunk = s.recv(1024)
                if not chunk:
                    break
                response += chunk
            return response.decode("utf-8")
    except Exception as e:
        pytest.fail(f"Failed to connect or communicate with service on {host}:{port}. Error: {e}")


def test_tcp_service_query_1():
    response = send_query("QUERY 2^4\n")
    assert response == "/home/user/project/src/auth.sh\n", f"Unexpected response: {response}"


def test_tcp_service_query_2():
    response = send_query("QUERY 100/10\n")
    assert response == "/home/user/project/docs/readme.md\n", f"Unexpected response: {response}"


def test_tcp_service_query_3():
    response = send_query("QUERY 5*5*5\n")
    assert response == "/home/user/project/src/main.c\n", f"Unexpected response: {response}"


def test_tcp_service_not_found():
    response = send_query("QUERY 999\n")
    assert response == "NOT_FOUND\n", f"Unexpected response: {response}"


def make_expression(value, rng, mode):
    if mode == 0:
        a = rng.randint(2, 19)
        b = rng.randint(2, 19)
        base_expr = f"({a} * {b})"
        base_value = a * b
    elif mode == 1:
        base = rng.randint(2, 5)
        exponent = rng.randint(2, 4)
        base_expr = f"({base}^{exponent})"
        base_value = base ** exponent
    else:
        divisor = rng.randint(2, 11)
        quotient = rng.randint(2, 30)
        numerator = divisor * quotient
        base_expr = f"({numerator} / {divisor})"
        base_value = quotient

    delta = value - base_value
    if delta >= 0:
        return f"({base_expr} + {delta})"
    return f"({base_expr} - {abs(delta)})"


def test_tcp_service_randomized_expression_evaluation_and_lookup():
    # Expressions are generated after the agent has finished, so a responder
    # hardcoded for the four original query strings cannot satisfy this test.
    rng = random.SystemRandom()
    expected_paths = {
        125: "/home/user/project/src/main.c\n",
        16: "/home/user/project/src/auth.sh\n",
        10: "/home/user/project/docs/readme.md\n",
    }

    cases = []
    for priority, path in expected_paths.items():
        for mode in range(3):
            cases.append((make_expression(priority, rng, mode), path))

    missing_values = set()
    while len(missing_values) < 8:
        candidate = rng.randint(20, 500)
        if candidate not in expected_paths:
            missing_values.add(candidate)
    for index, value in enumerate(missing_values):
        cases.append((make_expression(value, rng, index % 3), "NOT_FOUND\n"))

    rng.shuffle(cases)
    for expression, expected in cases:
        response = send_query(f"QUERY {expression}\n")
        assert response == expected, f"Expression {expression!r} returned {response!r}, expected {expected!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
