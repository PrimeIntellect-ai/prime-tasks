#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import string
import subprocess
import tempfile
import urllib.parse
import pytest

SCRIPT_PATH = "/home/user/build_orchestrator.py"
CLEAN_DIR = "/app/corpus/clean"
EVIL_DIR = "/app/corpus/evil"
IMAGE_PATH = "/app/build_architecture.png"


def parse_url(url_str):
    # build://{action}?token={BUILD_TOKEN}&target={target_name}&flags={compiler_flags}
    if not url_str.startswith("build://"):
        return None, None, None
    url_str = url_str[8:]
    if "?" not in url_str:
        return None, None, None
    action, query = url_str.split("?", 1)
    params = urllib.parse.parse_qs(query, keep_blank_values=True)
    target = params.get("target", [""])[0]
    flags = params.get("flags", [""])[0]
    return action, target, flags


def run_script(filepath):
    return subprocess.run(
        ["python3", SCRIPT_PATH, "--verify", filepath],
        capture_output=True,
        text=True,
        timeout=5
    ).stdout.strip()


def extract_token():
    result = subprocess.run(
        ["tesseract", IMAGE_PATH, "stdout", "--psm", "7"],
        capture_output=True,
        text=True,
        timeout=10,
        check=True
    )
    match = re.search(r"BUILD_TOKEN\s*=\s*([A-Za-z0-9]+)", result.stdout)
    assert match, f"Could not extract BUILD_TOKEN from architecture image: {result.stdout!r}"
    return match.group(1)


def test_build_orchestrator_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"


def test_clean_corpus():
    assert os.path.isdir(CLEAN_DIR), f"Clean corpus missing at {CLEAN_DIR}"
    clean_files = [f for f in os.listdir(CLEAN_DIR) if f.endswith(".txt")]
    assert len(clean_files) > 0, "No clean corpus files found"

    failed_files = []

    for filename in clean_files:
        filepath = os.path.join(CLEAN_DIR, filename)
        with open(filepath, "r") as f:
            url_str = f.read().strip()

        action, target, flags = parse_url(url_str)
        expected_output = f"ACCEPT: [{action}] built {target} with {flags}"

        try:
            result = subprocess.run(
                ["python3", SCRIPT_PATH, "--verify", filepath],
                capture_output=True,
                text=True,
                timeout=5
            )
            stdout = result.stdout.strip()
            if stdout != expected_output:
                failed_files.append((filename, stdout, expected_output))
        except Exception as e:
            failed_files.append((filename, str(e), expected_output))

    if failed_files:
        error_msg = f"{len(failed_files)} of {len(clean_files)} clean modified/rejected.\n"
        for f, out, exp in failed_files:
            error_msg += f"File: {f} | Expected: '{exp}' | Got: '{out}'\n"
        pytest.fail(error_msg)


def test_evil_corpus():
    assert os.path.isdir(EVIL_DIR), f"Evil corpus missing at {EVIL_DIR}"
    evil_files = [f for f in os.listdir(EVIL_DIR) if f.endswith(".txt")]
    assert len(evil_files) > 0, "No evil corpus files found"

    failed_files = []

    for filename in evil_files:
        filepath = os.path.join(EVIL_DIR, filename)

        try:
            result = subprocess.run(
                ["python3", SCRIPT_PATH, "--verify", filepath],
                capture_output=True,
                text=True,
                timeout=5
            )
            stdout = result.stdout.strip()
            if stdout != "REJECT":
                failed_files.append((filename, stdout))
        except Exception as e:
            failed_files.append((filename, str(e)))

    if failed_files:
        error_msg = f"{len(failed_files)} of {len(evil_files)} evil bypassed.\n"
        for f, out in failed_files:
            error_msg += f"File: {f} | Got: '{out}' instead of 'REJECT'\n"
        pytest.fail(error_msg)


def test_randomized_unseen_dsl_cases():
    token = extract_token()
    alphabet = string.ascii_letters + string.digits

    def rand_text(length=10):
        return ''.join(secrets.choice(alphabet) for _ in range(length))

    cases = []

    # Unseen valid commands exercise every allowed action and randomized values.
    for action in ("compile_c", "compile_py", "link_bin"):
        for _ in range(3):
            target = f"{rand_text(8)}_{rand_text(5)}"
            flags = f"-{rand_text(3)} --{rand_text(7)} {rand_text(4)}"
            url = f"build://{action}?token={token}&target={target}&flags={flags}"
            cases.append((url, f"ACCEPT: [{action}] built {target} with {flags}"))

    action = secrets.choice(("compile_c", "compile_py", "link_bin"))
    target = rand_text()
    base = f"build://{action}?token={token}&target={target}&flags=-O2"

    # Authentication, routing, required parameters, and URL structure.
    cases.extend([
        (f"build://{action}?token={rand_text()}&target={target}&flags=-O2", "REJECT"),
        (f"build://{action}?token={token.lower()}X&target={target}&flags=-O2", "REJECT"),
        (f"build://{rand_text()}?token={token}&target={target}&flags=-O2", "REJECT"),
        (f"http://{action}?token={token}&target={target}&flags=-O2", "REJECT"),
        (f"build://{action}", "REJECT"),
        (f"build://{action}?target={target}&flags=-O2", "REJECT"),
        (f"build://{action}?token={token}&flags=-O2", "REJECT"),
        (f"build://{action}?token={token}&target={target}", "REJECT"),
        (f"build://{action}?token=&target={target}&flags=-O2", "REJECT"),
        (f"build://{action}?token={token}&target=&flags=-O2", "REJECT"),
        (f"build://{action}?token={token}&target={target}&flags=", "REJECT"),
    ])

    # Every forbidden target class is tested at an unpredictable position.
    for bad in ("/", ".", "-", " ", ";", "$", "|", "`", ">", "<"):
        left, right = rand_text(4), rand_text(4)
        cases.append((
            f"build://{action}?token={token}&target={left}{bad}{right}&flags=-O2",
            "REJECT"
        ))

    # Flags may contain only alphanumerics, hyphens, and spaces.
    for bad in (";", "&", "|", "$", ">", "<", "`", "_", "/", "."):
        cases.append((
            f"build://{action}?token={token}&target={target}&flags=-O2 {bad}{rand_text(5)}",
            "REJECT"
        ))

    # Percent-encoded forbidden characters must not bypass validation after parsing.
    cases.extend([
        (f"build://{action}?token={token}&target={target}%2Fetc&flags=-O2", "REJECT"),
        (f"build://{action}?token={token}&target={target}&flags=-O2%20%3Brm", "REJECT"),
        (base + "%20%24PATH", "REJECT"),
    ])

    random.SystemRandom().shuffle(cases)
    failures = []
    with tempfile.TemporaryDirectory(prefix=f"dsl_{secrets.token_hex(8)}_") as case_dir:
        for url, expected in cases:
            filepath = os.path.join(case_dir, secrets.token_hex(12) + ".txt")
            with open(filepath, "w", encoding="utf-8") as f:
                f.write(url + "\n")
            try:
                actual = run_script(filepath)
            except Exception as exc:
                actual = f"EXCEPTION: {exc}"
            if actual != expected:
                failures.append((url, expected, actual))

    if failures:
        details = "\n".join(
            f"URL: {url!r} | Expected: {expected!r} | Got: {actual!r}"
            for url, expected, actual in failures
        )
        pytest.fail(f"{len(failures)} randomized DSL cases failed:\n{details}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
