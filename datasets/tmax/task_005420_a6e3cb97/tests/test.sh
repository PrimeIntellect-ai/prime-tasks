#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import random
import re
import secrets
import subprocess
import pytest

BIN_PATH = "/home/user/traffic_inspector"
SRC_PATH = "/home/user/traffic_inspector.c"
LIB_PATH = "/app/picohttpparser/libpicohttpparser.so"
PARSER_DIR = "/app/picohttpparser"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"


def test_shared_library_compiled():
    assert os.path.isfile(LIB_PATH), f"Shared library not found at {LIB_PATH}. Did you compile picohttpparser?"


def test_makefile_builds_shared_library():
    result = subprocess.run(
        ["make", "-B", "-C", PARSER_DIR],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        "The repaired picohttpparser Makefile could not build the library:\n"
        + result.stdout.decode(errors="replace")
        + result.stderr.decode(errors="replace")
    )
    assert os.path.isfile(LIB_PATH), "Make did not produce libpicohttpparser.so"


def test_inspector_binary_compiled():
    assert os.path.isfile(BIN_PATH), f"Traffic inspector binary not found at {BIN_PATH}."
    assert os.access(BIN_PATH, os.X_OK), f"Traffic inspector binary at {BIN_PATH} is not executable."


def test_c_source_and_elf_linkage():
    assert os.path.isfile(SRC_PATH), f"C source not found at {SRC_PATH}."
    assert os.path.getsize(SRC_PATH) > 0, f"C source at {SRC_PATH} is empty."

    with open(LIB_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libpicohttpparser.so is not a compiled ELF shared library"
    with open(BIN_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "traffic_inspector is not a compiled ELF binary"

    lib_header = subprocess.run(
        ["/usr/bin/readelf", "-h", LIB_PATH], capture_output=True, text=True, check=True
    ).stdout
    assert re.search(r"Type:\s+DYN", lib_header), "libpicohttpparser.so is not an ELF shared object"

    lib_symbols = subprocess.run(
        ["/usr/bin/readelf", "-Ws", LIB_PATH], capture_output=True, text=True, check=True
    ).stdout
    assert "phr_parse_request" in lib_symbols, "Shared library does not export phr_parse_request"

    dynamic = subprocess.run(
        ["/usr/bin/readelf", "-d", BIN_PATH], capture_output=True, text=True, check=True
    ).stdout
    assert re.search(r"Shared library: \[libpicohttpparser\.so\]", dynamic), (
        "traffic_inspector is not dynamically linked against libpicohttpparser.so"
    )

    bin_symbols = subprocess.run(
        ["/usr/bin/readelf", "-Ws", BIN_PATH], capture_output=True, text=True, check=True
    ).stdout
    assert any(" UND " in line and "phr_parse_request" in line for line in bin_symbols.splitlines()), (
        "traffic_inspector does not reference picohttpparser's phr_parse_request"
    )


def run_inspector(input_data: bytes) -> subprocess.CompletedProcess:
    env = os.environ.copy()
    if "LD_LIBRARY_PATH" in env:
        env["LD_LIBRARY_PATH"] = f"/app/picohttpparser:{env['LD_LIBRARY_PATH']}"
    else:
        env["LD_LIBRARY_PATH"] = "/app/picohttpparser"

    return subprocess.run(
        [BIN_PATH],
        input=input_data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        timeout=5,
    )


def parse_reconstructed(data: bytes):
    assert b"\x00" not in data, "output contains a NUL byte"
    normalized = data.replace(b"\r\n", b"\n")
    assert b"\r" not in normalized, "output contains malformed line endings"
    assert b"\n\n" in normalized, "output is not a complete HTTP request"
    head, body = normalized.split(b"\n\n", 1)
    lines = head.decode("ascii", errors="strict").split("\n")
    assert lines and lines[0], "output has no request line"
    headers = []
    for line in lines[1:]:
        assert ":" in line, f"malformed reconstructed header: {line!r}"
        name, value = line.split(":", 1)
        assert name, "empty reconstructed header name"
        headers.append((name.lower(), value.lstrip(" \t")))
    return lines[0], headers, body


def assert_reconstructed(input_data: bytes, output_data: bytes):
    in_line, in_headers, in_body = parse_reconstructed(input_data)
    out_line, out_headers, out_body = parse_reconstructed(output_data)
    assert out_line == in_line, "request line was not reconstructed correctly"
    assert out_body == in_body, "request body was not reconstructed correctly"

    expected = []
    secrets_in_auth = []
    for name, value in in_headers:
        if name == "authorization":
            secrets_in_auth.append(value)
            expected.append((name, "REDACTED"))
        else:
            expected.append((name, value))

    assert collections.Counter(out_headers) == collections.Counter(expected), (
        "reconstructed headers differ from the input headers other than redaction"
    )
    for secret in secrets_in_auth:
        if secret:
            assert secret.encode() not in output_data, "Authorization credential leaked in output"


def test_evil_corpus():
    if not os.path.isdir(EVIL_CORPUS_DIR):
        pytest.fail(f"Evil corpus directory missing at {EVIL_CORPUS_DIR}")

    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, "No files found in evil corpus directory."

    bypassed = []
    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, filename)
        with open(filepath, "rb") as f:
            input_data = f.read()
        result = run_inspector(input_data)
        if result.returncode != 1 or result.stdout != b"":
            bypassed.append(filename)

    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil requests bypassed the inspector: {', '.join(bypassed)}")


def test_clean_corpus():
    if not os.path.isdir(CLEAN_CORPUS_DIR):
        pytest.fail(f"Clean corpus directory missing at {CLEAN_CORPUS_DIR}")

    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, "No files found in clean corpus directory."

    modified_or_failed = []
    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, filename)
        with open(filepath, "rb") as f:
            input_data = f.read()
        result = run_inspector(input_data)

        if result.returncode != 0:
            modified_or_failed.append(f"{filename} (exit code {result.returncode})")
            continue

        stdout_str = result.stdout.decode('utf-8', errors='ignore')
        input_str = input_data.decode('utf-8', errors='ignore')
        if "Authorization:" in input_str:
            if "Authorization: REDACTED" not in stdout_str:
                modified_or_failed.append(f"{filename} (Authorization header not REDACTED)")
                continue
        try:
            assert_reconstructed(input_data, result.stdout)
        except (AssertionError, UnicodeError) as exc:
            modified_or_failed.append(f"{filename} ({exc})")

    if modified_or_failed:
        pytest.fail(f"{len(modified_or_failed)} of {len(clean_files)} clean requests were incorrectly handled: {', '.join(modified_or_failed)}")


