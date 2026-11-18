#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import pwd
import random
import secrets
import subprocess
import tempfile
from pathlib import Path

WAF_SCRIPT = "/home/user/waf_filter.sh"
NETWORK_SCRIPT = "/home/user/network_harden.sh"
SSH_SCRIPT = "/home/user/ssh_harden.sh"

EVIL_CORPUS_DIR = "/app/corpus/evil"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
AUTHORIZED_KEYS_PATH = "/home/user/.ssh/authorized_keys"
CHECKSUM_PATH = "/home/user/.ssh/authorized_keys.sha256"


def test_scripts_exist_and_executable():
    for script in [WAF_SCRIPT, NETWORK_SCRIPT, SSH_SCRIPT]:
        assert os.path.isfile(script), f"Expected script {script} does not exist."
        assert os.access(script, os.X_OK), f"Expected script {script} to be executable."


def run_waf(path):
    return subprocess.run(["/bin/bash", WAF_SCRIPT, str(path)], capture_output=True, text=True)


def test_waf_filter_adversarial_corpus():
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]

    bypassed_evil = []
    modified_clean = []

    for evil_file in evil_files:
        result = run_waf(evil_file)
        output = result.stdout.strip()
        if result.returncode != 1 or output != "EVIL":
            bypassed_evil.append(os.path.basename(evil_file))

    for clean_file in clean_files:
        result = run_waf(clean_file)
        output = result.stdout.strip()
        if result.returncode != 0 or output != "CLEAN":
            modified_clean.append(os.path.basename(clean_file))

    error_msg = []
    if bypassed_evil:
        error_msg.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_evil)}")
    if modified_clean:
        error_msg.append(f"{len(modified_clean)} of {len(clean_files)} clean modified: {', '.join(modified_clean)}")

    assert not error_msg, "WAF Filter failed: " + "; ".join(error_msg)


def test_waf_filter_generated_requests_at_opaque_paths():
    clean_a = secrets.token_hex(10)
    clean_b = str(secrets.randbelow(900000000) + 100000000)
    host = secrets.token_hex(5) + ".example"
    evil_values = [
        f"{secrets.token_hex(3)}/../{secrets.token_hex(3)}",
        f"{secrets.token_hex(4)};{secrets.token_hex(3)}",
        f"{secrets.token_hex(4)}|{secrets.token_hex(3)}",
        f"{secrets.token_hex(4)}&{secrets.token_hex(3)}",
        f"`{secrets.token_hex(4)}`",
    ]
    cases = [
        (f"GET /index.cgi?target={clean_a} HTTP/1.1\r\nHost: {host}\r\n\r\n", 0, "CLEAN"),
        (f"POST /index.cgi HTTP/1.1\r\nHost: {host}\r\nContent-Type: application/x-www-form-urlencoded\r\n\r\ntarget={clean_b}", 0, "CLEAN"),
        (f"GET /index.cgi?target={evil_values[0]} HTTP/1.1\r\nHost: {host}\r\n\r\n", 1, "EVIL"),
        (f"POST /cgi-bin/test HTTP/1.1\r\nHost: {host}\r\n\r\ntarget={evil_values[1]}", 1, "EVIL"),
        (f"GET /index.cgi?target={evil_values[2]} HTTP/1.1\r\nHost: {host}\r\n\r\n", 1, "EVIL"),
        (f"POST /index.cgi HTTP/1.1\r\nHost: {host}\r\n\r\ntarget={evil_values[3]}", 1, "EVIL"),
        (f"GET /index.cgi?target={evil_values[4]} HTTP/1.1\r\nHost: {host}\r\n\r\n", 1, "EVIL"),
    ]
    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="waf_cases_") as directory:
        paths = []
        for request, expected_code, expected_output in cases:
            path = Path(directory) / secrets.token_hex(16)
            path.write_text(request)
            paths.append((path, expected_code, expected_output))

        random.SystemRandom().shuffle(paths)
        for path, expected_code, expected_output in paths:
            result = run_waf(path)
            assert result.returncode == expected_code, f"Wrong WAF status for generated request: {result.stderr}"
            assert result.stdout.strip() == expected_output, "Wrong WAF output for generated request."


def test_network_harden_script_contents():
    with open(NETWORK_SCRIPT, "r") as f:
        content = f.read()

    assert ("8080" in content and ("DROP" in content or "REJECT" in content)), \
        "Network harden script does not appear to block TCP port 8080."
    assert ("443" in content and "ACCEPT" in content), \
        "Network harden script does not appear to explicitly allow TCP port 443."


