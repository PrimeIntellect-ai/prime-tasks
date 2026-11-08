#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import subprocess
import tempfile
import urllib.error
import urllib.request

import pytest

PROJECT = "/home/user/project"
NATIVE_BIN = f"{PROJECT}/bin/math_filter_native"
WASM_BIN = f"{PROJECT}/bin/math_filter.wasm"
MANIFEST = f"{PROJECT}/math_filter/Cargo.toml"
VIDEO = "/app/pendulum_experiment.mp4"


def run_checked(command, **kwargs):
    return subprocess.run(command, check=True, capture_output=True, **kwargs)


def decode_rgb(path):
    proc = run_checked([
        "ffmpeg", "-v", "error", "-i", path,
        "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"
    ])
    expected_size = 640 * 480 * 3
    assert len(proc.stdout) == expected_size, f"{path} is not a valid 640x480 image"
    return proc.stdout


def assert_visually_matches(actual_path, expected_path):
    actual = decode_rgb(actual_path)
    expected = decode_rgb(expected_path)

    # Sample throughout the decoded image. This permits harmless JPEG encoder
    # variation while rejecting placeholders and frames from the wrong time.
    indices = range(0, len(expected), 97)
    differences = [abs(actual[i] - expected[i]) for i in indices]
    mean_error = sum(differences) / len(differences)
    large_error_fraction = sum(d > 25 for d in differences) / len(differences)
    assert mean_error <= 6.0 and large_error_fraction <= 0.05, (
        f"{actual_path} does not match the corresponding frame extracted from the video "
        f"(mean error {mean_error:.3f}, large-error fraction {large_error_fraction:.3f})"
    )


def test_frames_extraction_and_organization():
    even_dir = f"{PROJECT}/frames/even/"
    odd_dir = f"{PROJECT}/frames/odd/"

    assert os.path.isdir(even_dir), f"Directory {even_dir} does not exist."
    assert os.path.isdir(odd_dir), f"Directory {odd_dir} does not exist."

    expected_even = [f"frame_{i:04d}.jpg" for i in range(2, 51, 2)]
    expected_odd = [f"frame_{i:04d}.jpg" for i in range(1, 51, 2)]
    even_files = sorted(f for f in os.listdir(even_dir) if f.endswith(".jpg"))
    odd_files = sorted(f for f in os.listdir(odd_dir) if f.endswith(".jpg"))

    assert len(even_files) == 25, f"Expected 25 even frames, found {len(even_files)}."
    assert len(odd_files) == 25, f"Expected 25 odd frames, found {len(odd_files)}."
    assert "frame_0002.jpg" in even_files, "frame_0002.jpg missing from even directory."
    assert "frame_0001.jpg" in odd_files, "frame_0001.jpg missing from odd directory."
    assert even_files == expected_even, "Even directory does not contain exactly the even-numbered frames."
    assert odd_files == expected_odd, "Odd directory does not contain exactly the odd-numbered frames."

    with tempfile.TemporaryDirectory() as expected_dir:
        run_checked([
            "ffmpeg", "-v", "error", "-i", VIDEO,
            "-vf", "fps=5", "-start_number", "1",
            os.path.join(expected_dir, "frame_%04d.jpg")
        ])
        expected_files = sorted(f for f in os.listdir(expected_dir) if f.endswith(".jpg"))
        assert expected_files == [f"frame_{i:04d}.jpg" for i in range(1, 51)], (
            "The source video did not independently produce the expected 50 frames."
        )

        for name in expected_even:
            assert_visually_matches(os.path.join(even_dir, name), os.path.join(expected_dir, name))
        for name in expected_odd:
            assert_visually_matches(os.path.join(odd_dir, name), os.path.join(expected_dir, name))


