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
import re
import secrets
import subprocess
import time

import pytest
import requests

C_DIR = "/app/c_src"
RUST_DIR = "/app/rust_src"
LIB_PATH = "/app/c_src/libocr.so"
BIN_PATH = "/app/rust_src/target/debug/rust_ocr"
IMAGE_PATH = "/app/test_receipt.png"


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, **kwargs)


def rust_env():
    env = os.environ.copy()
    old = env.get("LD_LIBRARY_PATH", "")
    env["LD_LIBRARY_PATH"] = C_DIR + ((":" + old) if old else "")
    return env


def rust_output(image_path=IMAGE_PATH):
    return run([BIN_PATH, image_path], env=rust_env()).stdout


def get_with_retry(url):
    last_exception = None
    for _ in range(5):
        try:
            return requests.get(url, timeout=5)
        except requests.exceptions.RequestException as exc:
            last_exception = exc
            time.sleep(1)
    pytest.fail(f"Failed to connect to {url} after 5 attempts. Last error: {last_exception}")


def test_00_sources_really_build_and_artifacts_are_real():
    # Force both repaired source trees to be processed rather than trusting
    # pre-existing files with the expected names.
    os.utime(os.path.join(C_DIR, "libocr.c"), None)
    run(["make", "-B"], cwd=C_DIR)

    os.utime(os.path.join(RUST_DIR, "src/main.rs"), None)
    run(["cargo", "build"], cwd=RUST_DIR,
        env={**rust_env(), "LIBRARY_PATH": C_DIR})

    c_header = run(["readelf", "-h", LIB_PATH]).stdout.decode("utf-8", "replace")
    assert "DYN (Shared object file)" in c_header, "libocr.so is not an ELF shared library"
    c_symbols = run(["readelf", "-Ws", LIB_PATH]).stdout.decode("utf-8", "replace")
    assert re.search(r"\bextract_text\b", c_symbols), "libocr.so does not export extract_text"

    rust_header = run(["readelf", "-h", BIN_PATH]).stdout.decode("utf-8", "replace")
    assert "ELF" in rust_header, "The Rust artifact is not an ELF executable"
    rust_symbols = run(["readelf", "-Ws", BIN_PATH]).stdout.decode("utf-8", "replace")
    assert re.search(r"UND\s+extract_text\b", rust_symbols), \
        "The Rust executable is not linked through the extract_text FFI symbol"
    dependencies = run(["ldd", BIN_PATH], env=rust_env()).stdout.decode("utf-8", "replace")
    assert "libocr.so" in dependencies and "libocr.so => not found" not in dependencies, \
        "The Rust executable is not dynamically linked to the built libocr.so"


def test_compiled_c_library():
    assert os.path.isfile("/app/c_src/libocr.so"), "The C library /app/c_src/libocr.so was not compiled successfully."


def test_compiled_rust_binary():
    assert os.path.isfile("/app/rust_src/target/debug/rust_ocr"), "The Rust binary /app/rust_src/target/debug/rust_ocr was not compiled successfully."


def test_bash_server_script():
    assert os.path.isfile("/app/server.sh"), "The Bash server script /app/server.sh is missing."
    assert os.access("/app/server.sh", os.X_OK) or "bash" in open("/app/server.sh").read() or True, "Ensure server.sh exists."


def test_nginx_config_exists():
    assert os.path.isfile("/app/nginx.conf"), "The Nginx configuration file /app/nginx.conf is missing."
    run(["nginx", "-t", "-c", "/app/nginx.conf"])
    process_list = run(["ps", "-ef"]).stdout.decode("utf-8", "replace")
    assert re.search(r"nginx: master process.*(?:-c\s+)?/app/nginx\.conf", process_list), \
        "Nginx is not running with /app/nginx.conf"


def test_http_endpoint():
    url = "http://127.0.0.1:8080/"
    response = get_with_retry(url)
    assert response.status_code == 200, \
        f"HTTP GET {url} returned status code {response.status_code}, expected 200."
    body = response.text
    assert "ORDER_ID: 88921" in body, \
        f"HTTP GET {url} returned 200 OK, but the expected text 'ORDER_ID: 88921' was not found in the body. Actual body: {body}"
    expected = rust_output()
    assert response.content == expected, \
        "The HTTP body is not the exact stdout of the Rust OCR tool"


def test_dynamic_c_rust_and_http_pipeline():
    # Use values created only after the agent has finished, preventing a fixed
    # ORDER_ID response from satisfying the behavioral checks.
    lib = ctypes.CDLL(LIB_PATH)
    lib.extract_text.argtypes = [ctypes.c_char_p]
    lib.extract_text.restype = ctypes.c_void_p

    for _ in range(2):
        token = str(secrets.randbelow(900000) + 100000)
        run([
            "convert", "-size", "700x180", "xc:white", "-fill", "black",
            "-font", "DejaVu-Sans", "-pointsize", "72",
            "-gravity", "center", "-draw", f"text 0,0 '{token}'", IMAGE_PATH,
        ])

        expected_c = run(["tesseract", IMAGE_PATH, "stdout"]).stdout
        assert token.encode() in expected_c, \
            f"Generated OCR fixture was not recognized as {token}: {expected_c!r}"

        ptr = lib.extract_text(IMAGE_PATH.encode())
        assert ptr, "extract_text returned NULL"
        actual_c = ctypes.string_at(ptr)
        assert actual_c == expected_c, \
            f"The C library output differs from tesseract: {actual_c!r} != {expected_c!r}"

        actual_rust = rust_output()
        assert actual_rust.strip() == expected_c.strip(), \
            f"The Rust FFI wrapper produced incorrect OCR output: {actual_rust!r}"

        suffix = secrets.token_hex(8)
        backend = get_with_retry(f"http://127.0.0.1:8081/{suffix}")
        assert backend.status_code == 200
        assert backend.content == actual_rust, \
            "The Bash server body is not the exact Rust tool stdout"

        proxied = get_with_retry(f"http://127.0.0.1:8080/{suffix}?v={suffix}")
        assert proxied.status_code == 200
        assert proxied.content == actual_rust, \
            "The Nginx endpoint did not proxy the exact Bash server response"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
