#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import string
import subprocess
import tempfile


def test_attacker_ip():
    """Test that the attacker's IP was correctly extracted."""
    path = "/home/user/attacker_ip.txt"
    assert os.path.isfile(path), f"File missing: {path}"
    with open(path, "r") as f:
        ip = f.read().strip()
    assert ip == "198.51.100.42", f"Incorrect attacker IP. Expected 198.51.100.42, got {ip}"


def test_sshd_config_fixed():
    """Test that the SSH configuration was properly hardened."""
    path = "/home/user/sshd_config_fixed"
    assert os.path.isfile(path), f"File missing: {path}"
    with open(path, "r") as f:
        content = f.read()

    assert re.search(r"^\s*PermitRootLogin\s+no\s*$", content, re.MULTILINE), "Missing or incorrect PermitRootLogin directive"
    assert re.search(r"^\s*PasswordAuthentication\s+no\s*$", content, re.MULTILINE), "Missing or incorrect PasswordAuthentication directive"
    assert re.search(r"^\s*X11Forwarding\s+no\s*$", content, re.MULTILINE), "Missing or incorrect X11Forwarding directive"
    assert re.search(r"^\s*Protocol\s+2\s*$", content, re.MULTILINE), "Missing or incorrect Protocol directive"

    required = {
        "permitrootlogin": "no",
        "passwordauthentication": "no",
        "x11forwarding": "no",
        "protocol": "2",
    }
    for lineno, raw_line in enumerate(content.splitlines(), 1):
        active = raw_line.split("#", 1)[0].strip()
        if not active:
            continue
        fields = active.split()
        key = fields[0].lower()
        if key in required:
            assert len(fields) == 2 and fields[1].lower() == required[key], (
                f"Contradictory or malformed active directive on line {lineno}: {raw_line!r}"
            )


def test_redact_pii_script():
    """Test the redaction script against a randomized, independently derived dataset."""
    script_path = "/home/user/redact_pii.sh"
    assert os.path.isfile(script_path), f"Script missing: {script_path}"

    rng = secrets.SystemRandom()

    def digits(n):
        return "".join(rng.choice(string.digits) for _ in range(n))

    def letters(n):
        return "".join(rng.choice(string.ascii_letters) for _ in range(n))

    def pii():
        kind = rng.randrange(3)
        if kind == 0:
            return f"{digits(3)}-{digits(2)}-{digits(4)}"
        if kind == 1:
            return "-".join(digits(4) for _ in range(4))
        return digits(16)

    def near_miss():
        kind = rng.randrange(8)
        if kind == 0:
            return digits(17)
        if kind == 1:
            return digits(15)
        if kind == 2:
            return f"{digits(3)}-{digits(3)}-{digits(4)}"
        if kind == 3:
            return "-".join([digits(4), digits(4), digits(4), digits(3)])
        if kind == 4:
            return "A" + f"{digits(3)}-{digits(2)}-{digits(4)}"
        if kind == 5:
            return digits(16) + "Z"
        if kind == 6:
            return "_" + "-".join(digits(4) for _ in range(4)) + "_"
        return f"{digits(4)}-{digits(2)}-{digits(2)}T{digits(2)}:{digits(2)}:{digits(2)}"

    pattern = re.compile(r"\b(?:\d{3}-\d{2}-\d{4}|\d{4}(?:-\d{4}){3}|\d{16})\b")
    separators = [" | ", ", ", "; ", " / ", " and "]
    input_lines = []
    expected_lines = []

    for _ in range(5000):
        mode = rng.randrange(7)
        if mode == 0:
            fragments = ["SSN=" + pii()]
        elif mode == 1:
            fragments = ["primary=" + pii(), "secondary=" + pii()]
        elif mode == 2:
            fragments = [pii(), near_miss(), pii()]
        elif mode == 3:
            fragments = ["identifier=" + near_miss()]
        elif mode == 4:
            fragments = ["message=" + letters(rng.randrange(8, 30))]
        elif mode == 5:
            fragments = [near_miss(), near_miss()]
        else:
            fragments = ["account=" + letters(6), pii(), "code=" + near_miss(), pii()]

        separator = rng.choice(separators)
        line = f"event={letters(14)} " + separator.join(fragments) + f" status={letters(9)}"
        input_lines.append(line + "\n")
        expected_lines.append(pattern.sub("[REDACTED]", line) + "\n")

    with tempfile.TemporaryDirectory(prefix="redaction-test-") as temp_dir:
        input_file = os.path.join(temp_dir, "input.txt")
        agent_output_file = os.path.join(temp_dir, "output.txt")
        with open(input_file, "w") as f_in:
            f_in.writelines(input_lines)

        result = subprocess.run(
            ["bash", script_path, input_file, agent_output_file],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, f"Script failed with error: {result.stderr}"
        assert os.path.isfile(agent_output_file), "Agent script did not produce the output file."

        with open(agent_output_file, "r") as f_agent:
            agent_lines = f_agent.readlines()

    total_lines = len(expected_lines)
    assert len(agent_lines) == total_lines, (
        f"Agent output has incorrect number of lines: {len(agent_lines)} instead of {total_lines}"
    )

    correct_lines = sum(1 for actual, expected in zip(agent_lines, expected_lines) if actual == expected)
    accuracy = correct_lines / total_lines
    assert accuracy >= 0.98, (
        f"Accuracy {accuracy:.4f} is below threshold 0.98. "
        f"Correct lines: {correct_lines}/{total_lines}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