def test_nginx_proxy():
    url_even = "http://127.0.0.1:8080/assets/even/frame_0002.jpg"
    try:
        with urllib.request.urlopen(urllib.request.Request(url_even), timeout=5) as response:
            assert response.status == 200, f"Expected status 200, got {response.status}"
            content = response.read()
            assert len(content) > 0, "Empty response from nginx"
            with open(f"{PROJECT}/frames/even/frame_0002.jpg", "rb") as file:
                expected_content = file.read()
            assert content == expected_content, "Nginx served content does not match the actual file content."
    except urllib.error.URLError as error:
        pytest.fail(f"Failed to connect to nginx at {url_even}: {error}")

    url_odd = "http://127.0.0.1:8080/assets/odd/frame_0001.jpg"
    try:
        with urllib.request.urlopen(urllib.request.Request(url_odd), timeout=5) as response:
            assert response.status == 200, f"Expected status 200, got {response.status}"
            content = response.read()
            with open(f"{PROJECT}/frames/odd/frame_0001.jpg", "rb") as file:
                assert content == file.read(), "Nginx served the wrong odd frame content."
    except urllib.error.URLError as error:
        pytest.fail(f"Failed to connect to nginx at {url_odd}: {error}")


def expected_output(input_text):
    values = []
    for token in input_text.split():
        try:
            values.append(float(token))
        except ValueError:
            pass

    if not values:
        return "0.0"

    first = values[0]
    accumulator = 0.0
    for index in range(1, len(values)):
        values[index] = (values[index] + values[index - 1]) * 0.5
        accumulator += values[index] * math.sin(first)
    return f"{accumulator:.6f}"


def execute_artifact(command, input_text):
    try:
        proc = subprocess.run(
            command,
            input=input_text,
            text=True,
            capture_output=True,
            check=True,
            timeout=15,
        )
    except subprocess.CalledProcessError as error:
        pytest.fail(f"Artifact crashed: {error.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail("Artifact timed out")
    return proc.stdout.strip()


def test_rust_binaries_exist_and_source_cross_compiles():
    assert os.path.isfile(NATIVE_BIN), f"Native binary missing at {NATIVE_BIN}"
    assert os.access(NATIVE_BIN, os.X_OK), f"Native binary {NATIVE_BIN} is not executable"
    assert os.path.isfile(WASM_BIN), f"WASM binary missing at {WASM_BIN}"

    with open(WASM_BIN, "rb") as file:
        assert file.read(4) == b"\\x00asm", f"{WASM_BIN} is not a WebAssembly module"

    run_checked([
        "/opt/cargo/bin/cargo", "build", "--release", "--manifest-path", MANIFEST
    ], text=True)
    run_checked([
        "/opt/cargo/bin/cargo", "build", "--release", "--target", "wasm32-wasip1",
        "--manifest-path", MANIFEST
    ], text=True)


def test_native_fuzz_equivalence():
    random.seed(42)
    cases = ["", "1", "1 2 3", "bad 2 4", "-1.5 0 3.25"]
    for _ in range(1000):
        length = random.randint(10, 500)
        numbers = [random.uniform(0.0, 255.0) for _ in range(length)]
        cases.append(" ".join(f"{number:.6f}" for number in numbers))

    for index, input_text in enumerate(cases):
        actual = execute_artifact([NATIVE_BIN], input_text)
        expected = expected_output(input_text)
        assert actual == expected, (
            f"Native mismatch on case {index}. Expected {expected!r}, got {actual!r}."
        )


def test_wasm_executes_with_equivalent_behavior():
    random.seed(9173)
    cases = ["", "1", "1 2 3", "bad 2 4", "-1.5 0 3.25"]
    for _ in range(50):
        length = random.randint(2, 100)
        numbers = [random.uniform(-50.0, 255.0) for _ in range(length)]
        cases.append(" ".join(f"{number:.6f}" for number in numbers))

    for index, input_text in enumerate(cases):
        actual = execute_artifact(["/usr/local/bin/wasmtime", "run", WASM_BIN], input_text)
        expected = expected_output(input_text)
        assert actual == expected, (
            f"WASM mismatch on case {index}. Expected {expected!r}, got {actual!r}."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
