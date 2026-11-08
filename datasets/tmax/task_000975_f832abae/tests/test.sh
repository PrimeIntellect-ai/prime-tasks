#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import shutil
import stat
import subprocess
import tempfile


def compute_f1(pred_file, true_ips):
    try:
        with open(pred_file, "r") as f:
            content = f.read()
    except Exception:
        return 0.0

    pred_ips = set(re.findall(r"\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b", content))
    true_set = set(true_ips)

    tp = len(pred_ips.intersection(true_set))
    fp = len(pred_ips - true_set)
    fn = len(true_set - pred_ips)

    if tp == 0:
        return 0.0

    precision = tp / (tp + fp)
    recall = tp / (tp + fn)
    return 2 * (precision * recall) / (precision + recall)


def test_extracted_ips_f1_score():
    pred_file = "/home/user/extracted_ips.txt"
    assert os.path.exists(pred_file), f"File {pred_file} does not exist."

    true_ips = ["10.5.12.4", "192.168.100.52", "172.16.8.88"]
    f1 = compute_f1(pred_file, true_ips)
    assert f1 >= 0.8, f"F1 score for extracted IPs is {f1:.2f}, which is below the threshold of 0.8."

    with open(pred_file, "r") as f:
        lines = f.read().splitlines()
    assert len(lines) == len(true_ips), "The file must contain exactly three IP addresses, one per line."
    assert all(re.fullmatch(r"(?:[0-9]{1,3}\.){3}[0-9]{1,3}", line) for line in lines), \
        "Each line must contain only one IP address."
    assert set(lines) == set(true_ips), "The extracted IP list is incomplete or contains unexpected addresses."


def test_generate_fw_script_exists():
    script_path = "/home/user/generate_fw.py"
    assert os.path.exists(script_path), f"Python script {script_path} does not exist."
    assert os.path.isfile(script_path), f"Python script {script_path} is not a regular file."


def test_apply_firewall_script_exists_and_contains_iptables():
    script_path = "/home/user/apply_firewall.sh"
    assert os.path.exists(script_path), f"Bash script {script_path} does not exist."
    assert os.path.isfile(script_path), f"Bash script {script_path} is not a regular file."

    with open(script_path, "r") as f:
        content = f.read()
    assert "iptables" in content, f"Bash script {script_path} does not contain 'iptables' commands."


def _write_fake_iptables(path):
    fake = r'''#!/usr/bin/python3
import json
import os
import sys

state_path = os.environ["IPTABLES_STATE"]
args = sys.argv[1:]
action_index = None
for i, arg in enumerate(args):
    if arg in ("-C", "--check", "-A", "--append", "-I", "--insert"):
        action_index = i
        break
if action_index is None or action_index + 1 >= len(args):
    sys.exit(0)

action = args[action_index]
chain = args[action_index + 1]
rule = args[action_index + 2:]
if action in ("-I", "--insert") and rule and rule[0].isdigit():
    rule = rule[1:]
key = json.dumps([chain, rule], separators=(",", ":"))
try:
    with open(state_path, "r") as f:
        entries = [line.rstrip("\n") for line in f if line.rstrip("\n")]
except FileNotFoundError:
    entries = []

if action in ("-C", "--check"):
    sys.exit(0 if key in entries else 1)
with open(state_path, "a") as f:
    f.write(key + "\n")
sys.exit(0)
'''
    with open(path, "w") as f:
        f.write(fake)
    os.chmod(path, 0o755)


def _read_rules(state_path):
    if not os.path.exists(state_path):
        return []
    with open(state_path, "r") as f:
        return [json.loads(line) for line in f if line.strip()]


