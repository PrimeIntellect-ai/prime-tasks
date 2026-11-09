#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import ipaddress
import json
import os
import subprocess
import tempfile

WORKSPACE_DIR = "/home/user/traffic_data"
PAYLOAD_PATH = os.path.join(WORKSPACE_DIR, "payload.txt")
CLIENT_CERT_PATH = os.path.join(WORKSPACE_DIR, "client.crt")
ROOT_CA_PATH = os.path.join(WORKSPACE_DIR, "rootCA.crt")
FIREWALL_RULE_PATH = os.path.join(WORKSPACE_DIR, "firewall_rule.sh")
EXPECTED_CMD = "iptables -A INPUT -s 198.51.100.123 -j DROP"


def decoded_source_ip():
    with open(PAYLOAD_PATH, "rb") as f:
        encoded = b"".join(f.read().split())
    payload = json.loads(base64.b64decode(encoded, validate=True).decode("utf-8"))
    source_ip = payload["source_ip"]
    ipaddress.ip_address(source_ip)
    return source_ip


def test_payload_and_certificate_require_firewall_rule():
    source_ip = decoded_source_ip()
    assert source_ip == "198.51.100.123"

    result = subprocess.run(
        ["openssl", "verify", "-CAfile", ROOT_CA_PATH, CLIENT_CERT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode != 0, "client.crt unexpectedly validates against rootCA.crt"


def test_firewall_rule_exists():
    assert os.path.exists(FIREWALL_RULE_PATH), f"File {FIREWALL_RULE_PATH} does not exist."
    assert os.path.isfile(FIREWALL_RULE_PATH), f"{FIREWALL_RULE_PATH} is not a file."


def test_firewall_rule_is_executable():
    assert os.path.exists(FIREWALL_RULE_PATH), f"File {FIREWALL_RULE_PATH} does not exist."
    assert os.access(FIREWALL_RULE_PATH, os.X_OK), f"File {FIREWALL_RULE_PATH} is not executable."


def test_firewall_rule_content_and_execution():
    assert os.path.exists(FIREWALL_RULE_PATH), f"File {FIREWALL_RULE_PATH} does not exist."
    with open(FIREWALL_RULE_PATH, "r") as f:
        content = f.read().strip()

    lines = [
        line.strip()
        for line in content.splitlines()
        if line.strip()
        and not line.strip().startswith("#")
        and line.strip() != "#!/bin/bash"
        and line.strip() != "#!/bin/sh"
    ]

    # Preserve the original assertion and additionally require exactly one command.
    assert any(EXPECTED_CMD in line for line in lines), (
        f"Expected command '{EXPECTED_CMD}' not found in {FIREWALL_RULE_PATH}."
    )
    source_ip = decoded_source_ip()
    derived_cmd = f"iptables -A INPUT -s {source_ip} -j DROP"
    assert lines == [derived_cmd], (
        f"{FIREWALL_RULE_PATH} must contain exactly the command '{derived_cmd}'."
    )

    # Execute the artifact with a harmless mock iptables and verify its arguments.
    with tempfile.TemporaryDirectory() as mock_bin:
        log_path = os.path.join(mock_bin, "iptables.args")
        mock_iptables = os.path.join(mock_bin, "iptables")
        with open(mock_iptables, "w") as f:
            f.write("#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$IPTABLES_LOG\"\n")
        os.chmod(mock_iptables, 0o755)

        env = os.environ.copy()
        env["PATH"] = mock_bin + os.pathsep + env.get("PATH", "")
        env["IPTABLES_LOG"] = log_path
        result = subprocess.run(
            ["/bin/sh", FIREWALL_RULE_PATH],
            cwd=WORKSPACE_DIR,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, result.stderr
        assert os.path.isfile(log_path), "The firewall script did not invoke iptables."
        with open(log_path, "r") as f:
            args = f.read().splitlines()
        assert args == ["-A", "INPUT", "-s", source_ip, "-j", "DROP"]
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
