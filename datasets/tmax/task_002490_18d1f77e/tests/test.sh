#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import re
import secrets
import string
import subprocess
import tempfile

SANITIZER = "/home/user/sanitizer.py"
RULE_OUTPUT = "EVIL: 99B-4X2\n"


def run_sanitizer(*args):
    return subprocess.run(
        ["python3", SANITIZER, *args],
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_sanitizer_exists():
    path = "/home/user/sanitizer.py"
    assert os.path.isfile(path), f"sanitizer.py not found at {path}"


def test_clean_corpus():
    clean_logs_dir = "/app/clean_logs"
    clean_logs = glob.glob(os.path.join(clean_logs_dir, "*"))
    assert len(clean_logs) > 0, f"No clean logs found in {clean_logs_dir}"

    failed_files = []
    for log_file in clean_logs:
        result = subprocess.run(
            ["python3", "/home/user/sanitizer.py", log_file],
            capture_output=True,
            text=True
        )
        if result.returncode != 0:
            failed_files.append(os.path.basename(log_file))

    assert not failed_files, f"{len(failed_files)} of {len(clean_logs)} clean logs modified/rejected: {', '.join(failed_files)}"


def test_evil_corpus():
    evil_logs_dir = "/app/evil_logs"
    evil_logs = glob.glob(os.path.join(evil_logs_dir, "*"))
    assert len(evil_logs) > 0, f"No evil logs found in {evil_logs_dir}"

    bypassed_files = []
    for log_file in evil_logs:
        result = subprocess.run(
            ["python3", "/home/user/sanitizer.py", log_file],
            capture_output=True,
            text=True
        )
        if result.returncode != 1 or "EVIL: 99B-4X2" not in result.stdout:
            bypassed_files.append(os.path.basename(log_file))

    assert not bypassed_files, f"{len(bypassed_files)} of {len(evil_logs)} evil logs bypassed: {', '.join(bypassed_files)}"


def test_original_evil_output_is_exact():
    for log_file in glob.glob("/app/evil_logs/*"):
        result = run_sanitizer(log_file)
        assert result.returncode == 1
        assert result.stdout == RULE_OUTPUT


def expected_malicious(log):
    return (
        "../" in log
        or re.search(r"UNION SELECT", log, re.IGNORECASE) is not None
        or "&byp=true" in log
    )


def random_text(length=32):
    alphabet = string.ascii_letters + string.digits + " _-?=/.:"
    while True:
        value = "".join(secrets.choice(alphabet) for _ in range(length))
        if not expected_malicious(value):
            return value


def randomized_case(value):
    return "".join(ch.upper() if secrets.randbits(1) else ch.lower() for ch in value)


def test_novel_logs_are_classified_by_contents_with_exact_output():
    clean_near_misses = [
        "GET /safe/.. /file HTTP/1.1",
        "GET /safe/..\\secret HTTP/1.1",
        "POST query=UNION  SELECT value",
        "POST query=UNION\tSELECT value",
        "GET /admin?x=1&BYP=true HTTP/1.1",
        "GET /admin?x=1&byp=false HTTP/1.1",
    ]
    cases = list(clean_near_misses)

    for _ in range(54):
        prefix = random_text(secrets.randbelow(35) + 5)
        suffix = random_text(secrets.randbelow(35) + 5)
        choice = secrets.randbelow(4)
        if choice == 0:
            content = prefix + suffix
        elif choice == 1:
            content = prefix + "../" + suffix
        elif choice == 2:
            content = prefix + randomized_case("UNION SELECT") + suffix
        else:
            content = prefix + "&byp=true" + suffix
        cases.append(content)

    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="sanitizer-check-") as directory:
        # Reuse one unpredictable path for both clean and malicious contents so
        # classification cannot be based on the path or filename.
        log_path = os.path.join(directory, secrets.token_hex(12) + ".log")
        for content in cases:
            with open(log_path, "w", encoding="utf-8") as handle:
                handle.write(content)

            result = run_sanitizer(log_path)
            if expected_malicious(content):
                assert result.returncode == 1, repr(content)
                assert result.stdout == RULE_OUTPUT, repr(content)
            else:
                assert result.returncode == 0, repr(content)


def test_requires_exactly_one_argument():
    no_args = run_sanitizer()
    assert no_args.returncode != 0

    with tempfile.TemporaryDirectory(prefix="sanitizer-args-") as directory:
        first = os.path.join(directory, "first.log")
        second = os.path.join(directory, "second.log")
        for path in (first, second):
            with open(path, "w", encoding="utf-8") as handle:
                handle.write("ordinary benign request")
        too_many = run_sanitizer(first, second)
        assert too_many.returncode != 0
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
