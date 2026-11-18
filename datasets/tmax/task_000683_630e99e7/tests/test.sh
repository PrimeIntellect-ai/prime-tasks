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
import glob
import math
import os
import random
import re
import secrets
import subprocess
import time

import pytest
import requests

SCRIPT = "/home/user/run_server.sh"
IMAGE = "/app/data_plot.png"


def kill_server():
    subprocess.run(["fuser", "-k", "8080/tcp"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)
    time.sleep(0.2)


def render_image(values):
    text = " ".join(str(v) for v in values)
    subprocess.run([
        "convert", "-size", "400x100", "xc:white",
        "-font", "DejaVu-Sans", "-pointsize", "24", "-fill", "black",
        "-draw", f"text 10,50 '{text}'", IMAGE
    ], check=True)


def listener_is_native_elf():
    result = subprocess.run(["fuser", "-n", "tcp", "8080"],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True)
    pids = [int(x) for x in re.findall(r"\d+", result.stdout)]
    for pid in pids:
        try:
            exe = os.readlink(f"/proc/{pid}/exe")
            with open(f"/proc/{pid}/exe", "rb") as f:
                if f.read(4) == b"\x7fELF":
                    return True, exe
        except (FileNotFoundError, PermissionError, OSError):
            pass
    return False, None


def start_and_query():
    kill_server()
    process = subprocess.Popen(
        ["/bin/bash", SCRIPT],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        cwd="/home/user"
    )

    response = None
    try:
        for _ in range(60):
            try:
                response = requests.get("http://127.0.0.1:8080/embedding", timeout=1)
                if response.status_code == 200:
                    break
            except requests.exceptions.RequestException:
                pass
            time.sleep(0.5)
        else:
            pytest.fail("Server did not start or did not respond with 200 OK on /embedding within 30 seconds.")

        native, exe = listener_is_native_elf()
        assert native, "The process listening on port 8080 must be a compiled native C++ server"
        return response
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        kill_server()


def parse_response(response):
    data = response.json()
    assert "mean" in data, "Response JSON missing 'mean'"
    assert "std" in data, "Response JSON missing 'std'"
    assert "embedding" in data, "Response JSON missing 'embedding'"

    mean = float(data["mean"])
    std = float(data["std"])
    embedding = data["embedding"]
    assert math.isfinite(mean), "mean must be finite"
    assert math.isfinite(std) and std > 0, "std must be finite and positive"
    assert isinstance(embedding, list), "'embedding' should be a list"
    return mean, std, embedding


def test_run_server_script_exists():
    assert os.path.isfile(SCRIPT), "run_server.sh does not exist"
    assert os.access(SCRIPT, os.X_OK), "run_server.sh is not executable"


def test_cpp_and_ocr_artifacts_exist():
    sources = []
    for pattern in ("/home/user/**/*.cpp", "/home/user/**/*.cc", "/home/user/**/*.cxx"):
        sources.extend(glob.glob(pattern, recursive=True))
    assert sources, "No C++ source file was provided under /home/user"

    cpp_texts = []
    for path in sources:
        try:
            with open(path, "r", errors="ignore") as f:
                cpp_texts.append(f.read())
        except OSError:
            pass
    assert any(all(token in text.lower() for token in ("mean", "std", "embedding"))
               for text in cpp_texts), "C++ source does not implement the requested embedding response"

    artifact_text = "\n".join(cpp_texts)
    for path in glob.glob("/home/user/**/*", recursive=True):
        try:
            if os.path.isfile(path) and os.path.getsize(path) <= 1024 * 1024:
                with open(path, "r", errors="ignore") as f:
                    artifact_text += "\n" + f.read()
        except OSError:
            pass
    lowered = artifact_text.lower()
    assert "tesseract" in lowered or "tessbaseapi" in lowered, \
        "No use of Tesseract OCR was found in the submitted implementation"


def test_original_image_response():
    expected_values = [12, 15, 22, 29, 35]
    render_image(expected_values)
    response = start_and_query()
    mean, std, embedding = parse_response(response)

    assert len(embedding) == 5, f"Expected 5 embedding values, got {len(embedding)}"
    assert math.isclose(mean, 22.6, rel_tol=0.05), f"Expected mean ~22.6, got {mean}"
    assert 7.0 < std < 10.0, f"Standard deviation {std} is outside expected range"

    for i, val in enumerate(expected_values):
        expected_z = (val - mean) / std
        assert math.isclose(float(embedding[i]), expected_z, rel_tol=0.1, abs_tol=0.1), \
            f"Embedding at index {i} expected ~{expected_z}, got {embedding[i]}"


def check_generated_case(values):
    render_image(values)
    response = start_and_query()
    mean, std, embedding = parse_response(response)

    assert len(embedding) == len(values), \
        f"Expected {len(values)} embedding values, got {len(embedding)}"

    expected_mean = sum(values) / len(values)
    population_std = math.sqrt(sum((v - expected_mean) ** 2 for v in values) / len(values))
    sample_std = math.sqrt(sum((v - expected_mean) ** 2 for v in values) / (len(values) - 1))

    assert math.isclose(mean, expected_mean, rel_tol=0.01, abs_tol=0.02), \
        f"Expected mean {expected_mean}, got {mean}"
    assert (math.isclose(std, population_std, rel_tol=0.03, abs_tol=0.03) or
            math.isclose(std, sample_std, rel_tol=0.03, abs_tol=0.03)), \
        f"Expected population std {population_std} or sample std {sample_std}, got {std}"

    for i, value in enumerate(values):
        expected_z = (value - mean) / std
        assert math.isclose(float(embedding[i]), expected_z, rel_tol=0.03, abs_tol=0.04), \
            f"Embedding at index {i} expected {expected_z}, got {embedding[i]}"


def test_ocr_on_unseen_images():
    rng = random.Random(secrets.randbits(128))
    pool = [23, 24, 26, 27, 32, 34, 36, 38, 42, 43, 46, 47,
            52, 54, 56, 58, 62, 63, 67, 68, 72, 74, 76, 78, 82, 84, 86, 87]
    first = rng.sample(pool, 4)
    remaining = [v for v in pool if v not in first]
    second = rng.sample(remaining, 6)
    check_generated_case(first)
    check_generated_case(second)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
