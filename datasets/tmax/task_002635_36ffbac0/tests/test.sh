#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import pytest

DETECTOR = "/home/user/detector.py"
BACKDOOR_USER = "b4ckd00r_adm1n_xyz"


def run_detector(log_file):
    try:
        out = subprocess.check_output(
            ["python3", DETECTOR, str(log_file)],
            text=True,
            stderr=subprocess.PIPE,
            timeout=45,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
        pytest.fail(f"Detector script failed with error: {e}")
    return {line.strip() for line in out.split("\n") if line.strip()}


def assert_f1(agent_ips, truth_ips):
    tp = len(truth_ips.intersection(agent_ips))
    fp = len(agent_ips - truth_ips)
    fn = len(truth_ips - agent_ips)

    precision = tp / (tp + fp) if (tp + fp) > 0 else 0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0
    f1 = 2 * (precision * recall) / (precision + recall) if (precision + recall) > 0 else 0

    assert f1 >= 0.95, (
        f"F1 Score {f1:.4f} is below the threshold of 0.95. "
        f"Precision: {precision:.4f}, Recall: {recall:.4f}. "
        f"Detected IPs: {agent_ips}"
    )


def test_detector_f1_score(tmp_path):
    assert os.path.isfile(DETECTOR), f"Detector script not found at {DETECTOR}"

    truth_file = "/truth/held_out_auth.log"
    if os.path.isfile(truth_file):
        log_file = truth_file
        truth_ips = {"192.168.1.55", "10.0.0.9", "172.16.5.101", "198.51.100.22"}
    else:
        log_file_path = tmp_path / "auth.log"
        log_content = """
Dec 15 10:22:33 host sshd[1234]: Accepted publickey for b4ckd00r_adm1n_xyz from 192.168.1.55 port 44322 ssh2
Dec 15 10:22:35 host sshd[1235]: Invalid user admin from 10.1.2.3 port 33444
Dec 15 10:22:36 host sshd[1236]: Accepted password for b4ckd00r_adm1n_xyz from 10.0.0.9 port 55555 ssh2
Dec 15 10:22:37 host sshd[1237]: Accepted publickey for root from 192.168.1.55 port 44322 ssh2
Dec 15 10:22:38 host sshd[1238]: Accepted keyboard-interactive/pam for b4ckd00r_adm1n_xyz from 172.16.5.101 port 12345 ssh2
Dec 15 10:22:39 host sshd[1239]: Failed password for b4ckd00r_adm1n_xyz from 1.1.1.1 port 22
Dec 15 10:22:40 host sshd[1240]: Accepted publickey for b4ckd00r_adm1n_xyz from 198.51.100.22 port 2222 ssh2
"""
        log_file_path.write_text(log_content.strip() + "\n")
        log_file = str(log_file_path)
        truth_ips = {"192.168.1.55", "10.0.0.9", "172.16.5.101", "198.51.100.22"}

    assert_f1(run_detector(log_file), truth_ips)


def test_detector_on_generated_massive_log(tmp_path):
    assert os.path.isfile(DETECTOR), f"Detector script not found at {DETECTOR}"

    rng = random.Random(int.from_bytes(secrets.token_bytes(32), "big"))
    used = {"192.168.1.55", "10.0.0.9", "172.16.5.101", "198.51.100.22"}

    def new_ip():
        while True:
            ip = f"{rng.randint(11, 223)}.{rng.randint(0, 255)}.{rng.randint(0, 255)}.{rng.randint(1, 254)}"
            if ip not in used:
                used.add(ip)
                return ip

    truth_ips = {new_ip() for _ in range(rng.randint(120, 180))}
    benign_ips = [new_ip() for _ in range(1200)]
    methods = ["publickey", "password", "keyboard-interactive/pam"]
    other_users = ["root", "admin", "deploy", "ubuntu", "backup", BACKDOOR_USER + "_backup"]

    def prefix(i):
        if i % 3:
            return f"Jan {1 + (i % 28):2d} {i % 24:02d}:{(i // 3) % 60:02d}:{(i // 7) % 60:02d} gateway sshd[{2000 + i % 50000}]:"
        return f"2026-01-{1 + (i % 28):02d}T{i % 24:02d}:{(i // 3) % 60:02d}:{(i // 7) % 60:02d}+00:00 gateway sshd[{2000 + i % 50000}]:"

    lines = []
    for i, ip in enumerate(truth_ips):
        lines.append(
            f"{prefix(i)} Accepted {rng.choice(methods)} for {BACKDOOR_USER} "
            f"from {ip} port {rng.randint(1024, 65535)} ssh2"
        )

    total_lines = 120000
    while len(lines) < total_lines:
        i = len(lines)
        ip = rng.choice(benign_ips)
        kind = rng.randrange(6)
        port = rng.randint(1024, 65535)
        if kind == 0:
            line = f"{prefix(i)} Failed password for {BACKDOOR_USER} from {ip} port {port} ssh2"
        elif kind == 1:
            line = f"{prefix(i)} Failed publickey for invalid user {BACKDOOR_USER} from {ip} port {port} ssh2"
        elif kind == 2:
            line = f"{prefix(i)} Accepted {rng.choice(methods)} for {rng.choice(other_users)} from {ip} port {port} ssh2"
        elif kind == 3:
            line = f"{prefix(i)} Invalid user {rng.choice(other_users)} from {ip} port {port}"
        elif kind == 4:
            line = f"{prefix(i)} Connection closed by authenticating user {BACKDOOR_USER} {ip} port {port} [preauth]"
        else:
            line = f"{prefix(i)} pam_unix(sshd:auth): authentication failure; rhost={ip} user={BACKDOOR_USER}"
        lines.append(line)

    rng.shuffle(lines)
    generated_log = tmp_path / ("held_out_" + secrets.token_hex(8) + ".log")
    generated_log.write_text("\n".join(lines) + "\n")

    assert_f1(run_detector(generated_log), truth_ips)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
