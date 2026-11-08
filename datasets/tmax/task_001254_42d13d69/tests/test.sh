#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import random
import re
import secrets
import stat
import subprocess
import tempfile
import time
import urllib.request

import pytest

SANITIZER = "/home/user/sanitizer.sh"


def sanitizer_env(tmpdir):
    bindir = os.path.join(tmpdir, "forbidden-bin")
    os.makedirs(bindir, exist_ok=True)
    marker = os.path.join(tmpdir, "forbidden-used")
    wrapper = '#!/bin/sh\necho "$0" >> "$SANITIZER_FORBIDDEN_MARKER"\nexit 126\n'
    for name in ("python", "python2", "python3", "pypy", "pypy3", "R", "Rscript"):
        path = os.path.join(bindir, name)
        with open(path, "w", encoding="utf-8") as f:
            f.write(wrapper)
        os.chmod(path, 0o755)
    env = os.environ.copy()
    env["PATH"] = bindir + os.pathsep + env.get("PATH", "")
    env["SANITIZER_FORBIDDEN_MARKER"] = marker
    return env, marker


def run_sanitizer(args, env):
    return subprocess.run(
        ["bash", SANITIZER, *args],
        capture_output=True,
        text=True,
        timeout=5,
        env=env,
    )


def test_sanitizer_adversarial_corpus_and_behavior():
    assert os.path.isfile(SANITIZER), f"Sanitizer script not found at {SANITIZER}"
    assert stat.S_ISREG(os.stat(SANITIZER).st_mode), "Sanitizer must be a regular file"
    assert os.access(SANITIZER, os.X_OK), f"Sanitizer script at {SANITIZER} is not executable"

    with open(SANITIZER, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()

    # Reject direct Python/R execution, including absolute paths and common shell prefixes.
    active_source = "\n".join(
        line for line in source.splitlines() if not line.lstrip().startswith("#")
    )
    forbidden_command = re.compile(
        r"(?m)(?:^|[;|&()\n])\s*"
        r"(?:(?:if|then|elif|while|until|do|command|exec|builtin|!)\s+)*"
        r"(?:(?:\S*/)?env(?:\s+-\S+)*\s+)?"
        r"(?:\S*/)?(?:python(?:[0-9.]+)?|pypy(?:[0-9.]+)?|Rscript|R)"
        r"(?=\s|$|[;|&()])"
    )
    assert not forbidden_command.search(active_source), "sanitizer.sh must not invoke Python or R"

    clean_dir = "/home/user/data/clean"
    evil_dir = "/home/user/data/evil"
    clean_files = sorted(
        os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith(".csv")
    )
    evil_files = sorted(
        os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith(".csv")
    )
    assert clean_files, "No clean CSV files found."
    assert evil_files, "No evil CSV files found."

    with tempfile.TemporaryDirectory(prefix="sanitizer-verifier-") as td:
        env, forbidden_marker = sanitizer_env(td)

        clean_failed = []
        for path in clean_files:
            if run_sanitizer([path], env).returncode != 0:
                clean_failed.append(os.path.basename(path))

        evil_failed = []
        for path in evil_files:
            if run_sanitizer([path], env).returncode == 0:
                evil_failed.append(os.path.basename(path))

        errors = []
        if evil_failed:
            errors.append(
                f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}"
            )
        if clean_failed:
            errors.append(
                f"{len(clean_failed)} of {len(clean_files)} clean rejected: {', '.join(clean_failed)}"
            )
        assert not errors, " | ".join(errors)

        # A single argument is required.
        assert run_sanitizer([], env).returncode != 0, "Sanitizer accepted zero arguments"
        assert run_sanitizer([clean_files[0], clean_files[1]], env).returncode != 0, \
            "Sanitizer accepted more than one argument"

        # Generate files at unpredictable paths so behavior cannot be based on clean/evil paths.
        rng = random.SystemRandom()
        valid_cases = []
        for _ in range(8):
            rows = []
            for row_id in range(rng.randint(1, 5)):
                value = str(secrets.randbelow(2_000_001) - 1_000_000)
                rows.append(f"text-{row_id},12.5,NaN,{value}")
            valid_cases.append((True, rows))

        invalid_tokens = [
            "", "12.0", "-3.0", "NaN", "null", "NULL", "abc",
            "12x", " 12", "12 ", "+7", "--3"
        ]
        invalid_cases = []
        for token in invalid_tokens:
            rows = [
                f"1,a,b,{secrets.randbelow(100000)}",
                f"2,c,d,{token}",
                f"3,e,f,-{secrets.randbelow(100000) + 1}",
            ]
            invalid_cases.append((False, rows))

        cases = valid_cases + invalid_cases
        rng.shuffle(cases)
        for should_accept, rows in cases:
            path = os.path.join(td, secrets.token_hex(12) + ".csv")
            with open(path, "w", encoding="utf-8", newline="") as f:
                f.write("id,val1,val2,experiment_id\n")
                f.write("\n".join(rows) + "\n")
            result = run_sanitizer([path], env)
            expected = 0 if should_accept else 1
            assert result.returncode == expected, (
                f"Generated {'valid' if should_accept else 'invalid'} CSV returned "
                f"{result.returncode}; stdout={result.stdout!r}, stderr={result.stderr!r}"
            )

        assert not os.path.exists(forbidden_marker), "sanitizer.sh attempted to invoke Python or R"


