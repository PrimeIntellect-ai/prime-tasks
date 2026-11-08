#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import random
import re
import secrets
import shutil
import string
import subprocess
import tempfile
import pytest

PROJECT = "/home/user/parser_project"
SO_PATH = os.path.join(PROJECT, "libparser.so")
SCRIPT_PATH = "/home/user/classifier.py"


def run_classifier(path):
    return subprocess.run(
        ["python3", SCRIPT_PATH, path],
        capture_output=True,
        timeout=5,
    )


def is_malicious(text):
    return any(ch in text for ch in ";|&$") or re.search(r"\bsudo\b", text) is not None


def test_libparser_built():
    assert os.path.isfile(os.path.join(PROJECT, "Makefile")), "Failed: Makefile does not exist."
    result = subprocess.run(
        ["make", "-B"], cwd=PROJECT, capture_output=True, text=True, timeout=20
    )
    assert result.returncode == 0, f"Failed to build libparser.so:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(SO_PATH), f"Failed: {SO_PATH} was not built."

    try:
        library = ctypes.CDLL(SO_PATH)
        parse_cmd = library.parse_cmd
        parse_cmd.argtypes = [ctypes.c_char_p]
        parse_cmd.restype = ctypes.c_int
        assert parse_cmd(b"echo verifier_probe") == 0
    except Exception as exc:
        pytest.fail(f"Failed: libparser.so is not a loadable shared library exposing parse_cmd: {exc}")


def test_pin_txt_content():
    pin_path = "/home/user/pin.txt"
    assert os.path.isfile(pin_path), f"Failed: {pin_path} does not exist."
    with open(pin_path, "r") as f:
        content = f.read().strip()
    assert content == "8675309", f"Failed: {pin_path} contains '{content}', expected '8675309'."


def test_classifier_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Failed: {SCRIPT_PATH} does not exist."


def test_classifier_clean_corpus():
    clean_dir = "/app/corpus/clean/"
    assert os.path.isdir(clean_dir), f"Failed: {clean_dir} does not exist."
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    assert clean_files, "No files found in clean corpus."
    failures = []
    for fpath in clean_files:
        if run_classifier(fpath).returncode != 0:
            failures.append(os.path.basename(fpath))
    if failures:
        pytest.fail(f"{len(failures)} of {len(clean_files)} clean files rejected (should be accepted): {', '.join(failures)}")


def test_classifier_evil_corpus():
    evil_dir = "/app/corpus/evil/"
    assert os.path.isdir(evil_dir), f"Failed: {evil_dir} does not exist."
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    assert evil_files, "No files found in evil corpus."
    failures = []
    for fpath in evil_files:
        if run_classifier(fpath).returncode != 1:
            failures.append(os.path.basename(fpath))
    if failures:
        pytest.fail(f"{len(failures)} of {len(evil_files)} evil files bypassed (should be rejected): {', '.join(failures)}")


def test_classifier_hidden_adversarial_corpus():
    nonce = secrets.token_hex(16)
    safe_alphabet = string.ascii_letters + string.digits + " _-/\.\n\t"
    cases = [
        f"echo hidden_{nonce}",
        f"ls -la /tmp/{nonce}",
        f"printf hidden_{nonce}",
        f"pseudocode {nonce}",
        f"sudoku {nonce}",
        f"sudoers {nonce}",
        f"{nonce};rm -rf /tmp/x",
        f"echo {nonce}|cat",
        f"echo {nonce}&background",
        f"echo ${nonce}",
        f"echo {nonce} sudo whoami",
        f"sudo\necho {nonce}",
        f"echo {nonce}\tsudo",
    ]

    rng = random.SystemRandom()
    for _ in range(40):
        text = "".join(rng.choice(safe_alphabet) for _ in range(rng.randint(10, 100)))
        cases.append(text)
        insertion = rng.choice([";", "|", "&", "$", " sudo "])
        position = rng.randrange(len(text) + 1)
        cases.append(text[:position] + insertion + text[position:])

    with tempfile.TemporaryDirectory(prefix="classifier_hidden_") as directory:
        failures = []
        for index, content in enumerate(cases):
            path = os.path.join(directory, f"case_{index}_{secrets.token_hex(6)}.txt")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(content)
            expected = 1 if is_malicious(content) else 0
            result = run_classifier(path)
            if result.returncode != expected:
                failures.append((index, expected, result.returncode, repr(content)))
        if failures:
            pytest.fail(f"Classifier failed generated hidden cases: {failures[:5]}")


def test_classifier_loads_and_calls_parse_cmd():
    assert os.path.isfile(SO_PATH), f"Failed: {SO_PATH} does not exist."
    probe_text = "echo call_probe_" + secrets.token_hex(20)
    marker_path = "/tmp/parse_cmd_marker_" + secrets.token_hex(16)
    marker_token = secrets.token_hex(24)
    expected_bytes = ",".join(str(value) for value in probe_text.encode("ascii")) + ",0"

    source = f'''#include <stdio.h>
#include <string.h>
int parse_cmd(const char *cmd) {{
    static const unsigned char expected[] = {{{expected_bytes}}};
    if (cmd != NULL && strcmp(cmd, (const char *)expected) == 0) {{
        FILE *f = fopen("{marker_path}", "w");
        if (f != NULL) {{ fputs("{marker_token}", f); fclose(f); }}
    }}
    return 0;
}}
'''

    with tempfile.TemporaryDirectory(prefix="parser_probe_") as directory:
        source_path = os.path.join(directory, "probe.c")
        replacement_path = os.path.join(directory, "libparser.so")
        backup_path = os.path.join(directory, "original_libparser.so")
        input_path = os.path.join(directory, "input_" + secrets.token_hex(8) + ".txt")
        with open(source_path, "w", encoding="utf-8") as handle:
            handle.write(source)
        with open(input_path, "w", encoding="utf-8") as handle:
            handle.write(probe_text)

        compile_result = subprocess.run(
            ["gcc", "-shared", "-fPIC", "-o", replacement_path, source_path],
            capture_output=True, text=True, timeout=20
        )
        assert compile_result.returncode == 0, compile_result.stderr

        shutil.copy2(SO_PATH, backup_path)
        try:
            os.replace(replacement_path, SO_PATH)
            result = run_classifier(input_path)
            assert result.returncode == 0, "Classifier rejected the clean parse_cmd call probe."
            assert os.path.isfile(marker_path), "classifier.py did not load and call parse_cmd from libparser.so."
            with open(marker_path, "r", encoding="utf-8") as handle:
                assert handle.read() == marker_token, "parse_cmd was not called with the input file contents."
        finally:
            if os.path.exists(backup_path):
                os.replace(backup_path, SO_PATH)
            if os.path.exists(marker_path):
                os.unlink(marker_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
