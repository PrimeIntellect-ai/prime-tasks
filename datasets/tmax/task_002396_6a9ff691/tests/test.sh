#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import re
import os
import pytest

def test_compliance_artifacts_score():
    """
    Evaluates the compliance JSON report and firewall script.
    All five content checks must pass, and the script must begin with
    the required Bash shebang.
    """
    score = 0
    total = 5

    json_path = "/home/user/compliance_report.json"
    sh_path = "/home/user/firewall_update.sh"
    script_has_required_shebang = False

    # Check JSON
    if os.path.exists(json_path):
        try:
            with open(json_path, "r") as f:
                data = json.load(f)

                if data.get("attacker_ip") == "10.55.20.156":
                    score += 1
                if data.get("target_port") == 443:
                    score += 1
                if str(data.get("cwe_id", "")).upper() == "CWE-78":
                    score += 1
                if data.get("decoded_payload") == "ls -la /etc/passwd":
                    score += 1
        except Exception:
            pass

    # Check Firewall Script
    if os.path.isfile(sh_path):
        try:
            with open(sh_path, "r") as f:
                content = f.read()
                script_has_required_shebang = content.startswith("#!/bin/bash\n") or content == "#!/bin/bash"
                # Look for standard iptables drop rule
                if re.search(r"iptables\s+-A\s+INPUT\s+.*-s\s+10\.55\.20\.156.*-p\s+tcp.*--dport\s+443.*-j\s+DROP", content) or \
                   re.search(r"iptables\s+-I\s+INPUT\s+.*-s\s+10\.55\.20\.156.*-p\s+tcp.*--dport\s+443.*-j\s+DROP", content):
                    score += 1
        except Exception:
            pass

    metric = score / total
    assert metric >= 0.8, f"Score metric {metric} is below the threshold of 0.8. Score: {score}/{total}. Required at least 4/5 correct items."
    assert score == total, f"All required artifact checks must pass. Score: {score}/{total}."
    assert script_has_required_shebang, "Firewall script must start with #!/bin/bash."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
