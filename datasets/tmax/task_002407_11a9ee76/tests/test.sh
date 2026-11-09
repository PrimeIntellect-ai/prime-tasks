#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import math
import os
import random
import re
import struct
import subprocess
import tempfile


def test_cpp_fixes_applied():
    path = "/home/user/math_util.cpp"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()

    # Preserve the original source-level assertions.
    assert "a.distance <= b.distance" not in content, "Bug 1 (strict weak ordering) is still present. Use '<' instead of '<='."
    assert "new Point[num_points - 1]" not in content, "Bug 2 (buffer overflow) is still present. Allocate the correct number of points."
    assert "delete points;" not in content, "Bug 3 (wrong delete) is still present. Use 'delete[] points;' or std::vector."


def test_executable_exists():
    path = "/home/user/math_util"
    assert os.path.isfile(path), f"Executable {path} does not exist. Did you compile the code?"
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "math_util must be a compiled executable."


def _parse_and_validate_output(path, points):
    assert os.path.isfile(path), f"Utility did not create output file {path}."
    with open(path, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()

    assert len(lines) == len(points), f"Expected {len(points)} output rows, got {len(lines)}."

    expected = {}
    for pid, x, y, z in points:
        # Inputs have already been rounded to IEEE-754 float values by packing.
        expected[pid] = math.sqrt(x * x + y * y + z * z)

    seen = []
    number = r"(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?"
    pattern = re.compile(rf"^(-?[0-9]+),([+-]?{number})$")
    for line in lines:
        match = pattern.fullmatch(line)
        assert match, f"Invalid CSV row: {line!r}"
        pid = int(match.group(1))
        distance = float(match.group(2))
        assert pid in expected, f"Unexpected point id {pid}."
        assert pid not in [item[0] for item in seen], f"Duplicate point id {pid}."
        assert math.isfinite(distance) and distance >= 0.0, f"Invalid distance for id {pid}."
        assert math.isclose(distance, expected[pid], rel_tol=2e-5, abs_tol=1e-5), \
            f"Wrong distance for id {pid}: got {distance}, expected {expected[pid]}."
        seen.append((pid, distance))

    assert {pid for pid, _ in seen} == set(expected), "Output omitted or duplicated points."
    for (left_id, left_printed), (right_id, right_printed) in zip(seen, seen[1:]):
        assert left_printed <= right_printed + 1e-6, "Output distances are not sorted ascending."
        assert expected[left_id] <= expected[right_id] + 1e-6, "Points are not sorted by their calculated distances."


def _write_dataset(path, points):
    raw = b"".join(struct.pack("<iffff", pid, x, y, z, 0.0) for pid, x, y, z in points)
    with open(path, "w", encoding="ascii") as f:
        f.write(base64.b64encode(raw).decode("ascii"))
        f.write("\n")


def _run_case(executable, points):
    with tempfile.TemporaryDirectory(prefix="math-util-case-") as directory:
        input_path = os.path.join(directory, "input.b64")
        output_path = os.path.join(directory, "output.csv")
        _write_dataset(input_path, points)
        result = subprocess.run(
            [executable, input_path, output_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"Utility exited with {result.returncode}. stderr: "
            f"{result.stderr.decode(errors='replace')}"
        )
        _parse_and_validate_output(output_path, points)


def _float32(value):
    return struct.unpack("<f", struct.pack("<f", value))[0]


def _dynamic_cases():
    cases = [
        [],
        [(101, _float32(1.25), _float32(-2.5), _float32(4.0))],
        [
            (11, _float32(3.0), _float32(4.0), _float32(0.0)),
            (-7, _float32(0.0), _float32(0.0), _float32(0.0)),
            (12, _float32(-3.0), _float32(0.0), _float32(4.0)),
            (99, _float32(0.125), _float32(0.25), _float32(0.5)),
        ],
    ]

    rng = random.SystemRandom()
    ids = rng.sample(range(-1000000000, 1000000000), 41)
    generated = []
    for pid in ids:
        coordinates = tuple(_float32(rng.uniform(-10000.0, 10000.0)) for _ in range(3))
        generated.append((pid, *coordinates))
    rng.shuffle(generated)
    cases.append(generated)
    return cases


def test_executable_and_source_behavior():
    source = "/home/user/math_util.cpp"
    installed = "/home/user/math_util"
    cases = _dynamic_cases()

    # Exercise the artifact supplied by the agent on verifier-generated inputs.
    for points in cases:
        _run_case(installed, points)

    # Independently compile the submitted source and exercise that build too.
    with tempfile.TemporaryDirectory(prefix="math-util-build-") as directory:
        rebuilt = os.path.join(directory, "math_util")
        result = subprocess.run(
            ["g++", "-O2", "-std=c++17", source, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, (
            "Submitted source does not compile with the required command: "
            + result.stderr.decode(errors="replace")
        )
        for points in cases:
            _run_case(rebuilt, points)


def test_memory_safety_under_valgrind():
    rng = random.SystemRandom()
    points = []
    for pid in rng.sample(range(1, 10000000), 29):
        points.append((
            pid,
            _float32(rng.uniform(-500.0, 500.0)),
            _float32(rng.uniform(-500.0, 500.0)),
            _float32(rng.uniform(-500.0, 500.0)),
        ))

    with tempfile.TemporaryDirectory(prefix="math-util-valgrind-") as directory:
        input_path = os.path.join(directory, "input.b64")
        output_path = os.path.join(directory, "output.csv")
        log_path = os.path.join(directory, "valgrind.log")
        _write_dataset(input_path, points)
        result = subprocess.run(
            [
                "valgrind", "--quiet", "--error-exitcode=97",
                "--leak-check=full", "--show-leak-kinds=all",
                "--errors-for-leak-kinds=definite,indirect,possible",
                f"--log-file={log_path}",
                "/home/user/math_util", input_path, output_path,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        log = ""
        if os.path.exists(log_path):
            with open(log_path, "r", errors="replace") as f:
                log = f.read()
        assert result.returncode == 0, f"Valgrind detected memory errors or leaks:\n{log}"
        _parse_and_validate_output(output_path, points)


def test_output_csv_correct():
    out_path = "/home/user/output.csv"
    assert os.path.isfile(out_path), f"Output file {out_path} does not exist."

    b64_path = "/home/user/data.b64"
    assert os.path.isfile(b64_path), f"Data file {b64_path} does not exist."

    with open(b64_path, "r") as f:
        b64_data = f.read().strip()
    bin_data = base64.b64decode(b64_data)

    points = []
    for i in range(0, len(bin_data), 20):
        chunk = bin_data[i:i + 20]
        if len(chunk) < 20:
            break
        pid, x, y, z, _ = struct.unpack("<iffff", chunk)
        points.append((pid, x, y, z))

    # Independently validate the existing output against the provided input.
    _parse_and_validate_output(out_path, points)

    exp_path = "/home/user/expected.csv"
    assert os.path.isfile(exp_path), f"Expected file {exp_path} does not exist."
    with open(exp_path, "r") as f:
        expected_content = f.read().strip().splitlines()
    with open(out_path, "r") as f:
        actual_content = f.read().strip().splitlines()

    # Preserve the original exact comparison assertion.
    assert actual_content == expected_content, "The content of output.csv does not match expected.csv."


def test_diff_result_empty():
    path = "/home/user/diff_result.txt"
    assert os.path.isfile(path), f"Diff result file {path} does not exist."
    size = os.path.getsize(path)
    assert size == 0, f"Diff result file {path} is not empty. This means output.csv does not exactly match expected.csv."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
