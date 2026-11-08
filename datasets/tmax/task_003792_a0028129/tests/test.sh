#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import string


def test_part1_make_test_passes():
    """Check that the vendored package is fixed and its Makefile runs the tests."""
    work_dir = "/app/auth-redirect-v1.0.0"
    assert os.path.isdir(work_dir), f"Directory {work_dir} is missing."

    result = subprocess.run(
        ["make", "test"],
        cwd=work_dir,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    assert result.returncode == 0, f"'make test' failed in {work_dir}.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"

    # Independently verify auth.py so a no-op Makefile cannot hide the bug.
    direct_check = subprocess.run(
        [
            "python3", "-c",
            "from auth import extract_host; "
            "assert extract_host('https://example.com/path') == 'example.com'; "
            "assert extract_host('https://example.com:8080/path') == 'example.com'"
        ],
        cwd=work_dir,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    assert direct_check.returncode == 0, (
        f"auth.py still has incorrect host extraction.\n"
        f"STDOUT:\n{direct_check.stdout}\nSTDERR:\n{direct_check.stderr}"
    )

    # Confirm that `make test` really executes test_auth.py rather than merely
    # returning success.
    test_file = os.path.join(work_dir, "test_auth.py")
    with open(test_file, "rb") as f:
        original_tests = f.read()
    try:
        with open(test_file, "ab") as f:
            f.write(b"\n\ndef test_verifier_sentinel_failure():\n    assert False\n")
        sentinel_result = subprocess.run(
            ["make", "test"],
            cwd=work_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
    finally:
        with open(test_file, "wb") as f:
            f.write(original_tests)

    assert sentinel_result.returncode != 0, (
        "'make test' returned success even when test_auth.py contained a failing test; "
        "the Makefile does not actually run the test suite."
    )


def generate_fuzz_inputs(n=1000):
    random.seed(42)
    base_domains = ["example.com", "corp.internal", "app.co.uk"]

    schemes = ["https://", "http://", "javascript:", "ftp://", "", "//", "https:/", "https:"]
    subdomains = ["", "app.", "sub.sub.", "not", "evil-"]
    paths = [
        "", "/", "/dashboard", "/login?next=/home",
        "/../etc/passwd", "/%2e%2e/admin", "/%2E%2E/secret",
        "/valid/path/here", "relative", "/api/v1/data"
    ]

    inputs = []
    for _ in range(n):
        base_domain = random.choice(base_domains)
        scheme = random.choice(schemes)
        sub = random.choice(subdomains)
        domain_choice = random.choice([base_domain, "evil.com", base_domain + ".evil.com", "other.com"])
        if sub == "not":
            domain = "not" + base_domain
        else:
            domain = sub + domain_choice

        path = random.choice(paths)
        port = random.choice(["", ":80", ":443", ":8080", ":evil"])

        if scheme in ["https://", "http://", "ftp://", "//"]:
            url = f"{scheme}{domain}{port}{path}"
        else:
            url = f"{scheme}{path}"

        if random.random() < 0.2:
            url = path
        if random.random() < 0.05:
            url = "".join(random.choices(string.printable, k=random.randint(5, 20)))

        inputs.append((base_domain, url))

    return inputs


def test_part2_validate_redirect_fuzzing():
    agent_script = "/home/user/validate_redirect"
    oracle_script = "/tests/validate_redirect_oracle.py"

    assert os.path.isfile(agent_script), f"Agent script missing: {agent_script}"
    assert os.access(agent_script, os.X_OK), f"Agent script is not executable: {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script missing: {oracle_script}"

    inputs = generate_fuzz_inputs(1000)

    for base_domain, url in inputs:
        oracle_res = subprocess.run(
            ["python3", oracle_script, base_domain, url],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        oracle_out = oracle_res.stdout.strip()

        agent_res = subprocess.run(
            [agent_script, base_domain, url],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        agent_out = agent_res.stdout.strip()

        assert agent_out == oracle_out, (
            f"Mismatch on input!\n"
            f"Base domain: {base_domain}\n"
            f"URL: {url}\n"
            f"Expected (Oracle): {oracle_out}\n"
            f"Got (Agent): {agent_out}\n"
            f"Agent STDERR: {agent_res.stderr}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
