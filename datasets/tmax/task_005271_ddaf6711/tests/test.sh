#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import os
import random
import socket
import string
import subprocess
import time
import urllib.request


def wait_for_port(port, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.5):
                return
        except OSError:
            time.sleep(0.1)
    raise AssertionError(f"Service did not listen on port {port}")


def test_fuzz_equivalence_audit_tokenizer():
    oracle_path = "/app/reference_oracle/audit_tokenizer"
    agent_path = "/home/user/workspace/audit_tokenizer"

    assert os.path.exists(agent_path), f"Agent binary not found at {agent_path}"
    assert os.access(agent_path, os.X_OK), f"Agent binary at {agent_path} is not executable"
    assert not filecmp.cmp(agent_path, oracle_path, shallow=False), "Agent binary is byte-identical to the reference oracle"

    random.seed(42)
    printable = string.printable.replace("\r", "").replace("\n", "").replace("\x0b", "").replace("\x0c", "")

    # Run 1000 iterations to prevent test timeout while ensuring robustness
    for _ in range(1000):
        length = random.randint(1, 256)
        test_input = "".join(random.choice(printable) for _ in range(length))

        oracle_proc = subprocess.run([oracle_path, test_input], capture_output=True, text=True)
        agent_proc = subprocess.run([agent_path, test_input], capture_output=True, text=True)

        assert oracle_proc.returncode == agent_proc.returncode, f"Return code mismatch on input '{test_input}'"
        assert oracle_proc.stdout == agent_proc.stdout, f"Output mismatch on input '{test_input}'. Oracle: {oracle_proc.stdout}, Agent: {agent_proc.stdout}"


def test_nginx_csp_configuration_and_services_start():
    nginx_config = "/home/user/nginx/nginx.conf"
    ssh_config = "/home/user/ssh/sshd_config"

    assert subprocess.run(["nginx", "-t", "-c", nginx_config], capture_output=True, text=True).returncode == 0, "Invalid nginx configuration"
    assert subprocess.run(["sshd", "-t", "-f", ssh_config], capture_output=True, text=True).returncode == 0, "Invalid sshd configuration"

    # Ensure the provided script must start fresh instances of both services.
    subprocess.run(["bash", "-c", "command -v pkill >/dev/null && { pkill -x nginx || true; pkill -x sshd || true; }"], check=False)
    time.sleep(1)
    started = subprocess.run(["/app/start_services.sh"], capture_output=True, text=True, timeout=10)
    assert started.returncode == 0, f"start_services.sh failed: {started.stdout}{started.stderr}"

    wait_for_port(8080)
    wait_for_port(2222)

    req = urllib.request.Request("http://localhost:8080/")
    with urllib.request.urlopen(req, timeout=5) as response:
        headers = response.headers
        csp_values = headers.get_all("Content-Security-Policy") or []
        assert csp_values, "Content-Security-Policy header is missing"

        csp = "; ".join(csp_values)
        assert "script-src" in csp, "Content-Security-Policy does not contain script-src"
        assert "'self'" in csp, "Content-Security-Policy does not allow 'self'"
        assert "https://trusted.cdn.com" in csp, "Content-Security-Policy does not allow https://trusted.cdn.com"
        assert "'unsafe-inline'" not in csp, "Content-Security-Policy allows unsafe-inline scripts"
        assert "'unsafe-eval'" not in csp, "Content-Security-Policy allows unsafe-eval"

        allowed = {"'self'", "https://trusted.cdn.com"}
        for policy in csp_values:
            directives = []
            for raw_directive in policy.split(";"):
                parts = raw_directive.strip().split()
                if parts:
                    directives.append((parts[0].lower(), parts[1:]))

            script_directives = [sources for name, sources in directives if name == "script-src"]
            assert len(script_directives) == 1, "Each CSP policy must contain exactly one script-src directive"
            assert len(script_directives[0]) == 2 and set(script_directives[0]) == allowed, \
                f"script-src must contain only {sorted(allowed)}, got {script_directives[0]}"

            # These directives override script-src for script elements or attributes.
            assert not any(name in ("script-src-elem", "script-src-attr") for name, _ in directives), \
                "CSP must not override the strict script-src policy"


def test_ssh_hardening():
    config_path = "/home/user/ssh/sshd_config"
    assert os.path.exists(config_path), f"SSH config not found at {config_path}"

    # Parse sshd config using sshd -T
    proc = subprocess.run(["sshd", "-T", "-f", config_path], capture_output=True, text=True)
    assert proc.returncode == 0, f"sshd rejected its configuration: {proc.stderr}"
    output = proc.stdout.lower()

    assert "passwordauthentication no" in output, "PasswordAuthentication is not disabled"
    assert "permitrootlogin no" in output, "PermitRootLogin is not disabled"

    # Check HostKey
    hostkeys = [line for line in output.splitlines() if line.startswith("hostkey ")]
    assert hostkeys, "No SSH host key is configured"
    for hk in hostkeys:
        assert "ed25519" in hk, f"Non-ed25519 host key found: {hk}"

    with socket.create_connection(("127.0.0.1", 2222), timeout=5) as sock:
        banner = sock.recv(255)
    assert banner.startswith(b"SSH-"), f"Port 2222 did not return an SSH banner: {banner!r}"


def test_ssh_key_generated():
    key_path = "/home/user/.ssh/id_ed25519_audit"
    public_path = key_path + ".pub"
    assert os.path.exists(key_path), f"SSH key not found at {key_path}"
    assert os.path.exists(public_path), f"SSH public key not found at {public_path}"

    # Retain the textual format check and additionally validate the private key cryptographically.
    with open(key_path, "r") as f:
        content = f.read()
        assert "OPENSSH PRIVATE KEY" in content or "ED25519" in content, "Generated key does not appear to be an ed25519 private key"

    derived = subprocess.run(
        ["ssh-keygen", "-y", "-P", "", "-f", key_path],
        input="", capture_output=True, text=True, timeout=5
    )
    assert derived.returncode == 0, f"Private key is not a valid unencrypted SSH key: {derived.stderr}"
    derived_fields = derived.stdout.strip().split()
    assert len(derived_fields) >= 2 and derived_fields[0] == "ssh-ed25519", "Private key is not ed25519"

    with open(public_path, "r") as f:
        public_fields = f.read().strip().split()
    assert len(public_fields) >= 2 and public_fields[0] == "ssh-ed25519", "Public key is not ed25519"
    assert public_fields[:2] == derived_fields[:2], "Public key does not match the private key"


def test_integration_script():
    script_path = "/home/user/workspace/run_audit.sh"
    log_path = "/home/user/workspace/audit.log"

    assert os.path.exists(script_path), f"Integration script not found at {script_path}"
    assert os.access(script_path, os.X_OK), f"Integration script at {script_path} is not executable"

    test_event = "integration_test_event"
    oracle_path = "/app/reference_oracle/audit_tokenizer"

    oracle_proc = subprocess.run([oracle_path, test_event], capture_output=True, text=True)
    expected_token = oracle_proc.stdout.strip()

    subprocess.run([script_path, test_event], check=True)

    assert os.path.exists(log_path), f"Audit log not found at {log_path}"

    with open(log_path, "r") as f:
        log_content = f.read()

    expected_entry = f"[{expected_token}] - {test_event}"
    assert expected_entry in log_content, f"Expected log entry '{expected_entry}' not found in audit.log"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
