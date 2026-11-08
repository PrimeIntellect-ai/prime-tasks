#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import secrets
import string
import time

import pytest
import requests

SO_PATH = "/app/libencoder.so"
URL = "http://127.0.0.1:8080/api/v1/mock/encode"
AUTH = {"Authorization": "Bearer mobile-ci-token-2024"}
SEED = "X9F-44A-B21"


def request(params, headers=None):
    try:
        return requests.get(URL, params=params, headers=headers, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the mock server: {exc}")


def load_encoder():
    with open(SO_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Expected {SO_PATH} to be an ELF shared library"
    try:
        library = ctypes.CDLL(SO_PATH)
        function = library.encode_payload
    except (OSError, AttributeError) as exc:
        pytest.fail(f"Could not load encode_payload from {SO_PATH}: {exc}")
    function.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p]
    function.restype = ctypes.c_char_p
    return library, function


def test_libencoder_compiled():
    """Verify that the shared library was compiled and exports working native code."""
    assert os.path.exists(SO_PATH), f"Shared library missing: {SO_PATH}"
    assert os.path.isfile(SO_PATH), f"Expected {SO_PATH} to be a file"

    library, encode = load_encoder()
    result = encode(b"native_probe", b"android", SEED.encode("utf-8"))
    assert result is not None, "encode_payload returned NULL"
    assert result.decode("utf-8") == "android_native_probe_X9F-44A-B21"
    assert library is not None


def test_mock_server_valid_request():
    """Preserve the original valid-request assertion."""
    response = request({"payload": "hello", "platform": "ios"}, AUTH)
    assert response.status_code == 200, (
        f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response, got: {response.text}")
    assert data.get("status") == "success", (
        f"Expected status 'success', got: {data.get('status')}"
    )
    expected_result = "ios_hello_X9F-44A-B21"
    assert data.get("result") == expected_result, (
        f"Expected result '{expected_result}', got: {data.get('result')}"
    )


def test_mock_server_unauthorized_request():
    """Preserve the original missing-auth assertion and reject an incorrect token."""
    response = request({"payload": "test", "platform": "android"})
    assert response.status_code == 401, (
        f"Expected HTTP 401 for missing auth, got {response.status_code}. Response: {response.text}"
    )

    response = request(
        {"payload": secrets.token_hex(8), "platform": "ios"},
        {"Authorization": "Bearer incorrect-token"},
    )
    assert response.status_code == 401, (
        f"Expected HTTP 401 for incorrect auth, got {response.status_code}. Response: {response.text}"
    )


def test_mock_server_different_payload():
    """Preserve the original second fixed authorized request."""
    response = request({"payload": "pytest_payload", "platform": "android"}, AUTH)
    assert response.status_code == 200, (
        f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response, got: {response.text}")
    expected_result = "android_pytest_payload_X9F-44A-B21"
    assert data.get("result") == expected_result, (
        f"Expected result '{expected_result}', got: {data.get('result')}"
    )


def test_randomized_requests_match_native_library():
    """Exercise unpredictable inputs and derive each expected answer from the submitted library."""
    library, encode = load_encoder()
    alphabet = string.ascii_letters + string.digits + "-_"

    for _ in range(8):
        payload = "probe_" + "".join(secrets.choice(alphabet) for _ in range(24))
        platform = "abi_" + "".join(secrets.choice(alphabet) for _ in range(12))

        native = encode(
            payload.encode("utf-8"), platform.encode("utf-8"), SEED.encode("utf-8")
        )
        assert native is not None, "encode_payload returned NULL"
        expected = native.decode("utf-8")
        assert expected == f"{platform}_{payload}_{SEED}", (
            "The submitted shared library does not implement encoder.c's required behavior"
        )

        response = request({"payload": payload, "platform": platform}, AUTH)
        assert response.status_code == 200, (
            f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"
        )
        try:
            data = response.json()
        except ValueError:
            pytest.fail(f"Expected JSON response, got: {response.text}")
        assert data.get("status") == "success"
        assert data.get("result") == expected, (
            f"Server result did not match encode_payload for randomized input: {data}"
        )
    assert library is not None


def listening_socket_inodes():
    """Return socket inodes listening specifically on 127.0.0.1:8080."""
    inodes = set()
    try:
        with open("/proc/net/tcp", "r", encoding="ascii") as f:
            rows = f.readlines()[1:]
    except OSError as exc:
        pytest.fail(f"Could not inspect listening sockets: {exc}")

    for row in rows:
        fields = row.split()
        if len(fields) >= 10 and fields[1].upper() == "0100007F:1F90" and fields[3] == "0A":
            inodes.add(fields[9])
    return inodes


def test_server_process_loaded_libencoder_with_ctypes():
    """Ensure the process serving port 8080 actually loaded the requested ABI library."""
    # Make a valid call immediately before inspecting the serving process.
    response = request(
        {"payload": "mapping_" + secrets.token_hex(12), "platform": "ios"}, AUTH
    )
    assert response.status_code == 200

    deadline = time.time() + 2
    while time.time() < deadline:
        inodes = listening_socket_inodes()
        assert inodes, "No process is listening exactly on 127.0.0.1:8080"

        for pid in os.listdir("/proc"):
            if not pid.isdigit():
                continue
            fd_dir = f"/proc/{pid}/fd"
            try:
                fds = os.listdir(fd_dir)
            except OSError:
                continue

            owns_listener = False
            for fd in fds:
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    owns_listener = True
                    break
            if not owns_listener:
                continue

            try:
                with open(f"/proc/{pid}/maps", "r", encoding="utf-8", errors="replace") as f:
                    maps = f.read()
            except OSError:
                continue
            if SO_PATH in maps and ("_ctypes" in maps or "libffi" in maps):
                return
        time.sleep(0.05)

    pytest.fail(
        "The process serving 127.0.0.1:8080 has not loaded /app/libencoder.so through ctypes"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
