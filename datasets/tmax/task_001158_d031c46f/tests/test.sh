#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import socket
import subprocess
import time
import pytest


def test_finder_binary_exists():
    """Check that the compiled binary exists and is executable."""
    binary_path = "/home/user/finder"
    assert os.path.isfile(binary_path), f"The compiled binary {binary_path} does not exist."
    assert os.access(binary_path, os.X_OK), f"The file {binary_path} is not executable."


def test_finder_accuracy():
    """Exercise the finder against unpredictable, simultaneous listening processes."""
    services = []
    decoys = []
    tests = []

    try:
        # These processes expose passphrases in cmdline but own no listening socket.
        # A finder must correlate the requested socket inode with the owning PID.
        for _ in range(3):
            decoy_secret = "Decoy_" + secrets.token_hex(12)
            decoys.append(subprocess.Popen([
                "python3", "-c", "import time; time.sleep(30)",
                f"--passphrase={decoy_secret}"
            ]))

        # Let the kernel choose unpredictable free ports. Each child inherits the
        # already-listening socket, while the verifier closes its own descriptor.
        for _ in range(5):
            listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            listener.bind(("127.0.0.1", 0))
            listener.listen(1)
            port = listener.getsockname()[1]
            pass_val = "Pass_" + secrets.token_urlsafe(18)

            proc = subprocess.Popen(
                ["python3", "-c", "import time; time.sleep(30)",
                 f"--passphrase={pass_val}"],
                pass_fds=(listener.fileno(),)
            )
            listener.close()
            services.append(proc)
            tests.append((port, pass_val))

        time.sleep(0.3)

        passed = 0
        for port, pass_val in tests:
            try:
                out = subprocess.check_output(
                    ["/home/user/finder", str(port)], timeout=3
                ).decode("utf-8").strip()
                if out == pass_val:
                    passed += 1
            except (subprocess.TimeoutExpired, subprocess.CalledProcessError, Exception):
                pass

        accuracy = passed / len(tests)
        assert accuracy >= 1.0, (
            f"Finder accuracy is {accuracy} ({passed}/{len(tests)} correctly identified), "
            "expected threshold is >= 1.0"
        )
    finally:
        for proc in services + decoys:
            if proc.poll() is None:
                proc.terminate()
        for proc in services + decoys:
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()


def test_firewall_rule_script():
    """Check that the firewall script outputs the correct iptables command."""
    script_path = "/home/user/firewall_rule.sh"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."

    try:
        out = subprocess.check_output(["bash", script_path], timeout=2).decode("utf-8").strip()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Execution of {script_path} failed: {e}")
    except Exception as e:
        pytest.fail(f"Failed to run {script_path}: {e}")

    expected_command = "iptables -A INPUT -p tcp --dport 8443 -j DROP"
    assert out == expected_command, (
        f"Firewall script output mismatch.\nGot: '{out}'\nExpected: '{expected_command}'"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
