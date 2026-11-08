#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import socket
import stat
import subprocess
import pytest


def test_stage1_echo_server_running_and_fixed():
    """Test that the echo server is running and bound to the correct socket."""
    sock_path = "/tmp/upstream.sock"
    assert os.path.exists(sock_path), f"Socket file {sock_path} does not exist. Did you start the server?"

    mode = os.stat(sock_path).st_mode
    assert stat.S_ISSOCK(mode), f"{sock_path} is not a socket."

    test_message = b"ping_test_123"
    try:
        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        client.settimeout(2.0)
        client.connect(sock_path)
        client.sendall(test_message)
        data = client.recv(1024)
        client.close()
    except Exception as e:
        pytest.fail(f"Failed to connect and communicate with the echo server at {sock_path}: {e}")

    assert data == test_message, f"Echo server did not return the expected message. Got {data}, expected {test_message}."


def expected_firewall_command(src, dst, ports, proto, action):
    parts = ["iptables", "-A", "INPUT"]
    if src != "any":
        parts.extend(["-s", src])
    if dst != "any":
        parts.extend(["-d", dst])
    parts.extend(["-p", proto])
    if proto != "icmp" and ports != "any":
        if "," in ports:
            parts.extend(["-m", "multiport", "--dports", ports])
        else:
            parts.extend(["--dport", ports])
    parts.extend(["-j", action])
    return " ".join(parts) + "\n"


def test_stage2_fw_compiler_fuzz_equivalence():
    """Exercise the submitted compiler and derive expected output from the DSL specification."""
    agent_script = "/home/user/fw_compiler.sh"
    assert os.path.exists(agent_script), f"Agent script {agent_script} does not exist."
    assert os.path.isfile(agent_script), f"Agent script {agent_script} is not a regular file."
    assert os.access(agent_script, os.X_OK), f"Agent script {agent_script} is not executable."

    random.seed(42)

    def random_ip(prefix):
        if prefix == "any":
            return "any"
        return prefix.replace("X", str(random.randint(1, 254)))

    src_prefixes = ["any", "192.168.1.X", "10.0.0.X"]
    dst_prefixes = ["any", "172.16.0.X", "10.1.1.X"]
    ports_list = ["any", "80", "443", "80,443", "22,23,24"]
    protos_list = ["tcp", "udp", "icmp"]
    actions_list = ["ACCEPT", "DROP", "REJECT"]

    for _ in range(1000):
        src = random_ip(random.choice(src_prefixes))
        dst = random_ip(random.choice(dst_prefixes))
        ports = random.choice(ports_list)
        proto = random.choice(protos_list)
        action = random.choice(actions_list)
        rule = f"{src};{dst};{ports};{proto};{action}"

        agent_res = subprocess.run([agent_script, rule], capture_output=True, text=True, timeout=3)
        expected = expected_firewall_command(src, dst, ports, proto, action)

        assert agent_res.returncode == 0, f"Agent script failed on input: {rule}\nStderr: {agent_res.stderr}"
        assert agent_res.stdout.strip() == expected.strip(), (
            f"Output mismatch on input: {rule}\n"
            f"Expected: {expected.strip()}\n"
            f"Got:      {agent_res.stdout.strip()}"
        )
        assert agent_res.stdout == expected, (
            f"Output was not bit-exact on input: {rule}\n"
            f"Expected bytes: {expected.encode()!r}\n"
            f"Got bytes:      {agent_res.stdout.encode()!r}"
        )


def test_stage3_cron_job_exists_and_behaves_correctly():
    """Test both branches of the every-minute socket monitor command."""
    try:
        crontab_out = subprocess.run(
            ["crontab", "-l"], capture_output=True, text=True, check=True
        ).stdout
    except subprocess.CalledProcessError:
        pytest.fail("Failed to read crontab. No crontab for current user?")

    candidates = []
    for line in crontab_out.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(maxsplit=5)
        if len(parts) >= 6 and " ".join(parts[:5]) == "* * * * *":
            cmd = parts[5]
            if "/tmp/upstream.sock" in cmd and "/home/user/monitor.log" in cmd and "DOWN" in cmd:
                candidates.append(cmd)

    assert candidates, "Could not find a candidate cron job running every minute for the required socket monitor"

    sock_path = "/tmp/upstream.sock"
    moved_sock = "/tmp/upstream.sock.verifier-moved"
    log_path = "/home/user/monitor.log"
    marker = b"VERIFIER_BASELINE\n"

    original_log_exists = os.path.exists(log_path)
    original_log = None
    if original_log_exists:
        with open(log_path, "rb") as f:
            original_log = f.read()

    valid = False
    errors = []
    try:
        for cmd in candidates:
            if os.path.exists(moved_sock):
                os.unlink(moved_sock)
            if not os.path.exists(sock_path) or not stat.S_ISSOCK(os.stat(sock_path).st_mode):
                errors.append("the upstream socket disappeared before the cron command could be tested")
                break

            try:
                with open(log_path, "wb") as f:
                    f.write(marker)

                present_run = subprocess.run(
                    ["/bin/sh", "-c", cmd], capture_output=True, text=True, timeout=5
                )
                with open(log_path, "rb") as f:
                    present_contents = f.read()
                if present_run.returncode != 0 or present_contents != marker:
                    errors.append(f"command changed the log while the socket existed: {cmd}")
                    continue

                os.rename(sock_path, moved_sock)
                try:
                    absent_run = subprocess.run(
                        ["/bin/sh", "-c", cmd], capture_output=True, text=True, timeout=5
                    )
                    with open(log_path, "rb") as f:
                        absent_contents = f.read()
                finally:
                    if os.path.exists(moved_sock) and not os.path.exists(sock_path):
                        os.rename(moved_sock, sock_path)

                if absent_run.returncode == 0 and absent_contents == marker + b"DOWN\n":
                    valid = True
                    break
                errors.append(f"command did not append exactly DOWN followed by a newline when the socket was absent: {cmd}")
            except (OSError, subprocess.SubprocessError) as e:
                errors.append(f"failed while exercising cron command {cmd!r}: {e}")
                if os.path.exists(moved_sock) and not os.path.exists(sock_path):
                    os.rename(moved_sock, sock_path)
    finally:
        if os.path.exists(moved_sock) and not os.path.exists(sock_path):
            os.rename(moved_sock, sock_path)
        if original_log_exists:
            with open(log_path, "wb") as f:
                f.write(original_log)
        elif os.path.exists(log_path):
            os.unlink(log_path)

    assert valid, "No every-minute cron command implemented the required socket check. " + "; ".join(errors)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
