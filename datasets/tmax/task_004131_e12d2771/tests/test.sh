#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import secrets
import socket
import pytest

HOST = "127.0.0.1"
PORT = 9999


def get_expected(x):
    return (x * x + x + 41) % 1000


def connect():
    try:
        return socket.create_connection((HOST, PORT), timeout=3)
    except ConnectionRefusedError:
        pytest.fail(f"Connection refused on {HOST}:{PORT}. Ensure the TCP service is running.")
    except socket.timeout:
        pytest.fail(f"Timeout connecting to {HOST}:{PORT}.")


def test_tcp_service_responses():
    # Preserve the original checks, including ordinary and crash-triggering inputs.
    test_cases = [1, 2, 5, 7, 10, 14, 21, 100]

    for x in test_cases:
        expected = get_expected(x)
        try:
            with connect() as s:
                s.sendall(f"{x}\n".encode("utf-8"))
                response = s.recv(1024).decode("utf-8").strip()
                assert response == str(expected), (
                    f"For input {x}, expected {expected} but got {response}"
                )
        except socket.timeout:
            pytest.fail(f"Timeout waiting for response from {HOST}:{PORT} for input {x}.")
        except AssertionError:
            raise
        except Exception as e:
            pytest.fail(f"Unexpected error when testing input {x}: {e}")


def test_unpredictable_streamed_inputs():
    rng = secrets.SystemRandom()
    values = [
        -100000, -999, -14, -7, -1, 0, 7, 14, 999, 100000,
    ]
    values.extend(rng.randint(-100000, 100000) for _ in range(40))
    # Guarantee additional unpredictable crash-triggering values.
    values.extend(7 * rng.randint(-14000, 14000) for _ in range(12))

    payload = "".join(f"{x}\n" for x in values).encode("ascii")

    try:
        with connect() as s:
            s.settimeout(3)
            # Deliberately split records across TCP writes and pipeline many records
            # through one connection to verify proper stream handling.
            pos = 0
            while pos < len(payload):
                width = rng.randint(1, 13)
                s.sendall(payload[pos:pos + width])
                pos += width

            reader = s.makefile("rb")
            for x in values:
                line = reader.readline()
                assert line, f"Service disconnected before replying to streamed input {x}"
                try:
                    response = line.decode("utf-8").strip()
                except UnicodeDecodeError as e:
                    pytest.fail(f"Non-UTF-8 response for input {x}: {e}")
                expected = str(get_expected(x))
                assert response == expected, (
                    f"For streamed input {x}, expected {expected} but got {response}"
                )
    except socket.timeout:
        pytest.fail("Timeout while testing multiple fragmented inputs on one connection.")


def test_service_remains_available():
    x = secrets.SystemRandom().randint(-100000, 100000)
    with connect() as s:
        s.settimeout(3)
        s.sendall(f"{x}\n".encode("ascii"))
        response = s.makefile("rb").readline().decode("utf-8").strip()
        assert response == str(get_expected(x))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