def case_variant(value, rng):
    return "".join(ch.upper() if ch.isalpha() and rng.randrange(2) else ch.lower() if ch.isalpha() else ch for ch in value)


def make_request(method, uri, cert_value="SUCCESS", include_cert=True, authorization=None, newline="\r\n", cert_name="X-SSL-Cert-Valid"):
    headers = [
        ("Host", f"edge-{secrets.token_hex(5)}.example"),
        ("X-Request-ID", secrets.token_hex(16)),
    ]
    if include_cert:
        headers.append((cert_name, cert_value))
    if authorization is not None:
        headers.append(("Authorization", authorization))
    if method in ("POST", "PUT", "PATCH"):
        headers.append(("Content-Length", "0"))
    text = f"{method} {uri} HTTP/1.1{newline}"
    text += "".join(f"{name}: {value}{newline}" for name, value in headers)
    text += newline
    return text.encode("ascii")


def test_generated_requests_and_full_reconstruction():
    rng = random.SystemRandom()
    methods = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]

    # Independently generated clean requests prevent fixture-specific output.
    for i in range(180):
        method = rng.choice(methods)
        marker = secrets.token_hex(12)
        uri = f"/service/{marker}/item?mode=safe&n={rng.randrange(1000000)}"
        auth = None
        if i % 3 != 0:
            auth = f"Bearer {secrets.token_urlsafe(24)}"
        newline = "\r\n" if i % 2 else "\n"
        cert_name = case_variant("X-SSL-Cert-Valid", rng)
        request = make_request(method, uri, authorization=auth, newline=newline, cert_name=cert_name)
        result = run_inspector(request)
        assert result.returncode == 0, f"generated clean request exited with {result.returncode}: {result.stderr!r}"
        assert_reconstructed(request, result.stdout)

    # Exercise every URI signature with fresh locations, casing, and credentials.
    signatures = ["<script", "%3Cscript", "UNION SELECT", "%27%20OR"]
    for i in range(80):
        token = case_variant(signatures[i % len(signatures)], rng)
        uri = f"/lookup/{secrets.token_hex(8)}?q=before{token}after{secrets.token_hex(3)}"
        request = make_request(
            rng.choice(methods), uri, authorization=f"Basic {secrets.token_urlsafe(18)}",
            newline="\r\n" if i % 2 else "\n",
        )
        result = run_inspector(request)
        assert result.returncode == 1, f"generated malicious URI was accepted: {token!r}"
        assert result.stdout == b"", "malicious URI produced output"

    # Missing and non-SUCCESS certificate values must fail independently of URI.
    bad_values = ["FAILED", "success", "SUCCESSFUL", "0", "", "REVOKED"]
    for i in range(60):
        uri = f"/clean/{secrets.token_hex(12)}?v={rng.randrange(1000000)}"
        if i % 2 == 0:
            request = make_request(rng.choice(methods), uri, include_cert=False)
        else:
            request = make_request(rng.choice(methods), uri, cert_value=rng.choice(bad_values))
        result = run_inspector(request)
        assert result.returncode == 1, "request with missing or invalid TLS certificate header was accepted"
        assert result.stdout == b"", "request with missing or invalid TLS certificate header produced output"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
