#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import os
import secrets
import socket
import subprocess
import pytest


def get_expected_score(seq, c00, c01, c10, c11):
    cmd = ["/app/legacy_oracle", seq, str(c00), str(c01), str(c10), str(c11)]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return float(result.stdout.strip())
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Legacy oracle failed: {e.stderr}")
    except ValueError:
        pytest.fail(f"Could not parse legacy oracle output: {result.stdout}")


def test_files_exist():
    """Check that the expected source and compiled binary exist."""
    assert os.path.exists("/home/user/sim_server.cpp"), "Source file /home/user/sim_server.cpp is missing."
    assert os.path.exists("/home/user/sim_server"), "Compiled binary /home/user/sim_server is missing."
    assert os.access("/home/user/sim_server", os.X_OK), "/home/user/sim_server is not executable."
    assert not filecmp.cmp("/home/user/sim_server", "/app/legacy_oracle", shallow=False), \
        "The submitted executable must not be a byte-identical copy of the legacy oracle."


PUBLIC_CASES = [
    ("A", 1.0, 0.0, 0.0, 1.0),
    ("ACGTACGT", 1.0, 0.5, 0.5, 1.0),
    ("ACGTACGTACGTACGTACGT", 2.0, -0.1, -0.1, 0.5),
    ("GATTACA", 0.8, 0.2, 0.2, 1.2),
]


def make_hidden_cases():
    rng = secrets.SystemRandom()
    lengths = rng.sample([n for n in range(2, 33) if n not in (7, 8, 20)], 6)
    cases = []
    for n in lengths:
        seq = ''.join(rng.choice("ACGT") for _ in range(n))
        c00 = rng.choice([0.35, 0.6, 0.9, 1.25, 1.7, 2.4])
        c11 = rng.choice([0.4, 0.75, 1.1, 1.55, 2.1, 2.8])
        # |rho| < 1 guarantees a symmetric positive-definite covariance matrix.
        rho = rng.choice([-0.72, -0.51, -0.29, -0.13, 0.17, 0.34, 0.58, 0.76])
        off_diag = rho * (c00 * c11) ** 0.5
        cases.append((seq, c00, off_diag, off_diag, c11))
    return cases


ALL_CASES = PUBLIC_CASES + make_hidden_cases()


@pytest.mark.parametrize("seq, c00, c01, c10, c11", ALL_CASES)
def test_sim_server_responses(seq, c00, c01, c10, c11):
    """Test the TCP server against the legacy oracle's output."""
    expected = get_expected_score(seq, c00, c01, c10, c11)
    payload = f"{seq},{c00},{c01},{c10},{c11}\n"

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(10.0)

    try:
        s.connect(("127.0.0.1", 9000))
        s.sendall(payload.encode("utf-8"))
        response = s.recv(1024).decode("utf-8")
    except ConnectionRefusedError:
        pytest.fail("Connection refused. Is the server running on 127.0.0.1:9000?")
    except socket.timeout:
        pytest.fail("Server timed out while processing the request.")
    except Exception as e:
        pytest.fail(f"Failed to communicate with server: {e}")
    finally:
        s.close()

    assert response.endswith("\n"), f"Response must end with a newline, got: {repr(response)}"

    try:
        actual = float(response.strip())
    except ValueError:
        pytest.fail(f"Could not parse server response as float: {repr(response)}")

    assert abs(actual - expected) <= 0.001, \
        f"For input {payload.strip()}, expected ~{expected:.4f}, but got {actual:.4f}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
