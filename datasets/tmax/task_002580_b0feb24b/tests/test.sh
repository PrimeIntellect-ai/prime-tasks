#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
import urllib.request
import urllib.error
import pytest

DETECTOR = "/home/user/detector"
SOURCE = "/home/user/detector.c"


def run_detector(executable, filepath, timeout=3):
    try:
        return subprocess.run(
            [executable, filepath], capture_output=True, timeout=timeout
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Detector {executable} hung while processing {filepath}")


@pytest.fixture(scope="session")
def rebuilt_detector():
    assert os.path.isfile(SOURCE), f"Detector C source not found at {SOURCE}"
    build_dir = tempfile.mkdtemp(prefix="detector-build-")
    output = os.path.join(build_dir, "detector-from-source")
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", SOURCE, "-o", output],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, (
        "detector.c did not compile as C source:\n"
        + result.stdout
        + result.stderr
    )
    assert os.path.isfile(output) and os.access(output, os.X_OK)
    return output


def test_end_to_end_proxy():
    """
    Test that the Nginx proxy is correctly configured and routes to the C backend.
    A clean HTTP POST request to http://127.0.0.1:8080/process should successfully
    return a 200 OK and "PROCESSED".
    """
    url = "http://127.0.0.1:8080/process"
    data = b"clean data"
    req = urllib.request.Request(url, data=data, method="POST")

    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            status = response.status
            body = response.read().decode("utf-8", errors="ignore")
    except urllib.error.HTTPError as e:
        pytest.fail(f"End-to-end request failed with HTTP Error {e.code}: {e.reason}")
    except urllib.error.URLError as e:
        pytest.fail(f"End-to-end request failed to connect: {e.reason}")
    except Exception as e:
        pytest.fail(f"End-to-end request encountered an unexpected error: {e}")

    assert status == 200, f"Expected HTTP status 200, got {status}"
    assert "PROCESSED" in body, f"Expected 'PROCESSED' in response body, got: {body}"


def test_detector_exists_and_executable():
    """Ensure the detector binary was compiled and is executable."""
    assert os.path.isfile(DETECTOR), f"Detector binary not found at {DETECTOR}"
    assert os.access(DETECTOR, os.X_OK), f"Detector at {DETECTOR} is not executable"


def test_detector_evil_corpus():
    """Ensure the detector rejects 100% of the evil corpus with exit code 1."""
    evil_dir = "/app/corpus/evil"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"

    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    assert len(evil_files) > 0, "No files found in evil corpus directory."

    failed_files = []
    for filename in evil_files:
        filepath = os.path.join(evil_dir, filename)
        if run_detector(DETECTOR, filepath) != 1:
            failed_files.append(filename)

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(evil_files)} evil bypassed. "
            f"Offending files: {', '.join(failed_files)}"
        )


def test_detector_clean_corpus():
    """Ensure the detector accepts 100% of the clean corpus with exit code 0."""
    clean_dir = "/app/corpus/clean"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"

    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    assert len(clean_files) > 0, "No files found in clean corpus directory."

    failed_files = []
    for filename in clean_files:
        filepath = os.path.join(clean_dir, filename)
        if run_detector(DETECTOR, filepath) != 0:
            failed_files.append(filename)

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(clean_files)} clean modified/rejected. "
            f"Offending files: {', '.join(failed_files)}"
        )


def test_detector_source_is_c_and_builds(rebuilt_detector):
    assert os.path.isfile(SOURCE), f"Detector C source not found at {SOURCE}"
    with open(DETECTOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Installed detector is not a compiled ELF executable"
    with open(rebuilt_detector, "rb") as f:
        assert f.read(4) == b"\x7fELF"


def parser_would_hang(raw_request):
    """Derive the result from the supplied parser's body and token semantics."""
    separator = raw_request.find(b"\r\n\r\n")
    if separator < 0:
        return False
    body = raw_request[separator + 4:].split(b"\x00", 1)[0]
    tokens = [t for t in re.split(br"[ \t\r\n]+", body) if t]
    return b"RECURSE_HALT" in tokens


def make_novel_cases():
    cases = []
    marker = b"RECURSE_HALT"
    whitespace = [b" ", b"\t", b"\r\n", b"  \t "]

    # Runtime-randomized requests containing a real body token.
    for _ in range(24):
        left = ("left_" + secrets.token_hex(6)).encode()
        right = ("right_" + secrets.token_hex(6)).encode()
        body = left + secrets.choice(whitespace) + marker
        if secrets.randbelow(2):
            body += secrets.choice(whitespace) + right
        header = ("X-Nonce: " + secrets.token_hex(10)).encode()
        raw = b"POST /process HTTP/1.1\r\nHost: localhost\r\n" + header + b"\r\n\r\n" + body
        cases.append(raw)

    # Runtime-randomized clean requests and decoys where the marker is not a
    # whitespace-delimited body token.
    for i in range(24):
        nonce = secrets.token_hex(8).encode()
        kind = i % 6
        if kind == 0:
            body = b"ordinary_" + nonce + b" data"
            raw = b"POST /process HTTP/1.1\r\nHost: localhost\r\n\r\n" + body
        elif kind == 1:
            body = b"ordinary " + marker + b"_suffix " + nonce
            raw = b"POST /process HTTP/1.1\r\nHost: localhost\r\n\r\n" + body
        elif kind == 2:
            body = b"ordinary prefix_" + marker + b" " + nonce
            raw = b"POST /process HTTP/1.1\r\nHost: localhost\r\n\r\n" + body
        elif kind == 3:
            body = b"ordinary recurse_halt " + nonce
            raw = b"POST /process HTTP/1.1\r\nHost: localhost\r\n\r\n" + body
        elif kind == 4:
            raw = (
                b"POST /process HTTP/1.1\r\nX-Decoy: " + marker
                + b"\r\nHost: localhost\r\n\r\nordinary " + nonce
            )
        else:
            # No CRLF/CRLF separator, so the backend does not parse a body.
            raw = b"POST /process HTTP/1.1\nHost: localhost\n\nordinary " + marker + b" " + nonce
        cases.append(raw)

    return cases


def test_detector_on_novel_content_at_same_neutral_path(rebuilt_detector):
    cases = make_novel_cases()
    expected = [1 if parser_would_hang(raw) else 0 for raw in cases]
    assert 0 in expected and 1 in expected

    # Every request is written to the same randomly named neutral path. Thus
    # classifications must depend on file contents rather than corpus/path names.
    workdir = tempfile.mkdtemp(prefix="request-check-")
    request_path = os.path.join(workdir, "sample-" + secrets.token_hex(8) + ".dat")

    order = list(range(len(cases)))
    secrets.SystemRandom().shuffle(order)
    for executable in (DETECTOR, rebuilt_detector):
        for index in order:
            with open(request_path, "wb") as f:
                f.write(cases[index])
            actual = run_detector(executable, request_path)
            assert actual == expected[index], (
                f"{executable} returned {actual}, expected {expected[index]} "
                f"for novel request {index}"
            )


def test_detector_requires_exactly_one_argument(rebuilt_detector):
    for executable in (DETECTOR, rebuilt_detector):
        no_arg = subprocess.run([executable], capture_output=True, timeout=3)
        extra_args = subprocess.run(
            [executable, "/tmp/one", "/tmp/two"], capture_output=True, timeout=3
        )
        assert no_arg.returncode != 0, f"{executable} accepted no input argument"
        assert extra_args.returncode != 0, f"{executable} accepted multiple input arguments"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
