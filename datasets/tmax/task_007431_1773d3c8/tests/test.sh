#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess

import pytest

SOURCE = "/home/user/process_requests.c"
EXECUTABLE = "/home/user/process_requests"
REQUESTS = "/home/user/requests.txt"
RESULTS = "/home/user/results.csv"
COMPILED_COPY = "/tmp/process_requests_from_source"

with open(REQUESTS, "rb") as f:
    ORIGINAL_REQUESTS = f.read()
ORIGINAL_RESULTS = None
if os.path.isfile(RESULTS):
    with open(RESULTS, "rb") as f:
        ORIGINAL_RESULTS = f.read()


@pytest.fixture(scope="module", autouse=True)
def restore_input_files():
    yield
    with open(REQUESTS, "wb") as f:
        f.write(ORIGINAL_REQUESTS)
    if ORIGINAL_RESULTS is None:
        try:
            os.unlink(RESULTS)
        except FileNotFoundError:
            pass
    else:
        with open(RESULTS, "wb") as f:
            f.write(ORIGINAL_RESULTS)


def run_program(program, request_text):
    with open(REQUESTS, "w", encoding="utf-8") as f:
        f.write(request_text)
    try:
        os.unlink(RESULTS)
    except FileNotFoundError:
        pass

    completed = subprocess.run(
        [program],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert completed.returncode == 0, (
        f"{program} exited with status {completed.returncode}. "
        f"stderr: {completed.stderr}"
    )
    assert os.path.exists(RESULTS), f"{program} did not create {RESULTS}."
    assert os.path.isfile(RESULTS), f"{RESULTS} is not a regular file."
    with open(RESULTS, "r", encoding="utf-8") as f:
        return f.read().strip().splitlines()


def polygon_area(vertices):
    twice_area = 0.0
    for i, (x1, y1) in enumerate(vertices):
        x2, y2 = vertices[(i + 1) % len(vertices)]
        twice_area += x1 * y2 - x2 * y1
    return abs(twice_area) / 2.0


def make_altered_case():
    seed = secrets.randbits(64)
    rng = random.Random(seed)
    users = rng.sample(range(1, 101), 5)
    special_user = users[0]

    # These timestamps explicitly exercise the strict 1000 ms boundary and
    # ensure rejected requests do not themselves consume rate-limit capacity.
    events = [
        (10000, special_user),
        (10100, special_user),
        (10999, special_user),
        (11000, special_user),
        (11099, special_user),
        (11100, special_user),
    ]

    timestamp = 12000
    for _ in range(70):
        timestamp += rng.choice([0, 40, 100, 250, 500, 999, 1000])
        events.append((timestamp, rng.choice(users)))

    records = []
    for index, (timestamp, user_id) in enumerate(events):
        w = rng.randint(2, 11)
        h = rng.randint(2, 9)
        shift = rng.randint(-15, 15)
        kind = index % 4
        if kind == 0:
            points = [(0, 0), (w, 0), (w, h), (0, h)]
        elif kind == 1:
            points = [(0, 0), (w, 0), (0, h)]
        elif kind == 2:
            slant = rng.randint(-4, 4)
            points = [(0, 0), (w, 0), (w + slant, h), (slant, h)]
        else:
            points = [(0, 0), (w, 0), (w, h), (w // 2, h // 2), (0, h)]

        # Half-unit translations require genuine floating-point coordinate parsing
        # while preserving exactly representable integer/half-integer areas.
        tx = shift + (0.5 if index % 3 == 0 else 0.0)
        ty = -shift + (0.5 if index % 5 == 0 else 0.0)
        vertices = [(x + tx, y + ty) for x, y in points]
        records.append((timestamp, user_id, vertices))

    lines = []
    expected = []
    accepted = {user: [] for user in users}
    for timestamp, user_id, vertices in records:
        coordinates = " ".join(f"{x:g},{y:g}" for x, y in vertices)
        lines.append(f"{timestamp} {user_id} {coordinates}")

        recent = [old for old in accepted[user_id] if timestamp - old < 1000]
        accepted[user_id] = recent
        if len(recent) < 2:
            accepted[user_id].append(timestamp)
            expected.append(f"{user_id},{polygon_area(vertices):.1f}")

    return "\n".join(lines) + "\n", expected, seed


def test_source_code_exists():
    """Test that the C source code file exists."""
    file_path = SOURCE
    assert os.path.exists(file_path), f"File {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a file."


def test_executable_exists():
    """Test that the compiled executable exists."""
    file_path = EXECUTABLE
    assert os.path.exists(file_path), f"Executable {file_path} is missing. Did you compile your code?"
    assert os.path.isfile(file_path), f"{file_path} is not a file."
    assert os.access(file_path, os.X_OK), f"{file_path} is not executable."
    with open(file_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{file_path} is not a compiled ELF executable."


def test_results_csv_content():
    """Run the submitted executable and check the required original input."""
    expected_lines = [
        "1,12.0",
        "2,25.0",
        "1,4.0",
        "1,25.0",
        "2,12.0",
        "2,4.0",
    ]
    actual = run_program(EXECUTABLE, ORIGINAL_REQUESTS.decode("utf-8"))

    assert len(actual) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in {RESULTS}, but found {len(actual)}."
    )
    for i, (got, expected) in enumerate(zip(actual, expected_lines)):
        assert got.strip() == expected, (
            f"Line {i + 1} in {RESULTS} is incorrect. "
            f"Expected '{expected}', got '{got.strip()}'."
        )


def test_submitted_executable_on_altered_requests():
    request_text, expected, seed = make_altered_case()
    actual = run_program(EXECUTABLE, request_text)
    assert actual == expected, (
        f"Submitted executable failed generated parsing/area/rate-limit case "
        f"(seed {seed}).\nExpected: {expected}\nActual: {actual}"
    )


def test_source_builds_and_implements_behavior():
    build = subprocess.run(
        ["gcc", "-std=c11", SOURCE, "-o", COMPILED_COPY, "-lm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert build.returncode == 0, f"The submitted C source does not compile: {build.stderr}"

    request_text, expected, seed = make_altered_case()
    actual = run_program(COMPILED_COPY, request_text)
    assert actual == expected, (
        f"Program compiled from submitted source failed generated parsing/area/"
        f"rate-limit case (seed {seed}).\nExpected: {expected}\nActual: {actual}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
