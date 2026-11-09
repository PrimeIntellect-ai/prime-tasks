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
import ast
import io
import os
import subprocess
import tempfile
import uuid

import pytest
import pytesseract
import requests
from PIL import Image, ImageDraw, ImageFont

URL = "http://127.0.0.1:8080/process"
AUTH = {"Authorization": "Bearer diag-token-xyz"}
CUSTOMER_IMAGE = "/app/customer_upload.png"


def ocr_file(path):
    with Image.open(path) as image:
        return pytesseract.image_to_string(image).strip()


def make_image(text):
    font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
    font = ImageFont.truetype(font_path, 38) if os.path.exists(font_path) else ImageFont.load_default()
    probe = Image.new("RGB", (1, 1), "white")
    draw = ImageDraw.Draw(probe)
    box = draw.textbbox((0, 0), text, font=font)
    image = Image.new("RGB", (box[2] - box[0] + 40, box[3] - box[1] + 40), "white")
    ImageDraw.Draw(image).text((20 - box[0], 20 - box[1]), text, fill="black", font=font)
    handle = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
    handle.close()
    image.save(handle.name)
    return handle.name


def post_image(path, headers):
    with open(path, "rb") as image_file:
        response = requests.post(URL, headers=headers, files={"file": image_file}, timeout=15)
    if response.status_code not in (200, 201):
        with open(path, "rb") as image_file:
            response = requests.post(URL, headers=headers, data=image_file.read(), timeout=15)
    return response


def test_mre_script_exists_and_runs():
    """The MRE must use SQLite, reproduce an unsafe execution, and apply a parameterized fix."""
    mre_path = "/home/user/mre.py"
    assert os.path.exists(mre_path), f"Missing required file: {mre_path}"
    assert os.path.isfile(mre_path), f"Path is not a file: {mre_path}"

    expected_text = ocr_file(CUSTOMER_IMAGE)
    assert expected_text, "OCR unexpectedly produced empty text for the customer image"

    try:
        result = subprocess.run(["python3", mre_path], capture_output=True, text=True, timeout=10)
    except subprocess.TimeoutExpired:
        pytest.fail("mre.py execution timed out.")

    assert result.returncode == 0, f"mre.py failed to run. Output: {result.stderr}"
    assert "SUCCESS:" in result.stdout, "mre.py did not print 'SUCCESS: <extracted_text>'"
    assert f"SUCCESS: {expected_text}" in result.stdout.splitlines(), (
        f"mre.py did not print the actual stripped OCR text. Output: {result.stdout!r}"
    )

    with open(mre_path, "r", encoding="utf-8") as source_file:
        source = source_file.read()
    tree = ast.parse(source, filename=mre_path)

    imports_sqlite = any(
        (isinstance(node, ast.Import) and any(alias.name == "sqlite3" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "sqlite3")
        for node in ast.walk(tree)
    )
    assert imports_sqlite, "mre.py must actually exercise SQLite"

    sql_calls = [
        node for node in ast.walk(tree)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr in ("execute", "executemany")
    ]
    assert len(sql_calls) >= 3, "mre.py must create data, reproduce the bad query, and execute the fix"
    assert any(len(call.args) >= 2 or call.keywords for call in sql_calls), (
        "mre.py must prove the SQL fix using bound query parameters"
    )
    assert any(isinstance(node, ast.Try) and node.handlers for node in ast.walk(tree)), (
        "mre.py must catch the reproduced database failure before proving the fix"
    )


def test_service_unauthorized():
    """Check that the service rejects requests without the proper auth header."""
    assert os.path.exists(CUSTOMER_IMAGE), f"Test image missing at {CUSTOMER_IMAGE}"
    with open(CUSTOMER_IMAGE, "rb") as image_file:
        response = requests.post(URL, files={"file": image_file}, timeout=5)
    assert response.status_code in (401, 403), (
        f"Expected 401 or 403 for missing auth, got {response.status_code}"
    )

    with open(CUSTOMER_IMAGE, "rb") as image_file:
        response = requests.post(
            URL,
            headers={"Authorization": "Bearer wrong-token"},
            files={"file": image_file},
            timeout=5,
        )
    assert response.status_code in (401, 403), (
        f"Expected 401 or 403 for incorrect auth, got {response.status_code}"
    )


def assert_authorized_ocr(path):
    expected = ocr_file(path)
    assert expected, f"Verifier OCR unexpectedly produced empty text for {path}"

    try:
        response = post_image(path, AUTH)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the service or process request: {exc}")

    assert response.status_code in (200, 201), (
        f"Expected success status code, got {response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response was not valid JSON. Response text: {response.text}")

    assert "extracted_text" in data, "Response JSON missing 'extracted_text' key"
    assert isinstance(data["extracted_text"], str), "extracted_text must be a string"
    assert data["extracted_text"] == data["extracted_text"].strip(), (
        "Returned OCR text was not whitespace-stripped"
    )
    assert data["extracted_text"] == expected, (
        f"Expected exact OCR output {expected!r}, got {data['extracted_text']!r}"
    )
    return expected


def test_service_authorized_process():
    """Check the supplied customer image and independently generated unpredictable images."""
    server_path = "/home/user/server.py"
    assert os.path.exists(server_path), f"Missing required file: {server_path}"
    assert os.path.isfile(server_path), f"Path is not a file: {server_path}"

    customer_text = assert_authorized_ocr(CUSTOMER_IMAGE)
    assert "O'Reilly" in customer_text, f"Expected O'Reilly in customer OCR, got {customer_text!r}"

    token = uuid.uuid4().hex[:10].upper()
    generated_paths = [
        make_image(f"O'Reilly DYNAMIC {token}"),
        make_image(f"RANDOM OCR {token[::-1]}"),
    ]
    try:
        quoted_text = assert_authorized_ocr(generated_paths[0])
        assert "'" in quoted_text, f"Generated quote test did not OCR an apostrophe: {quoted_text!r}"
        assert_authorized_ocr(generated_paths[1])
    finally:
        for path in generated_paths:
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
