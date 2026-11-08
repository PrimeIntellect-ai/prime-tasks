#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import base64
import random
import string
import subprocess
import os
import stat
import pytest

ORACLE_CODE = """
import sys
import subprocess

def check_elf():
    try:
        with open('/home/user/server.bin', 'rb') as f:
            header = f.read(5)
            if header[:4] != b'\\x7fELF' or header[4] != 2:
                return False
        return True
    except:
        return False

def main():
    if not check_elf():
        print("AUDIT FAIL: SERVER BINARY INVALID")
        sys.exit(1)

    if len(sys.argv) < 2:
        return

    b64_input = sys.argv[1]

    try:
        proc = subprocess.run(['base64', '-d'], input=b64_input.encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if proc.returncode != 0:
            print("DECODE ERROR")
            sys.exit(0)
        decoded = proc.stdout.decode('utf-8', errors='replace')
    except Exception:
        print("DECODE ERROR")
        sys.exit(0)

    if not decoded.startswith("https://"):
        print("INVALID PROTOCOL")
        sys.exit(0)

    rest = decoded[8:]
    domain = rest.split('/', 1)[0]

    if domain == "auth-secure.internal.corp":
        print(f"SAFE - Content-Security-Policy: default-src 'none'; frame-ancestors https://{domain};")
    else:
        print(f"OPEN REDIRECT ALERT: {domain}")

if __name__ == "__main__":
    main()
"""

@pytest.fixture(scope="session", autouse=True)
def setup_oracle():
    os.makedirs("/verify", exist_ok=True)
    with open("/verify/oracle.py", "w") as f:
        f.write(ORACLE_CODE)

def generate_fuzz_inputs(n=1000):
    random.seed(42)
    inputs = []

    domains = ["auth-secure.internal.corp", "evil.com", "example.org", "sub.auth-secure.internal.corp"]
    protocols = ["https://", "http://", "ftp://", ""]
    paths = ["/login", "/admin", "", "/index.html?redirect=1"]

    for _ in range(n):
        choice = random.randint(1, 6)
        if choice == 1:
            url = f"https://auth-secure.internal.corp{random.choice(paths)}"
            inputs.append(base64.b64encode(url.encode()).decode())
        elif choice == 2:
            url = f"https://{random.choice(domains[1:])}{random.choice(paths)}"
            inputs.append(base64.b64encode(url.encode()).decode())
        elif choice == 3:
            url = f"https://{random.choice(domains)}"
            inputs.append(base64.b64encode(url.encode()).decode())
        elif choice == 4:
            url = f"{random.choice(protocols[1:])}{random.choice(domains)}{random.choice(paths)}"
            inputs.append(base64.b64encode(url.encode()).decode())
        elif choice == 5:
            bad_b64 = "".join(random.choices(string.punctuation, k=random.randint(5, 15)))
            inputs.append(bad_b64)
        elif choice == 6:
            if random.random() < 0.5:
                inputs.append("")
            else:
                rand_bytes = bytes(random.choices(range(256), k=random.randint(1, 20)))
                inputs.append(base64.b64encode(rand_bytes).decode())

    return inputs

def test_fuzz_equivalence():
    script_path = "/home/user/auditor.sh"
    server_path = "/home/user/server.bin"

    assert os.path.exists(script_path), f"Agent script {script_path} not found."
    assert os.access(script_path, os.X_OK), "Agent script is not executable."

    with open("/bin/ls", "rb") as f:
        fixture_bytes = f.read()

    assert fixture_bytes[:5] == b'\x7fELF\x02', "Original server fixture is not ELF64."
    assert os.path.exists(server_path), "Server binary is missing."
    assert stat.S_ISREG(os.lstat(server_path).st_mode), "Server binary must remain a regular file."
    with open(server_path, "rb") as f:
        assert f.read() == fixture_bytes, "Server binary was modified from the original fixture."

    inputs = generate_fuzz_inputs(1000)

    # Compute every expected result before executing any agent-controlled code.
    oracle_results = []
    for inp in inputs:
        proc = subprocess.run(["python3", "/verify/oracle.py", inp], capture_output=True, text=True)
        oracle_results.append((proc.returncode, proc.stdout.strip()))

    def restore_server_fixture():
        os.makedirs(os.path.dirname(server_path), exist_ok=True)
        tmp_path = server_path + ".verifier-tmp"
        try:
            os.unlink(tmp_path)
        except FileNotFoundError:
            pass
        with open(tmp_path, "wb") as f:
            f.write(fixture_bytes)
        os.chmod(tmp_path, 0o755)
        os.replace(tmp_path, server_path)

    for inp, (oracle_returncode, oracle_stdout) in zip(inputs, oracle_results):
        # The audited binary must be the original fixture for every independent case.
        restore_server_fixture()
        agent_proc = subprocess.run([script_path, inp], capture_output=True, text=True)

        assert oracle_returncode == agent_proc.returncode, (
            f"Return code mismatch on input '{inp}'.\n"
            f"Oracle: {oracle_returncode}\n"
            f"Agent: {agent_proc.returncode}"
        )

        agent_stdout = agent_proc.stdout.strip()
        assert oracle_stdout == agent_stdout, (
            f"Stdout mismatch on input '{inp}'.\n"
            f"Oracle: {oracle_stdout}\n"
            f"Agent: {agent_stdout}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
