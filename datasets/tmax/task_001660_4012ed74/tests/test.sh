#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import ctypes
import glob
import os
import random
import re
import secrets
import subprocess
import wave

import requests

LIB_PATH = "/app/lib/libfingerprint.so"
URL = "http://127.0.0.1:8080/analyze"


def pcm_checksum(filepath):
    with wave.open(filepath, "rb") as w:
        frames = w.readframes(w.getnframes())
    return sum(frames) % 99991


def post_analyze(filepath, token="ci-token-992", timeout=30):
    return requests.post(URL, json={"token": token, "filepath": filepath}, timeout=timeout)


def assert_success_response(response, filepath):
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        raise AssertionError("Response is not valid JSON")
    assert data.get("status") == "success", "Expected status to be 'success'"
    assert "checksum" in data, "Response missing 'checksum'"
    assert data["checksum"] == pcm_checksum(filepath), (
        f"Expected checksum {pcm_checksum(filepath)}, got {data['checksum']}"
    )
    assert "transcription" in data, "Response missing 'transcription'"
    assert isinstance(data["transcription"], str), "Transcription must be a string"
    return data


def test_required_c_source_and_shared_library():
    source_path = "/app/src/fingerprint.c"
    expected_source = '''#include <stdint.h>
int compute_fingerprint(const uint8_t* pcm_data, int length) {
    int checksum = 0;
    for(int i = 0; i < length; i++) {
        checksum = (checksum + pcm_data[i]) % 99991;
    }
    return checksum;
}
'''
    assert os.path.isfile(source_path), f"C source not found at {source_path}"
    with open(source_path, "r", encoding="utf-8") as f:
        actual_source = f.read().replace("\r\n", "\n")
    assert actual_source == expected_source, "fingerprint.c does not contain the required implementation"

    assert os.path.exists(LIB_PATH), f"Shared library not found at {LIB_PATH}"
    assert os.path.isfile(LIB_PATH), f"{LIB_PATH} is not a file"
    with open(LIB_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{LIB_PATH} is not a valid ELF shared object"

    lib = ctypes.CDLL(LIB_PATH)
    assert hasattr(lib, "compute_fingerprint"), "Shared library does not export compute_fingerprint"
    fn = lib.compute_fingerprint
    fn.argtypes = [ctypes.POINTER(ctypes.c_uint8), ctypes.c_int]
    fn.restype = ctypes.c_int

    for length in [0, 1, 2, 31, 256, 4097] + [random.randint(0, 8192) for _ in range(12)]:
        raw = os.urandom(length)
        array_type = ctypes.c_uint8 * max(1, length)
        buf = array_type(*raw) if length else array_type()
        result = fn(buf, length)
        assert isinstance(result, int)
        assert result == sum(raw) % 99991, f"FFI returned an incorrect result for {length} bytes"
        assert 0 <= result <= 99990


def test_property_based_test_exists_and_runs():
    files = [p for p in glob.glob("/app/tests/test_ffi*") if os.path.isfile(p)]
    assert files, "No property-based test file found starting with /app/tests/test_ffi"

    textual = []
    combined = ""
    for path in files:
        try:
            with open(path, "r", encoding="utf-8") as f:
                content = f.read()
        except (UnicodeDecodeError, OSError):
            continue
        textual.append(path)
        combined += "\n" + content

    assert any(name in combined.lower() for name in (
        "hypothesis", "gopter", "rapidcheck", "quickcheck", "proptest"
    )), "No property-based testing library import found in /app/tests/test_ffi*"
    assert re.search(r"@\s*(?:[A-Za-z_][\w]*\.)?given\s*\(", combined), (
        "The property test must define a generated property using @given"
    )
    assert re.search(r"(?:binary|lists)\s*\(", combined), (
        "The property test must generate byte arrays of varying lengths"
    )

    python_files = [p for p in textual if p.endswith(".py")]
    assert python_files, "No executable Python property-based test file was found"
    result = subprocess.run(
        ["python3", "-m", "pytest", "-q", *python_files],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, f"Property-based test suite failed:\n{result.stdout}"
    assert re.search(r"\b[1-9]\d* passed\b", result.stdout), (
        f"Property-based test suite did not execute any passing tests:\n{result.stdout}"
    )


def test_api_unauthorized():
    try:
        response = post_analyze("/app/audio/alert.wav", token="invalid", timeout=5)
    except requests.RequestException as e:
        raise AssertionError(f"Failed to connect to API: {e}")
    assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}"


def listening_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r", encoding="ascii") as f:
                rows = f.readlines()[1:]
        except OSError:
            continue
        for row in rows:
            fields = row.split()
            local_address = fields[1]
            state = fields[3]
            if state == "0A" and int(local_address.rsplit(":", 1)[1], 16) == port:
                inodes.add(fields[9])

    pids = set()
    for proc in glob.glob("/proc/[0-9]*"):
        pid = proc.rsplit("/", 1)[1]
        for fd in glob.glob(proc + "/fd/*"):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            match = re.fullmatch(r"socket:\[(\d+)\]", target)
            if match and match.group(1) in inodes:
                pids.add(pid)
                break
    return pids


def test_server_process_loaded_ffi_library():
    pids = listening_pids(8080)
    assert pids, "Could not identify a process listening on port 8080"
    mapped = False
    details = []
    for pid in pids:
        try:
            with open(f"/proc/{pid}/maps", "r", encoding="utf-8", errors="ignore") as f:
                maps = f.read()
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                details.append(f"{pid}:" + f.read().replace(b"\0", b" ").decode(errors="ignore"))
        except OSError:
            continue
        if LIB_PATH in maps:
            mapped = True
    assert mapped, "The API listener has not loaded /app/lib/libfingerprint.so via FFI; listeners: " + ", ".join(details)


def test_api_success_and_logic():
    filepath = "/app/audio/alert.wav"
    assert os.path.exists(filepath), f"Audio fixture missing: {filepath}"
    try:
        response = post_analyze(filepath)
    except requests.RequestException as e:
        raise AssertionError(f"Failed to connect to API: {e}")
    data = assert_success_response(response, filepath)

    transcription_clean = re.sub(r"[^\w\s]", "", data["transcription"].lower())
    expected_words = ["build", "pipeline", "failed", "at", "network", "module"]
    for word in expected_words:
        assert word in transcription_clean, f"Expected word '{word}' not found in transcription: {data['transcription']}"


def test_api_handles_unseen_audio_and_concurrent_requests():
    choices = [
        ("storage", "Build pipeline failed at storage module"),
        ("database", "Build pipeline failed at database module"),
        ("security", "Build pipeline failed at security module"),
    ]
    marker, phrase = secrets.choice(choices)
    generated = f"/app/audio/verifier_{secrets.token_hex(10)}.wav"
    subprocess.run(["espeak-ng", "-w", generated, phrase], check=True, timeout=30)
    assert os.path.isfile(generated)
    assert pcm_checksum(generated) != pcm_checksum("/app/audio/alert.wav"), (
        "Generated verifier audio unexpectedly has the fixture checksum"
    )

    paths = [generated, "/app/audio/alert.wav", generated, "/app/audio/alert.wav"]
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
            futures = [executor.submit(post_analyze, path) for path in paths]
            responses = [future.result(timeout=40) for future in futures]

        generated_transcriptions = []
        for path, response in zip(paths, responses):
            data = assert_success_response(response, path)
            if path == generated:
                generated_transcriptions.append(re.sub(r"[^\w\s]", "", data["transcription"].lower()))

        assert generated_transcriptions, "No generated-audio response was checked"
        for text in generated_transcriptions:
            assert marker in text, (
                f"Generated speech marker '{marker}' was not transcribed; got: {text!r}"
            )
    finally:
        try:
            os.remove(generated)
        except OSError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