def _assert_rules(rules, expected_ips):
    assert len(rules) == len(expected_ips), \
        f"Expected exactly {len(expected_ips)} installed rules, got {len(rules)}."
    found = []
    for chain, args in rules:
        assert chain == "INPUT", f"Rule is not on the inbound INPUT chain: {chain} {args}"
        source = None
        jump = None
        for i, arg in enumerate(args[:-1]):
            if arg in ("-s", "--source"):
                source = args[i + 1]
            if arg in ("-j", "--jump"):
                jump = args[i + 1]
        assert source is not None, f"Rule has no source address: {chain} {args}"
        if source.endswith("/32"):
            source = source[:-3]
        assert jump == "DROP", f"Rule does not DROP traffic: {chain} {args}"
        found.append(source)
    assert set(found) == set(expected_ips), \
        f"Firewall sources {set(found)} do not match expected sources {set(expected_ips)}."


def _run_twice_and_check(script_path, expected_ips, state_path, env):
    open(state_path, "w").close()
    first = subprocess.run(
        ["/bin/bash", script_path], env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
    )
    assert first.returncode == 0, f"Firewall script failed: {first.stderr}"
    first_rules = _read_rules(state_path)
    _assert_rules(first_rules, expected_ips)

    second = subprocess.run(
        ["/bin/bash", script_path], env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
    )
    assert second.returncode == 0, f"Firewall script failed on its second run: {second.stderr}"
    second_rules = _read_rules(state_path)
    assert second_rules == first_rules, "Running the firewall script twice created duplicate rules."


def test_generator_and_firewall_behavior():
    ip_file = "/home/user/extracted_ips.txt"
    generator = "/home/user/generate_fw.py"
    apply_script = "/home/user/apply_firewall.sh"
    original_ips = ["10.5.12.4", "192.168.100.52", "172.16.8.88"]

    with open(ip_file, "rb") as f:
        saved_ips = f.read()
    with open(apply_script, "rb") as f:
        saved_apply = f.read()
    saved_mode = stat.S_IMODE(os.stat(apply_script).st_mode)

    with tempfile.TemporaryDirectory() as td:
        fake_path = os.path.join(td, "iptables")
        state_path = os.path.join(td, "state")
        _write_fake_iptables(fake_path)

        env = os.environ.copy()
        env["PATH"] = td + os.pathsep + env.get("PATH", "")
        env["IPTABLES_STATE"] = state_path

        real_iptables = shutil.which("iptables", path=os.environ.get("PATH"))
        moved_iptables = None
        try:
            # Intercept both PATH-based and normal absolute /sbin or /usr/sbin invocations.
            if real_iptables:
                moved_iptables = real_iptables + ".verifier-backup-" + secrets.token_hex(8)
                os.rename(real_iptables, moved_iptables)
                shutil.copy2(fake_path, real_iptables)

            _run_twice_and_check(apply_script, original_ips, state_path, env)

            test_ips = [
                f"192.0.2.{secrets.randbelow(200) + 20}",
                f"198.51.100.{secrets.randbelow(200) + 20}",
                f"203.0.113.{secrets.randbelow(200) + 20}",
            ]
            with open(ip_file, "w") as f:
                f.write("\n".join(test_ips) + "\n")
            os.unlink(apply_script)

            generated = subprocess.run(
                ["/usr/bin/python3", generator], text=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
            )
            assert generated.returncode == 0, f"Generator failed: {generated.stderr}"
            assert os.path.isfile(apply_script), "Generator did not create /home/user/apply_firewall.sh."
            with open(apply_script, "r") as f:
                generated_content = f.read()
            assert "iptables" in generated_content, "Generated script contains no iptables command."

            _run_twice_and_check(apply_script, test_ips, state_path, env)
        finally:
            with open(ip_file, "wb") as f:
                f.write(saved_ips)
            with open(apply_script, "wb") as f:
                f.write(saved_apply)
            os.chmod(apply_script, saved_mode)
            if moved_iptables is not None:
                try:
                    os.unlink(real_iptables)
                except FileNotFoundError:
                    pass
                os.rename(moved_iptables, real_iptables)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
