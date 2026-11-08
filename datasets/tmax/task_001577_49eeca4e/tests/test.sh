#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess
import pytest

AGENT_BIN = "/home/user/workspace/log_filter"
WORKSPACE = "/home/user/workspace"
ORACLE_BIN = "/app/legacy_filter"
CLEAN_CORPUS_DIR = "/app/secret_corpus/clean"
EVIL_CORPUS_DIR = "/app/secret_corpus/evil"


def run_filter(input_text: str) -> str:
    result = subprocess.run(
        [AGENT_BIN],
        input=input_text,
        text=True,
        capture_output=True,
        check=False,
        timeout=10,
    )
    return result.stdout


def test_makefile_builds_executable_from_scratch():
    if os.path.lexists(AGENT_BIN):
        os.remove(AGENT_BIN)

    result = subprocess.run(
        ["make", "-B"],
        cwd=WORKSPACE,
        text=True,
        capture_output=True,
        check=False,
        timeout=30,
    )
    assert result.returncode == 0, f"make failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(AGENT_BIN), "make did not create log_filter"
    assert os.access(AGENT_BIN, os.X_OK), "make did not create an executable log_filter"
    with open(AGENT_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "log_filter is not a compiled executable"


def test_agent_binary_exists():
    assert os.path.isfile(AGENT_BIN), f"Expected executable not found at {AGENT_BIN}"
    assert os.access(AGENT_BIN, os.X_OK), f"File at {AGENT_BIN} is not executable"


def test_adversarial_corpus_evaluation():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Missing clean corpus dir: {CLEAN_CORPUS_DIR}"
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Missing evil corpus dir: {EVIL_CORPUS_DIR}"

    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]

    bypassed_evil = []
    modified_clean = []

    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, filename)
        with open(filepath, 'r') as f:
            content = f.read()

        output = run_filter(content)
        input_lines = content.splitlines()
        output_lines = [line for line in output.splitlines() if line]

        if len(output_lines) > 0:
            bypassed_evil.append(filename)

    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, filename)
        with open(filepath, 'r') as f:
            content = f.read()

        output = run_filter(content)
        input_lines = [line for line in content.splitlines() if line]
        output_lines = [line for line in output.splitlines() if line]

        if input_lines != output_lines:
            modified_clean.append(filename)

    errors = []
    if bypassed_evil:
        errors.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_evil)}")
    if modified_clean:
        errors.append(f"{len(modified_clean)} of {len(clean_files)} clean modified: {', '.join(modified_clean)}")

    if errors:
        pytest.fail(" | ".join(errors))


def oracle_is_clean(line: bytes) -> bool:
    result = subprocess.run(
        [ORACLE_BIN],
        input=line + b"\n",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        timeout=3,
    )
    assert result.returncode in (0, 1), f"legacy oracle returned {result.returncode}"
    return result.returncode == 0


def test_runtime_generated_inputs_match_legacy_oracle_exactly():
    assert os.path.isfile(ORACLE_BIN) and os.access(ORACLE_BIN, os.X_OK)

    rng = random.SystemRandom()
    alphabet = string.ascii_letters + string.digits + " []{}()_-=:+,./@#%!?"
    trigger_tokens = ["FATAL:", "PANIC:", "CREDENTIALS="]
    near_misses = [
        "fatal:", "Fatal:", "FATAL", "FATAL :", "PANIC", "panic:",
        "CREDENTIALS", "credentials=", "CREDENTIAL=", "CREDENTIALS =",
    ]

    lines = [
        b"FATAL:", b"PANIC:", b"CREDENTIALS=", b"prefixFATAL:suffix",
        b"left PANIC: right", b"xCREDENTIALS=y", b"", b"ordinary clean line",
    ]

    for i in range(320):
        nonce = ''.join(rng.choice(alphabet) for _ in range(rng.randint(8, 90)))
        marker = ''.join(rng.choice(string.ascii_letters + string.digits) for _ in range(24))
        base = f"case-{marker}-{i}-{nonce}"
        mode = rng.randrange(4)
        if mode == 0:
            token = rng.choice(trigger_tokens)
            pos = rng.randrange(len(base) + 1)
            base = base[:pos] + token + base[pos:]
        elif mode == 1:
            token = rng.choice(near_misses)
            pos = rng.randrange(len(base) + 1)
            base = base[:pos] + token + base[pos:]
        elif mode == 2:
            base = rng.choice(["INFO: ", "DEBUG: ", "WARNING: ", "TRACE: "]) + base
        lines.append(base.encode("ascii"))

    rng.shuffle(lines)
    expected = b"".join(line + b"\n" for line in lines if oracle_is_clean(line))
    input_data = b"".join(line + b"\n" for line in lines)

    result = subprocess.run(
        [AGENT_BIN],
        input=input_data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        timeout=15,
    )
    assert result.returncode == 0, f"log_filter exited with {result.returncode}: {result.stderr!r}"
    assert result.stdout == expected, "output did not exactly match classifications derived from the legacy oracle"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
