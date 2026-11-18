#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import string
import subprocess
import sys
import urllib.parse


def run_detector(script_path, payload):
    try:
        result = subprocess.run(
            [sys.executable, script_path, payload],
            capture_output=True,
            text=True,
            timeout=3,
        )
        return result.returncode, result.stdout.strip()
    except subprocess.TimeoutExpired:
        return "TIMEOUT", ""


def test_detector_script():
    script_path = "/home/user/detector.py"
    assert os.path.isfile(script_path), f"Detector script not found at {script_path}"

    evil_corpus_path = "/app/corpus/evil.txt"
    clean_corpus_path = "/app/corpus/clean.txt"

    assert os.path.isfile(evil_corpus_path), f"Missing evil corpus at {evil_corpus_path}"
    assert os.path.isfile(clean_corpus_path), f"Missing clean corpus at {clean_corpus_path}"

    with open(evil_corpus_path, "r", encoding="utf-8") as f:
        evil_payloads = f.read().splitlines()

    with open(clean_corpus_path, "r", encoding="utf-8") as f:
        clean_payloads = f.read().splitlines()

    evil_failures = []
    for payload in evil_payloads:
        rc, stdout = run_detector(script_path, payload)
        if rc != 1 or stdout != "REJECTED_OVERLORD":
            evil_failures.append((payload, rc, stdout))

    clean_failures = []
    for payload in clean_payloads:
        rc, stdout = run_detector(script_path, payload)
        if rc != 0 or stdout != "SAFE":
            clean_failures.append((payload, rc, stdout))

    # Generate fresh cases after the agent has finished. Every safe value is a
    # simple basename, while every evil value contains an independently derived
    # absolute path, directory component, traversal, null encoding, or encoded
    # Unicode traversal sequence.
    alphabet = string.ascii_letters + string.digits
    clean_dynamic = []
    for i in range(80):
        token = "".join(secrets.choice(alphabet) for _ in range(18))
        forms = (
            f"file_{token}.txt",
            f"report-{token}.pdf",
            f"IMG_{token}.PNG",
            f"archive_{token}.tar.gz",
            f"a{i}_{token}.dat",
        )
        clean_dynamic.append(forms[i % len(forms)])

    evil_dynamic = []
    bs = chr(92)
    for _ in range(4):
        token = "".join(secrets.choice(alphabet) for _ in range(16)) + ".txt"
        unicode_traversals = (
            "．．／" + token,
            "․․∕" + token,
            "․․⁄" + token,
            "．．＼" + token,
        )
        evil_dynamic.extend([
            "/tmp/" + token,
            "/etc/../tmp/" + token,
            "../" + token,
            "../../private/" + token,
            "safe/../" + token,
            "directory/" + token,
            ".." + bs + token,
            ".." + bs + ".." + bs + token,
            "folder" + bs + token,
            "C:" + bs + "Windows" + bs + token,
            bs + bs + "server" + bs + "share" + bs + token,
            "%2e%2e%2f" + token,
            "%2E%2E%2F" + token,
            ".%2e%2f" + token,
            "%2e.%5c" + token,
            "%252e%252e%252f" + token,
            "..%252f" + token,
            "%252e%252e%255c" + token,
            "..%c0%af" + token,
            "%00" + token,
            token + "%00.jpg",
            urllib.parse.quote(unicode_traversals[0], safe=""),
            urllib.parse.quote(unicode_traversals[1], safe=""),
            urllib.parse.quote(unicode_traversals[2], safe=""),
            *unicode_traversals,
        ])

    for payload in evil_dynamic:
        rc, stdout = run_detector(script_path, payload)
        if rc != 1 or stdout != "REJECTED_OVERLORD":
            evil_failures.append((payload, rc, stdout))

    for payload in clean_dynamic:
        rc, stdout = run_detector(script_path, payload)
        if rc != 0 or stdout != "SAFE":
            clean_failures.append((payload, rc, stdout))

    errors = []
    total_evil = len(evil_payloads) + len(evil_dynamic)
    total_clean = len(clean_payloads) + len(clean_dynamic)
    if evil_failures:
        errors.append(f"{len(evil_failures)} of {total_evil} evil payloads bypassed.")
        for payload, rc, out in evil_failures[:5]:
            errors.append(f"  Evil payload bypassed: {payload!r} -> exit {rc}, stdout {out!r}")

    if clean_failures:
        errors.append(f"{len(clean_failures)} of {total_clean} clean payloads rejected/modified.")
        for payload, rc, out in clean_failures[:5]:
            errors.append(f"  Clean payload rejected: {payload!r} -> exit {rc}, stdout {out!r}")

    assert not errors, "\n".join(errors)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
