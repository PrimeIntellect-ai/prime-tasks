#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shlex
import stat
import subprocess
import tempfile
from collections import Counter

SCRIPT_PATH = "/home/user/auto_deploy.exp"
DEPLOY_PATH = "/home/user/deploy_fw"
LOG_PATH = "/home/user/deployment_success.log"
AUTH_PATH = "/home/user/auth.log"


def derive_target_ip():
    pattern = re.compile(
        r"\[sshd\] Connection closed by authenticating user \S+ "
        r"(\d{1,3}(?:\.\d{1,3}){3}) port \d+ \[preauth\]$"
    )
    counts = Counter()
    with open(AUTH_PATH, "r") as f:
        for line in f:
            match = pattern.search(line.rstrip("\n"))
            if match:
                counts[match.group(1)] += 1

    targets = [ip for ip, count in counts.items() if count == 4]
    assert len(targets) == 1, f"Expected exactly one IP with four matching entries, got {targets}"
    return targets[0]


def test_00_expect_script_executes_interactive_deployment():
    """Execute the submitted Expect artifact and verify its interactive responses."""
    assert os.path.isfile(SCRIPT_PATH), f"File {SCRIPT_PATH} is missing."
    assert os.path.isfile(DEPLOY_PATH), f"File {DEPLOY_PATH} is missing."

    target_ip = derive_target_ip()
    assert target_ip == "192.168.1.105"

    with open(DEPLOY_PATH, "rb") as f:
        original_deploy = f.read()
    original_mode = stat.S_IMODE(os.stat(DEPLOY_PATH).st_mode)

    transcript = None
    result = None
    with tempfile.TemporaryDirectory(prefix="deploy-verifier-") as temp_dir:
        record_path = os.path.join(temp_dir, "responses")
        mock = f'''#!/bin/bash
# Discard any answer sent before each prompt, so the client must wait for it.
drain_input() {{
    while IFS= read -r -t 0.05 _discard; do :; done
}}
drain_input
printf 'Target IP to block: '
IFS= read -r ip || exit 20
sleep 0.15
drain_input
printf 'Select deployment stage (rolling/staged/all): '
IFS= read -r stage || exit 21
sleep 0.15
drain_input
printf 'Confirm deployment (y/n): '
IFS= read -r confirm || exit 22
printf '%s\\n%s\\n%s\\n' "$ip" "$stage" "$confirm" > {shlex.quote(record_path)}
printf 'Deployment logged.\\n'
'''

        try:
            with open(DEPLOY_PATH, "w") as f:
                f.write(mock)
            os.chmod(DEPLOY_PATH, 0o755)
            if os.path.exists(LOG_PATH):
                os.remove(LOG_PATH)

            result = subprocess.run(
                ["/usr/bin/expect", SCRIPT_PATH],
                cwd="/home/user",
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=15,
            )
            if os.path.isfile(record_path):
                with open(record_path, "r") as f:
                    transcript = f.read().splitlines()
        finally:
            with open(DEPLOY_PATH, "wb") as f:
                f.write(original_deploy)
            os.chmod(DEPLOY_PATH, original_mode)

    assert result is not None
    assert result.returncode == 0, f"Expect script failed while driving the prompts:\n{result.stdout}"
    assert transcript == [target_ip, "staged", "y"], (
        f"Incorrect interactive responses. Expected {[target_ip, 'staged', 'y']}, "
        f"got {transcript}. Output:\n{result.stdout}"
    )

    # Execute it again against the real deployment tool and require a freshly
    # generated success log rather than accepting one written in advance.
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)
    real_result = subprocess.run(
        ["/usr/bin/expect", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=15,
    )
    assert real_result.returncode == 0, f"Expect script failed against deploy_fw:\n{real_result.stdout}"


def test_deployment_success_log_exists():
    """Check if the deployment_success.log file was generated."""
    log_path = "/home/user/deployment_success.log"
    assert os.path.isfile(log_path), f"File {log_path} is missing. The expect script may not have been executed successfully."


def test_deployment_success_log_content():
    """Check if the deployment_success.log contains the correct success message."""
    log_path = "/home/user/deployment_success.log"
    assert os.path.isfile(log_path), f"File {log_path} is missing."

    with open(log_path, 'r') as f:
        content = f.read().strip()

    expected_content = "SUCCESS: Blocked 192.168.1.105 in staged environment"
    assert content == expected_content, f"Content of {log_path} is incorrect. Expected '{expected_content}', got '{content}'."


def test_expect_script_exists_and_shebang():
    """Check if the expect script exists and has the correct shebang."""
    script_path = "/home/user/auto_deploy.exp"
    assert os.path.isfile(script_path), f"File {script_path} is missing."

    with open(script_path, 'r') as f:
        first_line = f.readline().strip()

    assert first_line == "#!/usr/bin/expect", f"The expect script {script_path} does not have the correct shebang. Expected '#!/usr/bin/expect', got '{first_line}'."


def test_expect_script_content():
    """Check if the expect script calls the correct script."""
    script_path = "/home/user/auto_deploy.exp"
    assert os.path.isfile(script_path), f"File {script_path} is missing."

    with open(script_path, 'r') as f:
        content = f.read()

    assert "/home/user/deploy_fw" in content or "deploy_fw" in content, f"The expect script does not appear to spawn the target deployment script."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
