#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import glob
import os
import secrets
import subprocess

import requests

URL = "http://127.0.0.1:9090/process"


def fnv1a(data):
    value = 0x811C9DC5
    for byte in data:
        value ^= byte
        value = (value * 0x01000193) & 0xFFFFFFFF
    return value


def extracted_token():
    result = subprocess.run(
        ["tesseract", "/app/reference_code.png", "stdout"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    return result.stdout.strip()


def post(token, value):
    return requests.post(
        URL,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        json={"data": value},
        timeout=5,
    )


def test_shared_library_exists():
    assert os.path.exists('/app/libecc.so'), "/app/libecc.so does not exist. Did you compile the C library?"


def test_shared_library_is_loadable_and_correct():
    assert os.path.isfile('/app/libecc.so'), "/app/libecc.so is not a regular file"
    with open('/app/libecc.so', 'rb') as handle:
        assert handle.read(4) == b'\x7fELF', "/app/libecc.so is not an ELF shared library"

    try:
        library = ctypes.CDLL('/app/libecc.so')
        compute_ecc = library.compute_ecc
    except (OSError, AttributeError) as exc:
        assert False, f"Could not load compute_ecc from /app/libecc.so: {exc}"

    compute_ecc.argtypes = [ctypes.c_char_p, ctypes.c_int]
    compute_ecc.restype = ctypes.c_uint32
    samples = [b'', b'hello world', os.urandom(31), os.urandom(257)]
    for sample in samples:
        actual = compute_ecc(sample, len(sample))
        assert actual == fnv1a(sample), (
            f"compute_ecc returned {actual} for a generated input; expected {fnv1a(sample)}"
        )


def test_api_unauthorized():
    headers = {
        "Authorization": "Bearer WRONGTOKEN",
        "Content-Type": "application/json"
    }
    payload = {"data": "test"}

    try:
        response = requests.post(URL, headers=headers, json=payload, timeout=5)
    except requests.RequestException as e:
        assert False, f"Failed to connect to the API at {URL}: {e}"

    assert response.status_code == 401, f"Expected HTTP 401 Unauthorized for wrong token, got {response.status_code}"


def test_api_rejects_generated_wrong_token():
    token = extracted_token()
    wrong_token = token + "-" + secrets.token_hex(12)
    response = post(wrong_token, secrets.token_hex(20))
    assert response.status_code == 401, (
        f"Expected HTTP 401 Unauthorized for a generated wrong token, got {response.status_code}"
    )


def test_api_authorized_and_processing():
    headers = {
        "Authorization": "Bearer AUTH-77X9Q2",
        "Content-Type": "application/json"
    }
    payload = {"data": "hello world"}

    try:
        response = requests.post(URL, headers=headers, json=payload, timeout=5)
    except requests.RequestException as e:
        assert False, f"Failed to connect to the API at {URL}: {e}"

    assert response.status_code == 200, f"Expected HTTP 200 OK for correct token, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        assert False, f"Expected JSON response, got: {response.text}"

    assert data.get("status") == "ok", f"Expected status 'ok', got {data.get('status')}"
    assert data.get("checksum") == 3501256372, f"Expected checksum 3501256372 for 'hello world', got {data.get('checksum')}"


def test_api_processes_generated_inputs():
    token = extracted_token()
    assert token == "AUTH-77X9Q2", f"Unexpected OCR result from reference image: {token!r}"

    samples = [
        secrets.token_hex(17),
        secrets.token_urlsafe(39),
        "prefix-" + secrets.token_hex(80) + "-suffix",
        "spaces " + secrets.token_hex(12) + " and " + secrets.token_hex(13),
    ]
    for value in samples:
        response = post(token, value)
        assert response.status_code == 200, (
            f"Expected HTTP 200 for generated authorized input, got {response.status_code}: {response.text}"
        )
        try:
            body = response.json()
        except ValueError:
            assert False, f"Expected JSON response, got: {response.text}"
        expected = fnv1a(value.encode('utf-8'))
        assert body.get("status") == "ok", f"Expected status 'ok', got {body.get('status')}"
        assert body.get("checksum") == expected, (
            f"Expected checksum {expected} for generated input, got {body.get('checksum')}"
        )


def test_listening_service_loaded_shared_library():
    listener_inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as handle:
                next(handle, None)
                for line in handle:
                    fields = line.split()
                    if len(fields) > 9:
                        port = int(fields[1].rsplit(':', 1)[1], 16)
                        if port == 9090 and fields[3] == '0A':
                            listener_inodes.add(fields[9])
        except OSError:
            pass

    assert listener_inodes, "No process is listening on TCP port 9090"
    matching_pids = []
    loaded_by_listener = False
    for proc_dir in glob.glob('/proc/[0-9]*'):
        pid = os.path.basename(proc_dir)
        owns_listener = False
        for fd in glob.glob(f'{proc_dir}/fd/*'):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in listener_inodes:
                owns_listener = True
                break
        if not owns_listener:
            continue
        matching_pids.append(pid)
        try:
            with open(f'{proc_dir}/maps') as maps:
                if any('/app/libecc.so' in line for line in maps):
                    loaded_by_listener = True
                    break
        except OSError:
            pass

    assert matching_pids, "Could not identify the process listening on port 9090"
    assert loaded_by_listener, (
        "The service process listening on port 9090 has not loaded /app/libecc.so"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
