#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
import tempfile
import time

DELIMITER = b"\r\n---REQUEST-BOUNDARY---\r\n"
PROJECT = "/home/user/http_analytics"
BIN_PATH = PROJECT + "/target/release/http_analytics"
INPUT_FILE = "/app/data/requests.log"
OUTPUT_FILE = "/home/user/top_urls.txt"
LIB_PATH = "/app/vendored/http-parser-2.9.4/libhttp_parser.a"
VENDOR_DIR = "/app/vendored/http-parser-2.9.4"
PATCH_PATH = "/home/user/http-parser-makefile.patch"


def expected_from_dataset(path):
    with open(path, "rb") as f:
        data = f.read()

    rows = []
    for request in data.split(DELIMITER):
        line = request.split(b"\r\n", 1)[0]
        parts = line.split(b" ")
        if len(parts) != 3 or not parts[2].startswith(b"HTTP/"):
            continue
        try:
            url = parts[1].decode("utf-8")
        except UnicodeDecodeError:
            continue

        query = url.partition("?")[2]
        score = None
        for parameter in query.split("&"):
            key, separator, value = parameter.partition("=")
            if separator and key == "score":
                try:
                    score = int(value)
                except ValueError:
                    score = None
                break
        if score is not None:
            rows.append((score, url))

    rows.sort(key=lambda item: (-item[0], item[1]))
    return b"".join(url.encode("utf-8") + b"\n" for _, url in rows)


def run_binary(input_path, output_path):
    return subprocess.run(
        [BIN_PATH, input_path, output_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )


def test_patch_file_exists():
    assert os.path.isfile(PATCH_PATH), f"Patch file {PATCH_PATH} is missing. Step 1 requires saving the diff here."
    with open(PATCH_PATH, "r", errors="replace") as f:
        patch = f.read()
    assert re.search(r"^--- .+$", patch, re.MULTILINE), "Patch is not a unified diff: missing --- header."
    assert re.search(r"^\+\+\+ .+$", patch, re.MULTILINE), "Patch is not a unified diff: missing +++ header."
    assert re.search(r"^@@ ", patch, re.MULTILINE), "Patch is not a unified diff: missing hunk header."


def test_c_library_compiled():
    assert os.path.isfile(LIB_PATH), f"C library {LIB_PATH} was not compiled. Make sure 'make library' succeeded."
    subprocess.run(["make", "clean"], cwd=VENDOR_DIR, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    result = subprocess.run(
        ["make", "library"], cwd=VENDOR_DIR, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
    )
    assert result.returncode == 0, f"make library failed:\n{result.stdout.decode(errors='replace')}\n{result.stderr.decode(errors='replace')}"
    assert os.path.isfile(LIB_PATH), "make library did not produce libhttp_parser.a."
    members = subprocess.run(["ar", "t", LIB_PATH], check=True, stdout=subprocess.PIPE, text=True).stdout
    assert "http_parser.o" in members, "libhttp_parser.a does not contain the http-parser object file."


def test_rust_binary_exists():
    assert os.path.isfile(BIN_PATH), f"Rust binary {BIN_PATH} not found. Did you compile the project in release mode?"
    assert os.access(BIN_PATH, os.X_OK), f"Rust binary {BIN_PATH} is not executable."


def test_rust_project_links_and_calls_http_parser():
    build_rs = os.path.join(PROJECT, "build.rs")
    assert os.path.isfile(build_rs), "The Rust project is missing build.rs."
    with open(build_rs, "r", errors="replace") as f:
        build_text = f.read()
    assert "rustc-link-lib" in build_text and "http_parser" in build_text, "build.rs does not link http_parser."
    assert "static" in build_text, "build.rs does not request static linking of http_parser."

    rust_source = ""
    for root, _, files in os.walk(os.path.join(PROJECT, "src")):
        for name in files:
            if name.endswith(".rs"):
                with open(os.path.join(root, name), "r", errors="replace") as f:
                    rust_source += f.read() + "\n"
    assert "http_parser_init" in rust_source, "Rust source does not interface with http_parser_init."
    assert "http_parser_execute" in rust_source, "Rust source does not interface with http_parser_execute."
    assert "http_parser_settings" in rust_source, "Rust source does not define or use http_parser_settings."

    symbols = subprocess.run(["nm", BIN_PATH], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True).stdout
    assert re.search(r"\bhttp_parser_init$", symbols, re.MULTILINE), "Release binary is not linked with http_parser_init."
    assert re.search(r"\bhttp_parser_execute$", symbols, re.MULTILINE), "Release binary is not linked with http_parser_execute."

    disassembly = subprocess.run(["objdump", "-d", BIN_PATH], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True).stdout
    assert re.search(r"\bcall\w*\s+.*<http_parser_init>", disassembly), "Release binary contains no call to http_parser_init."
    assert re.search(r"\bcall\w*\s+.*<http_parser_execute>", disassembly), "Release binary contains no call to http_parser_execute."


def test_execution_correctness_and_performance():
    assert os.path.isfile(BIN_PATH), f"Binary {BIN_PATH} is missing."
    assert os.path.isfile(INPUT_FILE), f"Input file {INPUT_FILE} is missing."

    expected = expected_from_dataset(INPUT_FILE)
    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)

    start = time.perf_counter()
    result = run_binary(INPUT_FILE, OUTPUT_FILE)
    elapsed = time.perf_counter() - start

    assert result.returncode == 0, f"Execution failed with return code {result.returncode}.\nStderr: {result.stderr.decode(errors='replace')}"
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} was not created by the application."
    with open(OUTPUT_FILE, "rb") as f:
        actual = f.read()
    assert actual == expected, "Output contents are incorrect for the supplied request dataset."
    assert elapsed < 1.5, f"Execution time exceeded threshold. Elapsed: {elapsed:.3f}s, Threshold: < 1.5s"


def test_execution_on_unseen_requests():
    seed = int.from_bytes(os.urandom(8), "little")
    rng = random.Random(seed)
    requests = []
    expected_rows = []

    for i in range(250):
        score = rng.randint(-5000, 20000)
        url = f"/verify/{rng.randint(1, 99999)}?nonce={rng.getrandbits(64):016x}&score={score}"
        requests.append(f"GET {url} HTTP/1.1\r\nHost: verifier\r\nX-Test: {i}\r\n\r\n".encode())
        expected_rows.append((score, url))

        if i % 11 == 0:
            no_score = f"/verify/no-score/{rng.randint(1, 99999)}?nonce={rng.getrandbits(64):016x}"
            requests.append(f"GET {no_score} HTTP/1.1\r\nHost: verifier\r\n\r\n".encode())

    requests.extend([b"\x00not-an-http-request", b"BROKEN\r\n\r\n"])
    rng.shuffle(requests)
    expected_rows.sort(key=lambda item: (-item[0], item[1]))
    expected = b"".join(url.encode() + b"\n" for _, url in expected_rows)

    with tempfile.TemporaryDirectory() as directory:
        input_path = os.path.join(directory, "requests.log")
        output_path = os.path.join(directory, "result.txt")
        with open(input_path, "wb") as f:
            f.write(DELIMITER.join(requests))
        result = run_binary(input_path, output_path)
        assert result.returncode == 0, f"Execution on unseen input failed. Stderr: {result.stderr.decode(errors='replace')}"
        assert os.path.isfile(output_path), "Application did not create output for unseen input."
        with open(output_path, "rb") as f:
            actual = f.read()
        assert actual == expected, f"Incorrect output on unseen verifier-generated requests (seed {seed})."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
