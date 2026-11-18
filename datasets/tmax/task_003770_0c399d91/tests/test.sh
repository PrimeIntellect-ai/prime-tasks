#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
import tempfile


def compile_c(source, output, extra=None):
    assert os.path.isfile(source), f"File missing: {source}"
    assert os.path.getsize(source) > 0, f"Source file is empty: {source}"
    cmd = ["gcc", "-O2", source, "-o", output]
    if extra:
        cmd.extend(extra)
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"Compilation failed for {source}:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(output), f"Compiler did not create: {output}"


def test_attacker_ip():
    path = "/home/user/attacker_ip.txt"
    assert os.path.isfile(path), f"File missing: {path}"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "203.0.113.88", f"Expected '203.0.113.88', but got '{content}'"


def test_block_ip_script():
    path = "/home/user/block_ip.sh"
    assert os.path.isfile(path), f"File missing: {path}"
    with open(path, "r") as f:
        content = f.read().strip()

    assert "iptables" in content, "Missing 'iptables' command in script"
    assert "203.0.113.88" in content, "Missing attacker IP in script"
    assert "-p tcp" in content or "--protocol tcp" in content, "Missing TCP protocol flag in script"
    assert "-j DROP" in content or "--jump DROP" in content, "Missing DROP target in script"
    assert ("-A INPUT" in content or "-I INPUT" in content or
            "--append INPUT" in content or "--insert INPUT" in content), "Missing INPUT chain rule in script"


def test_check_integrity_c_compiles_and_runs():
    source = "/home/user/check_integrity.c"
    binary = "/tmp/check_integrity_test"
    compile_c(source, binary, ["-lcrypto"])
    result = subprocess.run([binary], capture_output=True, text=True, timeout=30)
    assert result.returncode >= 0, "Integrity checker terminated abnormally"


def test_tampered_file():
    path = "/home/user/tampered_file.txt"
    assert os.path.isfile(path), f"File missing: {path}"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "/app/webroot/api/users.json", f"Expected '/app/webroot/api/users.json', but got '{content}'"


def test_redact_c_behavior():
    source = "/home/user/redact.c"
    binary = "/tmp/redact_test"
    compile_c(source, binary)

    rng = random.SystemRandom()
    cards = []
    for i in range(120):
        digits = "".join(str(rng.randrange(10)) for _ in range(16))
        form = i % 3
        if form == 0:
            cards.append(digits)
        elif form == 1:
            cards.append("-".join(digits[j:j+4] for j in range(0, 16, 4)))
        else:
            cards.append(" ".join(digits[j:j+4] for j in range(0, 16, 4)))

    lines = [
        "ordinary 123 123456789012345 12345678901234567 text",
        "keep 1234-5678-9012-345 and 1234 5678 9012 34567",
    ]
    for i, card in enumerate(cards):
        lines.append(f"record={rng.randrange(100000, 999999)} cc:{card}; item={i}")
    payload = "\n".join(lines) + "\n"

    pattern = re.compile(r"\b\d{16}\b|\b\d{4}-\d{4}-\d{4}-\d{4}\b|\b\d{4} \d{4} \d{4} \d{4}\b")
    expected = pattern.sub(lambda m: re.sub(r"\d", "X", m.group(0)), payload)

    with tempfile.TemporaryDirectory() as td:
        input_path = os.path.join(td, "input.txt")
        output_path = os.path.join(td, "output.txt")
        with open(input_path, "w") as f:
            f.write(payload)
        result = subprocess.run([binary, input_path, output_path], capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, f"Redactor failed: {result.stdout}\n{result.stderr}"
        assert os.path.isfile(output_path), "Redactor did not create its requested output file"
        with open(output_path, "r") as f:
            actual = f.read()
        assert actual == expected, "Redactor failed generated behavioral test cases"


def test_redacted_dump_accuracy():
    agent_file = "/home/user/redacted_dump.txt"
    golden_file = "/tests/golden_redacted_dump.txt"

    assert os.path.isfile(agent_file), f"Agent output missing: {agent_file}"
    assert os.path.isfile(golden_file), f"Golden file missing from verifier assets: {golden_file}"

    with open(agent_file, "r") as f:
        agent_text = f.read()
    with open(golden_file, "r") as f:
        golden_text = f.read()

    if len(agent_text) == 0 and len(golden_text) > 0:
        accuracy = 0.0
    else:
        matches = sum(1 for a, b in zip(agent_text, golden_text) if a == b)
        max_len = max(len(agent_text), len(golden_text))
        accuracy = matches / max_len if max_len > 0 else 1.0

    assert accuracy >= 0.99, f"Accuracy {accuracy:.4f} is below threshold 0.99"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