def test_verification_log():
    log_path = "/home/user/verification.log"
    assert os.path.isfile(log_path), f"Verification log not found at {log_path}"
    with open(log_path, "r", encoding="utf-8", errors="strict") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = []
    for directory, result in (("/home/user/data/clean", "ACCEPT"),
                              ("/home/user/data/evil", "REJECT")):
        for name in sorted(os.listdir(directory)):
            if os.path.isfile(os.path.join(directory, name)):
                expected.append((name, result))

    parsed = []
    pattern = re.compile(r"^\[?([^\[\]]+?)\]?:\s*\[?(ACCEPT|REJECT)\]?$")
    for line in lines:
        match = pattern.fullmatch(line)
        assert match, f"Malformed verification log line: {line!r}"
        parsed.append((match.group(1), match.group(2)))

    assert collections.Counter(parsed) == collections.Counter(expected), (
        f"verification.log must contain exactly one correct result for every corpus file; "
        f"expected {expected!r}, got {parsed!r}"
    )


def test_multi_service_pipeline():
    start_script = "/home/user/app/start_services.sh"
    if os.path.exists(start_script):
        subprocess.run(["bash", start_script], check=False)
        time.sleep(3)

    csv_data = b"col1,col2,col3,experiment_id\n1,2,3,42\n"
    req = urllib.request.Request(
        "http://localhost:8080/api/upload", data=csv_data, method="POST"
    )
    req.add_header("Content-Type", "text/csv")

    try:
        response = urllib.request.urlopen(req, timeout=5)
        assert response.status in (200, 201), (
            f"Expected successful HTTP status, got {response.status}"
        )
    except Exception as e:
        pytest.fail(
            f"End-to-end flow failed at Nginx/Flask layer: {e}. "
            "Check if Nginx routes /api/ to Flask."
        )

    try:
        res = subprocess.run(
            ["redis-cli", "get", "uploads_count"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        assert res.returncode == 0, "Failed to execute redis-cli"
        count_str = res.stdout.strip()
        assert count_str and count_str.isdigit(), (
            f"Expected an integer in Redis for 'uploads_count', got: {count_str!r}"
        )
        assert int(count_str) > 0, (
            "Redis uploads_count was not incremented, meaning the Flask app didn't "
            "process the upload correctly."
        )
    except Exception as e:
        pytest.fail(f"End-to-end flow failed at Redis layer: {e}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
