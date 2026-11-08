#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/app/legacy_config_gen"
AGENT_PATH = "/home/user/new_config_gen"
NUM_TESTS = 100


def generate_random_ip():
    return f"{random.randint(1, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}"


def generate_random_input(num_lines):
    lines = []
    for _ in range(num_lines):
        choice = random.choice(["empty", "comment", "allow", "block"])
        if choice == "empty":
            lines.append("")
        elif choice == "comment":
            lines.append(f"# random comment {random.randint(1, 1000)}")
        elif choice == "allow":
            ip = generate_random_ip()
            p1 = random.randint(1, 30000)
            p2 = random.randint(p1, 65535)
            lines.append(f"ALLOW {ip} {p1}-{p2}")
        else:
            ip = generate_random_ip()
            p = random.randint(1, 65535)
            lines.append(f"BLOCK {ip} {p}")
    return "\n".join(lines) + "\n"


def expected_output(input_content):
    output = []
    for line in input_content.splitlines():
        if not line or line.startswith("#"):
            continue
        fields = line.split()
        if fields[0] == "ALLOW":
            ip = fields[1]
            p1, p2 = fields[2].split("-", 1)
            output.append(
                f"iptables -A INPUT -s {ip} -p tcp --match multiport --dports {int(p1)}:{int(p2)} -j ACCEPT\n"
            )
        elif fields[0] == "BLOCK":
            ip = fields[1]
            port = int(fields[2])
            output.append(
                f"iptables -A INPUT -s {ip} -p tcp --dport {port} -j DROP\n"
            )
    return "".join(output)


@pytest.fixture(scope="session", autouse=True)
def disable_legacy_oracle():
    assert os.path.exists(ORACLE_PATH), f"Oracle program not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle program {ORACLE_PATH} is not executable"

    if os.path.isfile(AGENT_PATH):
        with open(ORACLE_PATH, "rb") as oracle_file, open(AGENT_PATH, "rb") as agent_file:
            assert oracle_file.read() != agent_file.read(), "Agent program is a byte-identical copy of the legacy executable"

    os.remove(ORACLE_PATH)
    assert not os.path.exists(ORACLE_PATH)


def test_agent_program_exists():
    assert os.path.exists(AGENT_PATH), f"Agent's program not found at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"{AGENT_PATH} is not a file"
    assert os.access(AGENT_PATH, os.X_OK), f"{AGENT_PATH} is not executable"


def test_fuzz_equivalence():
    random.seed(42)

    for _ in range(NUM_TESTS):
        num_lines = random.randint(1, 50)
        input_content = generate_random_input(num_lines)
        expected = expected_output(input_content)

        with tempfile.NamedTemporaryFile(mode="w", delete=False) as tmp:
            tmp.write(input_content)
            tmp_path = tmp.name

        try:
            agent_result = subprocess.run(
                [AGENT_PATH, tmp_path], capture_output=True, text=True
            )
            assert agent_result.returncode == 0, (
                f"Return code mismatch on input:\n{input_content}\n"
                f"Expected: 0, Agent: {agent_result.returncode}"
            )
            assert agent_result.stdout == expected, (
                f"Stdout mismatch on input:\n{input_content}\n"
                f"Expected output:\n{expected}\nAgent output:\n{agent_result.stdout}"
            )
        finally:
            os.remove(tmp_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
