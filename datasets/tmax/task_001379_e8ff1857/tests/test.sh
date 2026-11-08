#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import secrets
import shlex
import subprocess
import tempfile

import pytest

SCRIPT_PATH = "/home/user/redirect_detector.sh"
PACKAGE_DIR = "/app/vendored-sso-auth-1.2.0"
BINARY_PATH = os.path.join(PACKAGE_DIR, "sso-decrypt")


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_sso_decrypt_binary_exists():
    assert os.path.isfile(BINARY_PATH), f"Binary {BINARY_PATH} does not exist. Did you run 'make'?"
    assert os.access(BINARY_PATH, os.X_OK), f"Binary {BINARY_PATH} is not executable."


def test_makefile_inherits_ld_flags_and_builds_binary():
    marker = f"/tmp/sso-link-{secrets.token_hex(8)}.map"
    env = os.environ.copy()
    env["LD_FLAGS"] = f"-Wl,-Map,{marker}"
    result = subprocess.run(
        ["make", "-B"],
        cwd=PACKAGE_DIR,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    assert result.returncode == 0, f"Package failed to build with inherited LD_FLAGS:\n{result.stdout}"
    assert os.path.isfile(marker), "Makefile did not inherit and use LD_FLAGS from the environment."
    assert os.path.isfile(BINARY_PATH) and os.access(BINARY_PATH, os.X_OK)
    with open(BINARY_PATH, "rb") as binary:
        assert binary.read(4) == b"\x7fELF", "sso-decrypt is not a compiled ELF binary."


def test_sso_decrypt_executes_and_decrypts_input():
    token = f"/verify-{secrets.token_hex(12)}?next=account"
    with tempfile.NamedTemporaryFile(mode="w", delete=False) as token_file:
        token_file.write(token)
        token_path = token_file.name
    try:
        result = subprocess.run(
            [BINARY_PATH, token_path],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        assert result.returncode == 0, result.stderr
        assert result.stdout == token
    finally:
        os.unlink(token_path)


def test_adversarial_corpus():
    evil_corpus = "/app/corpus/evil"
    clean_corpus = "/app/corpus/clean"

    try:
        evil_output = subprocess.check_output([SCRIPT_PATH, evil_corpus], stderr=subprocess.STDOUT, text=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Script failed when running on evil corpus. Output:\n{e.output}")

    evil_files = [f for f in os.listdir(evil_corpus) if os.path.isfile(os.path.join(evil_corpus, f))]
    evil_bypassed = []
    for filename in evil_files:
        expected_line = f"{filename}: EVIL"
        if expected_line not in evil_output:
            evil_bypassed.append(filename)

    try:
        clean_output = subprocess.check_output([SCRIPT_PATH, clean_corpus], stderr=subprocess.STDOUT, text=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Script failed when running on clean corpus. Output:\n{e.output}")

    clean_files = [f for f in os.listdir(clean_corpus) if os.path.isfile(os.path.join(clean_corpus, f))]
    clean_modified = []
    for filename in clean_files:
        expected_line = f"{filename}: CLEAN"
        if expected_line not in clean_output:
            clean_modified.append(filename)

    error_msg = []
    if evil_bypassed:
        error_msg.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msg.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (flagged incorrectly): {', '.join(clean_modified)}")
    if error_msg:
        pytest.fail(" | ".join(error_msg))


def test_randomized_mixed_corpus_exact_output_and_binary_use():
    nonce = secrets.token_hex(8)
    cases = {
        f"safe_home_{nonce}.tok": (f"/home/{nonce}", "CLEAN"),
        f"safe_query_{nonce}.tok": (f"/settings?session={nonce}", "CLEAN"),
        f"safe_nested_{nonce}.tok": (f"/dashboard/reports/{nonce}", "CLEAN"),
        f"evil_https_{nonce}.tok": (f"https://outside-{nonce}.example/login", "EVIL"),
        f"evil_http_{nonce}.tok": (f"http://outside-{nonce}.example/redirect", "EVIL"),
        f"evil_relative_{nonce}.tok": (f"//attacker-{nonce}.example/path", "EVIL"),
        f"evil_js_{nonce}.tok": (f"javascript:alert('{nonce}')", "EVIL"),
    }

    with tempfile.TemporaryDirectory(prefix="redirect-corpus-") as corpus:
        for filename, (url, _) in cases.items():
            with open(os.path.join(corpus, filename), "w") as token_file:
                token_file.write(url)

        invocation_log = f"/tmp/sso-invocations-{secrets.token_hex(8)}.log"
        real_binary = os.path.join(PACKAGE_DIR, f".sso-decrypt.verifier-real-{secrets.token_hex(8)}")
        os.replace(BINARY_PATH, real_binary)
        wrapper = """#!/bin/bash
for arg in "$@"; do
    resolved=$(readlink -f -- "$arg" 2>/dev/null || printf '%s' "$arg")
    printf '%s\\n' "$resolved" >> {log}
done
exec {real} "$@"
""".format(log=shlex.quote(invocation_log), real=shlex.quote(real_binary))
        try:
            with open(BINARY_PATH, "w") as wrapper_file:
                wrapper_file.write(wrapper)
            os.chmod(BINARY_PATH, 0o755)
            result = subprocess.run(
                [SCRIPT_PATH, corpus],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
        finally:
            if os.path.exists(BINARY_PATH):
                os.unlink(BINARY_PATH)
            os.replace(real_binary, BINARY_PATH)

        assert result.returncode == 0, f"Detector failed on randomized corpus:\n{result.stdout}{result.stderr}"
        expected_lines = collections.Counter(
            f"{filename}: {classification}" for filename, (_, classification) in cases.items()
        )
        actual_lines = collections.Counter(result.stdout.splitlines())
        assert actual_lines == expected_lines, (
            "Detector output must contain exactly one correctly classified line per file. "
            f"Expected {sorted(expected_lines.elements())}, got {result.stdout!r}"
        )

        assert os.path.isfile(invocation_log), "Detector never invoked the fixed sso-decrypt utility."
        with open(invocation_log) as log_file:
            invoked = collections.Counter(line.rstrip("\n") for line in log_file)
        missing = [
            filename
            for filename in cases
            if invoked[os.path.realpath(os.path.join(corpus, filename))] < 1
        ]
        assert not missing, f"Detector did not invoke sso-decrypt for: {', '.join(missing)}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
