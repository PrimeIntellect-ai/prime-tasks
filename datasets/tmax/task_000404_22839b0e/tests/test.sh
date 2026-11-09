#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import string
import zipfile
import re
import pytest
import tempfile
import shlex


def generate_random_string():
    length = random.randint(10, 500)
    chars = string.ascii_letters + string.digits + " -<>"
    s = "".join(random.choice(chars) for _ in range(length))

    if random.random() < 0.5:
        s += "<script>alert(1)</script>"
    if random.random() < 0.5:
        s += "<img>"
    if random.random() < 0.5:
        s += f"{random.randint(100,999)}-{random.randint(10,99)}-{random.randint(1000,9999)}"
    if random.random() < 0.5:
        s += f"{random.randint(1000,9999)}-{random.randint(1000,9999)}-{random.randint(1000,9999)}-{random.randint(1000,9999)}"
    if random.random() < 0.5:
        s += f"{random.randint(1000000000000,9999999999999)}"

    s_list = list(s)
    random.shuffle(s_list)
    return "".join(s_list)


def test_fuzz_equivalence():
    agent_script = "/home/user/redact_logs.py"
    oracle_script = "/tests/reference_redactor.py"

    assert os.path.exists(agent_script), f"Agent script {agent_script} not found."
    assert os.access(agent_script, os.X_OK), f"Agent script {agent_script} is not executable."
    assert os.path.exists(oracle_script), f"Oracle script {oracle_script} not found."

    with open(agent_script, "rb") as agent_file, open(oracle_script, "rb") as oracle_file:
        assert agent_file.read() != oracle_file.read(), "Agent script must not be byte-identical to the reference implementation."

    random.seed(42)
    for _ in range(1000):
        test_input = generate_random_string()

        agent_proc = subprocess.run([agent_script, test_input], capture_output=True, text=True)
        oracle_proc = subprocess.run(["python3", oracle_script, test_input], capture_output=True, text=True)

        assert agent_proc.returncode == 0, f"Agent script failed with error: {agent_proc.stderr}"
        assert agent_proc.stdout == oracle_proc.stdout, f"Mismatch on input: {test_input!r}\nExpected: {oracle_proc.stdout!r}\nGot: {agent_proc.stdout!r}"


def test_block_ips_script():
    script_path = "/home/user/block_ips.sh"
    assert os.path.exists(script_path), f"Missing {script_path}"

    zip_path = "/app/network_logs.zip"
    assert os.path.exists(zip_path), f"Missing {zip_path}"

    try:
        with zipfile.ZipFile(zip_path) as zf:
            log_data = zf.read("access.log", pwd=b"h4ckk3y!").decode("utf-8")
    except Exception as e:
        pytest.fail(f"Could not read access.log from zip using the expected password: {e}")

    sqli_ips = set()
    for line in log_data.splitlines():
        if "UNION SELECT" in line or "OR 1=1" in line:
            match = re.search(r'\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b', line)
            if match:
                sqli_ips.add(match.group(0))

    with open(script_path, "r") as f:
        script_content = f.read()

    for ip in sqli_ips:
        assert f"-s {ip}" in script_content, f"IP {ip} is missing from the iptables rules in {script_path}"
        assert "DROP" in script_content, f"DROP action is missing in {script_path}"

    syntax_proc = subprocess.run(["bash", "-n", script_path], capture_output=True, text=True)
    assert syntax_proc.returncode == 0, f"Firewall script has invalid bash syntax: {syntax_proc.stderr}"

    with tempfile.TemporaryDirectory() as mock_bin:
        calls_path = os.path.join(mock_bin, "iptables.calls")
        mock_iptables = os.path.join(mock_bin, "iptables")
        with open(mock_iptables, "w") as f:
            f.write("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$IPTABLES_LOG\"\n")
        os.chmod(mock_iptables, 0o755)

        env = os.environ.copy()
        env["PATH"] = mock_bin + os.pathsep + "/usr/bin:/bin"
        env["IPTABLES_LOG"] = calls_path
        proc = subprocess.run(["bash", script_path], capture_output=True, text=True, env=env, timeout=10)
        assert proc.returncode == 0, f"Firewall script failed when executed: {proc.stderr}"

        calls = []
        if os.path.exists(calls_path):
            with open(calls_path) as f:
                calls = [shlex.split(line) for line in f if line.strip()]

        for ip in sqli_ips:
            assert any(
                "-s" in call
                and call.index("-s") + 1 < len(call)
                and call[call.index("-s") + 1] == ip
                and "-j" in call
                and call.index("-j") + 1 < len(call)
                and call[call.index("-j") + 1].upper() == "DROP"
                for call in calls
            ), f"Executing {script_path} did not issue an iptables DROP rule for source {ip}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
