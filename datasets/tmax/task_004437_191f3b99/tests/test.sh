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
import ctypes
import os
import secrets

import pytest
import requests
from PIL import Image, ImageDraw, ImageFont

URL = "http://127.0.0.1:8080/api/v1/extract"
AUTH_HEADERS = {"Authorization": "Bearer dev-secret-token-99"}
IMAGE_PATH = "/app/data/config_scan.png"
LIB_PATH = "/home/user/libdecoder.so"


def decode_expected(values, x_val=3, xor_key=42):
    return sum(value * (x_val ** index) for index, value in enumerate(values)) ^ xor_key


def test_libdecoder_exists():
    """Verify that the compiled C shared library exists."""
    assert os.path.isfile(LIB_PATH), f"The C shared library {LIB_PATH} does not exist."


def test_libdecoder_function():
    """Load the shared library and exercise decode_values on unpredictable inputs."""
    try:
        library = ctypes.CDLL(LIB_PATH)
    except OSError as exc:
        pytest.fail(f"Failed to load {LIB_PATH} as a shared library: {exc}")

    try:
        decode_values = library.decode_values
    except AttributeError:
        pytest.fail(f"{LIB_PATH} does not export decode_values")

    decode_values.argtypes = [ctypes.POINTER(ctypes.c_int), ctypes.c_int, ctypes.c_int, ctypes.c_int]
    decode_values.restype = ctypes.c_int

    rng = secrets.SystemRandom()
    cases = [[5, 12, 7, 2]]
    cases.extend([rng.choices(range(0, 21), k=rng.randint(1, 7)) for _ in range(12)])

    for values in cases:
        input_array = (ctypes.c_int * len(values))(*values)
        actual = decode_values(input_array, len(values), 3, 42)
        expected = decode_expected(values)
        assert actual == expected, (
            f"decode_values returned {actual} for {values}; expected {expected}"
        )


def test_api_unauthorized():
    """Verify that the API returns 401 when the authorization header is missing or incorrect."""
    payload = {"image_path": IMAGE_PATH}

    try:
        response = requests.post(URL, json=payload, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the server at {URL}: {exc}")

    assert response.status_code == 401, (
        f"Expected 401 Unauthorized for missing auth header, got {response.status_code}. "
        f"Response: {response.text}"
    )

    headers = {"Authorization": "Bearer invalid-token-123"}
    try:
        response = requests.post(URL, json=payload, headers=headers, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the server at {URL}: {exc}")

    assert response.status_code == 401, (
        f"Expected 401 Unauthorized for incorrect auth header, got {response.status_code}. "
        f"Response: {response.text}"
    )


def test_api_not_found():
    """Verify that the API returns 404 when the requested image does not exist."""
    payload = {"image_path": "/app/data/nonexistent.png"}

    try:
        response = requests.post(URL, json=payload, headers=AUTH_HEADERS, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the server at {URL}: {exc}")

    assert response.status_code == 404, (
        f"Expected 404 Not Found for non-existent image, got {response.status_code}. "
        f"Response: {response.text}"
    )


def test_api_success():
    """Verify that the API returns 200 and the correctly decoded value for the supplied image."""
    payload = {"image_path": IMAGE_PATH}

    try:
        response = requests.post(URL, json=payload, headers=AUTH_HEADERS, timeout=10)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the server at {URL}: {exc}")

    assert response.status_code == 200, (
        f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    )

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Failed to parse JSON response. Response text: {response.text}")

    assert data.get("status") == "success", (
        f"Expected status 'success', got {data.get('status')}"
    )

    expected_val = 180
    assert data.get("decoded_value") == expected_val, (
        f"Expected decoded_value {expected_val}, got {data.get('decoded_value')}"
    )


def test_api_ocr_and_decode_dynamic_image():
    """Replace the input with unpredictable text and verify it is actually processed."""
    rng = secrets.SystemRandom()
    while True:
        values = [rng.randint(1, 9) for _ in range(4)]
        expected = decode_expected(values)
        if expected != 180:
            break

    text = " ".join(str(value) for value in values)
    font = ImageFont.truetype(
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 56
    )
    probe = Image.new("RGB", (1, 1), "white")
    probe_draw = ImageDraw.Draw(probe)
    bbox = probe_draw.textbbox((0, 0), text, font=font)
    image = Image.new("RGB", (bbox[2] - bbox[0] + 100, 120), "white")
    ImageDraw.Draw(image).text((50, 25), text, fill="black", font=font)

    with open(IMAGE_PATH, "rb") as original_file:
        original_image = original_file.read()

    replacement_path = IMAGE_PATH + ".verifier-new.png"
    restore_path = IMAGE_PATH + ".verifier-restore"
    try:
        image.save(replacement_path, format="PNG")
        os.replace(replacement_path, IMAGE_PATH)

        try:
            response = requests.post(
                URL,
                json={"image_path": IMAGE_PATH},
                headers=AUTH_HEADERS,
                timeout=15,
            )
        except requests.exceptions.RequestException as exc:
            pytest.fail(f"Failed to connect to the server at {URL}: {exc}")

        assert response.status_code == 200, (
            f"Expected 200 OK for generated image, got {response.status_code}. "
            f"Response: {response.text}"
        )
        try:
            data = response.json()
        except ValueError:
            pytest.fail(f"Failed to parse JSON response. Response text: {response.text}")

        assert data.get("status") == "success", (
            f"Expected status 'success', got {data.get('status')}"
        )
        assert data.get("decoded_value") == expected, (
            f"Generated image contains {text}; expected decoded_value {expected}, "
            f"got {data.get('decoded_value')}"
        )
    finally:
        if os.path.exists(replacement_path):
            os.unlink(replacement_path)
        with open(restore_path, "wb") as restore_file:
            restore_file.write(original_image)
        os.replace(restore_path, IMAGE_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
