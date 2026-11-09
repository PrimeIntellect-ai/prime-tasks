#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sys
import string
import hashlib
import stat
import re
import subprocess
import pytest

@pytest.fixture(scope="session", autouse=True)
def execute_remediation_script():
    """Validate and execute the requested Bash remediation automation."""
    script_path = "/home/user/remediate.sh"
    assert os.path.exists(script_path), f"Remediation script not found at {script_path}."
    assert stat.S_ISREG(os.lstat(script_path).st_mode), f"{script_path} must be a regular file."

    syntax = subprocess.run(
        ["/bin/bash", "-n", script_path],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert syntax.returncode == 0, f"Invalid Bash script: {syntax.stderr}"

    transcript_path = "/home/user/transcript.txt"
    assert os.path.isfile(transcript_path), f"Transcript file not found at {transcript_path}."

    # Remove generated artifacts and relax the transcript permissions so the
    # script must recreate the outputs and enforce all required permissions.
    for path in (
        "/home/user/firewall_rule.txt",
        "/home/user/csp.txt",
        "/home/user/transcript_hash.txt",
    ):
        if os.path.lexists(path):
            assert not os.path.isdir(path), f"Expected a file, but found a directory at {path}."
            os.unlink(path)
    os.chmod(transcript_path, 0o644)

    execution = subprocess.run(
        ["/bin/bash", script_path],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert execution.returncode == 0, (
        f"Remediation script failed with exit code {execution.returncode}. "
        f"stdout: {execution.stdout!r} stderr: {execution.stderr!r}"
    )

def calculate_wer(reference, hypothesis):
    ref_words = reference.split()
    hyp_words = hypothesis.split()

    d = [[0] * (len(hyp_words) + 1) for _ in range(len(ref_words) + 1)]

    for i in range(len(ref_words) + 1):
        d[i][0] = i
    for j in range(len(hyp_words) + 1):
        d[0][j] = j

    for i in range(1, len(ref_words) + 1):
        for j in range(1, len(hyp_words) + 1):
            if ref_words[i - 1] == hyp_words[j - 1]:
                cost = 0
            else:
                cost = 1
            d[i][j] = min(d[i - 1][j] + 1,      # deletion
                          d[i][j - 1] + 1,      # insertion
                          d[i - 1][j - 1] + cost) # substitution

    if len(ref_words) == 0:
        return float('inf')
    return d[len(ref_words)][len(hyp_words)] / float(len(ref_words))

def test_transcript_wer():
    """Check that the transcript exists and meets the Word Error Rate threshold."""
    transcript_path = "/home/user/transcript.txt"
    assert os.path.exists(transcript_path), f"Transcript file not found at {transcript_path}."

    with open(transcript_path, "r") as f:
        hypothesis = f.read().strip().lower()

    # Remove basic punctuation just in case
    hypothesis = hypothesis.translate(str.maketrans('', '', string.punctuation))

    reference = "the payload was delivered via open redirect on our login page the target domain was secure dash update dot net and the exfiltration ip is one nine two dot one six eight dot one five dot seven"

    wer = calculate_wer(reference, hypothesis)
    threshold = 0.20

    assert wer <= threshold, f"Transcript WER is {wer:.4f}, which is above the threshold of {threshold}. Hypothesis text: '{hypothesis}'"

def test_firewall_rule():
    """Check that the firewall rule matches the exact expected string with the extracted IP."""
    rule_path = "/home/user/firewall_rule.txt"
    assert os.path.exists(rule_path), f"Firewall rule file not found at {rule_path}."

    with open(rule_path, "r") as f:
        content = f.read().strip()

    # Normalize spaces for robust comparison
    normalized_content = " ".join(content.split())
    expected_rule = "iptables -A OUTPUT -d 192.168.15.7 -j DROP"

    assert normalized_content == expected_rule, f"Expected firewall rule '{expected_rule}', but got '{normalized_content}'."

def test_csp_rule():
    """Check that the CSP header matches the exact expected string."""
    csp_path = "/home/user/csp.txt"
    assert os.path.exists(csp_path), f"CSP file not found at {csp_path}."

    with open(csp_path, "r") as f:
        content = f.read().strip()

    expected_csp = "Content-Security-Policy: default-src 'self'; form-action 'self';"
    assert content == expected_csp, f"Expected CSP '{expected_csp}', but got '{content}'."

def test_transcript_hash():
    """Check that the transcript hash matches the transcript in sha256sum format."""
    transcript_path = "/home/user/transcript.txt"
    hash_path = "/home/user/transcript_hash.txt"

    assert os.path.exists(transcript_path), f"Transcript file not found at {transcript_path}."
    assert os.path.exists(hash_path), f"Hash file not found at {hash_path}."

    with open(transcript_path, 'rb') as f:
        expected_hash = hashlib.sha256(f.read()).hexdigest()

    with open(hash_path, 'r') as f:
        content = f.read()

    assert expected_hash in content, f"Expected hash '{expected_hash}' not found in {hash_path}. Content was: '{content}'"

    match = re.fullmatch(
        r"([0-9a-f]{64}) ([ *])(/home/user/transcript\.txt|transcript\.txt)\n?",
        content,
    )
    assert match is not None, f"Hash file is not in standard sha256sum format: {content!r}"
    assert match.group(1) == expected_hash, f"Expected hash '{expected_hash}', but got '{match.group(1)}'."

def test_file_permissions():
    """Check that all generated files have strict 600 permissions."""
    files = [
        '/home/user/transcript.txt',
        '/home/user/firewall_rule.txt',
        '/home/user/csp.txt',
        '/home/user/transcript_hash.txt'
    ]

    for f_path in files:
        assert os.path.exists(f_path), f"File {f_path} does not exist, cannot check permissions."
        st = os.stat(f_path)
        perms = stat.S_IMODE(st.st_mode)
        assert perms == 0o600, f"File {f_path} has permissions {oct(perms)}, expected 0o600."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
