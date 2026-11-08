#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re

def get_expected_ips(log_path):
    if not os.path.exists(log_path):
        return []

    with open(log_path, 'r') as f:
        content = f.read()

    records = re.findall(r'\[RECORD_START\](.*?)\[RECORD_END\]', content, re.DOTALL)
    ips = set()
    for record in records:
        lines = record.strip().split('\n')
        service = None
        action = None
        target_ip = None
        status = None

        in_details = False
        for line in lines:
            if line.startswith('Details:'):
                in_details = True
                continue
            if not in_details:
                if line.startswith('Service: '):
                    service = line.split(' ', 1)[1].strip()
                elif line.startswith('Action: '):
                    action = line.split(' ', 1)[1].strip()
                elif line.startswith('TargetIP: '):
                    target_ip = line.split(' ', 1)[1].strip()

        # The true Status is always at the root, at the end of the record.
        for line in reversed(lines):
            if line.startswith('Status: '):
                status = line.split(' ', 1)[1].strip()
                break

        if service == 'firewall' and action == 'ALLOW' and status == 'SUCCESS':
            if target_ip:
                ips.add(target_ip)

    return sorted(list(ips))

def test_script_exists_and_executable():
    """Test that the output script exists and is executable."""
    script_path = "/home/user/apply_firewall.sh"
    assert os.path.isfile(script_path), f"Output script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Output script {script_path} is not executable."

def test_script_content():
    """Test that the output script contains the correct content."""
    script_path = "/home/user/apply_firewall.sh"
    log_path = "/home/user/config_audit.log"

    assert os.path.isfile(script_path), f"Output script {script_path} does not exist."

    expected_ips = get_expected_ips(log_path)

    with open(script_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) > 0, "The output script is empty."
    assert lines[0] == "#!/bin/bash", "The output script must start with #!/bin/bash."

    script_ips = []
    for line in lines[1:]:
        match = re.match(r'^iptables -A INPUT -s (\S+) -j ACCEPT$', line)
        assert match, f"Invalid command format in script: {line}"
        script_ips.append(match.group(1))

    assert script_ips == expected_ips, (
        f"The IPs in the script do not match the expected IPs or are not sorted correctly.\n"
        f"Expected: {expected_ips}\n"
        f"Found: {script_ips}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