def option_value(args, names):
    for index, arg in enumerate(args):
        for name in names:
            if arg == name and index + 1 < len(args):
                return args[index + 1]
            if arg.startswith(name + "="):
                return arg.split("=", 1)[1]
    return None


def is_input_rule(args):
    return option_value(args, ["-A", "--append", "-I", "--insert"]) == "INPUT"


def is_tcp_rule(args):
    protocol = option_value(args, ["-p", "--protocol"])
    module = option_value(args, ["-m", "--match"])
    return (protocol and protocol.lower() == "tcp") or (module and module.lower() == "tcp")


def has_destination_port(args, port):
    value = option_value(args, ["--dport", "--destination-port", "--dports"])
    if value is None:
        return False
    return port in value.split(",")


def jump_target(args):
    value = option_value(args, ["-j", "--jump"])
    return value.upper() if value else None


def test_network_harden_executes_valid_iptables_policy():
    with tempfile.TemporaryDirectory(prefix="iptables_mock_") as directory:
        os.chmod(directory, 0o755)
        log_path = os.path.join(directory, "calls.jsonl")
        Path(log_path).touch()
        os.chmod(log_path, 0o666)

        mock_path = os.path.join(directory, "iptables")
        Path(mock_path).write_text(
            "#!/usr/bin/python3\n"
            "import json, sys\n"
            f"with open({log_path!r}, 'a') as f:\n"
            "    f.write(json.dumps(sys.argv[1:]) + '\\n')\n"
        )
        os.chmod(mock_path, 0o755)

        account = pwd.getpwnam("user")
        def demote():
            os.setgroups([])
            os.setgid(account.pw_gid)
            os.setuid(account.pw_uid)

        env = os.environ.copy()
        env["PATH"] = directory + ":/usr/bin:/bin"
        result = subprocess.run(
            ["/bin/bash", NETWORK_SCRIPT],
            capture_output=True,
            text=True,
            env=env,
            preexec_fn=demote,
        )
        assert result.returncode == 0, f"Network harden script failed with error: {result.stderr}"

        with open(log_path) as f:
            calls = [json.loads(line) for line in f if line.strip()]

    blocks_8080 = any(
        is_input_rule(call) and is_tcp_rule(call) and has_destination_port(call, "8080")
        and jump_target(call) in {"DROP", "REJECT"}
        for call in calls
    )
    allows_443 = any(
        is_input_rule(call) and is_tcp_rule(call) and has_destination_port(call, "443")
        and jump_target(call) == "ACCEPT"
        for call in calls
    )
    assert blocks_8080, "The executed script did not install an INPUT TCP rule blocking port 8080."
    assert allows_443, "The executed script did not install an INPUT TCP rule allowing port 443."


def test_ssh_harden_script():
    os.makedirs(os.path.dirname(AUTHORIZED_KEYS_PATH), exist_ok=True)

    initial_keys = [
        "ssh-rsa AAAAB3NzaC1yc2E... user1@host",
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... user2@host",
        "ssh-dss AAAAB3NzaC1kc3M... user3@host",
        "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTY... user4@host"
    ]

    with open(AUTHORIZED_KEYS_PATH, "w") as f:
        f.write("\n".join(initial_keys) + "\n")

    result = subprocess.run(["/bin/bash", SSH_SCRIPT], capture_output=True, text=True)
    assert result.returncode == 0, f"SSH harden script failed with error: {result.stderr}"

    assert os.path.isfile(AUTHORIZED_KEYS_PATH), "authorized_keys file was deleted."
    with open(AUTHORIZED_KEYS_PATH, "r") as f:
        cleaned_keys = f.read().splitlines()

    for key in cleaned_keys:
        assert not key.startswith("ssh-rsa"), "ssh-rsa key was not removed."
        assert not key.startswith("ssh-dss"), "ssh-dss key was not removed."

    assert any(key.startswith("ssh-ed25519") for key in cleaned_keys), "Valid ssh-ed25519 key was incorrectly removed."
    assert any(key.startswith("ecdsa-sha2-nistp256") for key in cleaned_keys), "Valid ecdsa key was incorrectly removed."

    assert os.path.isfile(CHECKSUM_PATH), f"Checksum file {CHECKSUM_PATH} was not created."

    with open(AUTHORIZED_KEYS_PATH, "rb") as f:
        expected_hash = hashlib.sha256(f.read()).hexdigest()

    with open(CHECKSUM_PATH, "r") as f:
        actual_checksum_content = f.read().strip()

    assert expected_hash in actual_checksum_content, "The SHA256 checksum does not match the cleaned authorized_keys file."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
