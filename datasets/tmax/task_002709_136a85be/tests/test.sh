#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
import tempfile
import uuid

import pytest


def test_bashrc_env_vars():
    bashrc_path = "/home/user/.bashrc"
    assert os.path.exists(bashrc_path), f"{bashrc_path} does not exist."
    with open(bashrc_path, "r") as f:
        content = f.read()

    assert re.search(r"export\s+SSH_PORT\s*=\s*[\"']?9922[\"']?", content), "SSH_PORT=9922 not properly exported in /home/user/.bashrc"
    assert re.search(r"export\s+EMAIL_PORT\s*=\s*[\"']?2525[\"']?", content), "EMAIL_PORT=2525 not properly exported in /home/user/.bashrc"


def test_fw_generator():
    generator_path = "/home/user/fw_generator.py"
    assert os.path.exists(generator_path), f"{generator_path} does not exist."
    assert os.path.isfile(generator_path), f"{generator_path} is not a regular file."

    env = os.environ.copy()
    env["SSH_PORT"] = "9922"
    env["EMAIL_PORT"] = "2525"

    try:
        subprocess.run(["python3", generator_path], env=env, check=True, capture_output=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"fw_generator.py failed to run: {e.stderr.decode()}")

    rules_path = "/home/user/fw_rules.txt"
    assert os.path.exists(rules_path), f"{rules_path} was not created."

    with open(rules_path, "r") as f:
        content = f.read().strip().split('\n')

    expected_lines = [
        "iptables -A INPUT -p tcp --dport 9922 -j ACCEPT",
        "iptables -A INPUT -p tcp --dport 2525 -j ACCEPT"
    ]

    assert len(content) >= 2, f"{rules_path} does not contain enough lines."
    assert expected_lines[0] in content, f"Missing rule: {expected_lines[0]} in {rules_path}"
    assert expected_lines[1] in content, f"Missing rule: {expected_lines[1]} in {rules_path}"


def run_detector(detector_path, log_path):
    return subprocess.run(
        ["python3", detector_path, log_path],
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_detector_script():
    detector_path = "/home/user/detector.py"
    assert os.path.exists(detector_path), f"{detector_path} does not exist."
    assert os.path.isfile(detector_path), f"{detector_path} is not a regular file."

    clean_dir = "/app/corpora/clean"
    evil_dir = "/app/corpora/evil"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    clean_failures = []
    for cf in clean_files:
        res = run_detector(detector_path, cf)
        if res.stdout.strip() != "CLEAN":
            clean_failures.append(os.path.basename(cf))

    evil_failures = []
    for ef in evil_files:
        res = run_detector(detector_path, ef)
        if res.stdout.strip() != "EVIL":
            evil_failures.append(os.path.basename(ef))

    err_msg = []
    if evil_failures:
        err_msg.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        err_msg.append(f"{len(clean_failures)} of {len(clean_files)} clean modified: {', '.join(clean_failures)}")

    if err_msg:
        pytest.fail(" | ".join(err_msg))

    # Holdout cases use randomized, label-neutral paths. Expected answers are
    # derived here from the case construction rather than from directory names.
    pid = random.randint(2000, 9000)
    port = random.randint(30000, 60000)
    user = "acct_" + uuid.uuid4().hex[:8]
    cases = [
        ("EVIL", f"sshd[{pid}]: Authentication refused: bad ownership or modes for directory /home/{user}"),
        ("EVIL", f"sshd[{pid + 1}]: Authentication refused: bad ownership or modes for file /home/{user}/.ssh/authorized_keys"),
        ("EVIL", f"Oct 18 04:12:31 gateway sshd[{pid + 2}]: Authentication refused: bad ownership or modes for directory /home/{user}/.ssh\nsshd[{pid + 2}]: Connection closed by authenticating user {user} 10.24.8.9 port {port} [preauth]"),
        ("EVIL", f"sshd[{pid + 3}]: Authentication refused: bad ownership or modes for file /srv/accounts/{user}/authorized_keys"),
        ("CLEAN", f"sshd[{pid + 4}]: Accepted publickey for {user} from 10.20.30.40 port {port} ssh2: RSA SHA256:abcdef"),
        ("CLEAN", f"sshd[{pid + 5}]: Failed password for invalid user {user} from 172.16.4.2 port {port - 1} ssh2"),
        ("CLEAN", f"sshd[{pid + 6}]: Connection closed by authenticating user {user} 192.0.2.15 port {port - 2} [preauth]"),
        ("CLEAN", f"sshd[{pid + 7}]: Accepted password for {user} from 198.51.100.8 port {port - 3} ssh2\nsshd[{pid + 7}]: pam_unix(sshd:session): session opened for user {user}"),
    ]
    random.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="ssh-holdout-") as holdout_dir:
        failures = []
        for expected, text in cases:
            path = os.path.join(holdout_dir, uuid.uuid4().hex + ".txt")
            with open(path, "w") as f:
                f.write(text + "\n")
            res = run_detector(detector_path, path)
            actual = res.stdout.strip()
            if res.returncode != 0 or actual != expected:
                failures.append(
                    f"expected {expected}, got {actual!r}, return code {res.returncode}"
                )
        assert not failures, "Holdout detector failures: " + " | ".join(failures)


def test_logrotate_conf():
    conf_path = "/home/user/logrotate.conf"
    assert os.path.exists(conf_path), f"{conf_path} does not exist."
    assert os.path.isfile(conf_path), f"{conf_path} is not a regular file."

    with open(conf_path, "r") as f:
        content = f.read()

    assert "/var/log/mail.log" in content, "/var/log/mail.log not specified in logrotate.conf"
    assert re.search(r"\bdaily\b", content), "Directive 'daily' missing in logrotate.conf"
    assert re.search(r"\brotate\s+7\b", content), "Directive 'rotate 7' missing in logrotate.conf"
    assert re.search(r"\bcompress\b", content), "Directive 'compress' missing in logrotate.conf"
    assert re.search(r"\bmissingok\b", content), "Directive 'missingok' missing in logrotate.conf"

    # Strip comments, verify balanced stanza syntax, and require all directives
    # to be active directives inside the /var/log/mail.log stanza.
    active_lines = []
    for line in content.splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            active_lines.append(line)
    active = "\n".join(active_lines)

    depth = 0
    for char in active:
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            assert depth >= 0, "logrotate.conf has an unmatched closing brace"
    assert depth == 0, "logrotate.conf has unbalanced braces"

    match = re.search(r"(?m)^\s*/var/log/mail\.log\s*\{(?P<body>.*?)^\s*\}\s*$", active, re.DOTALL)
    assert match, "/var/log/mail.log must have a valid logrotate stanza"
    body_lines = [line.strip() for line in match.group("body").splitlines() if line.strip()]

    assert any(re.fullmatch(r"daily", line) for line in body_lines), "Active 'daily' directive missing from mail log stanza"
    assert any(re.fullmatch(r"rotate\s+7", line) for line in body_lines), "Active 'rotate 7' directive missing from mail log stanza"
    assert any(re.fullmatch(r"compress", line) for line in body_lines), "Active 'compress' directive missing from mail log stanza"
    assert any(re.fullmatch(r"missingok", line) for line in body_lines), "Active 'missingok' directive missing from mail log stanza"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
