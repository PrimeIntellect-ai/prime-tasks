#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import subprocess
import pytest

REDACTOR = "/home/user/redactor"
SOURCE = "/home/user/redactor.c"
REBUILT = "/tmp/redactor_rebuilt"

EXPECTED_CORPUS = {
    "clean/1.txt": b"./legacy_deployer --help\n",
    "clean/2.txt": b"ls -l /var/log\n",
    "clean/3.txt": b"./legacy_deployer -K-not-the-key\n",
    "evil/1.txt": b"./legacy_deployer --db-pass MySecret123 -v\n",
    "evil/2.txt": b"./legacy_deployer --auth-token=ABCDEF\n",
    "evil/3.txt": b"./legacy_deployer -K secret_key\n",
}


def get_expected_redaction(input_str):
    """Derive the expected output from the three reverse-engineered flags."""
    tokens = input_str.split(' ')
    out = []
    skip_next = False

    for token in tokens:
        if skip_next:
            out.append("[REDACTED]")
            skip_next = False
            continue

        if token in ["--db-pass", "-K"]:
            out.append(token)
            skip_next = True
        elif token.startswith("--auth-token="):
            out.append("--auth-token=[REDACTED]")
        else:
            out.append(token)

    if skip_next:
        out.append("[REDACTED]")

    return ' '.join(out)


def run_redactor(path, input_text):
    return subprocess.run(
        [path], input=input_text, text=True, capture_output=True, timeout=5
    )


def test_redactor_exists_and_executable():
    """Verify the student compiled the redactor to the correct path."""
    assert os.path.exists(REDACTOR), f"Redactor binary not found at {REDACTOR}"
    assert os.path.isfile(REDACTOR), f"Expected a file at {REDACTOR}, but found something else."
    assert not os.path.islink(REDACTOR), "Redactor must be a compiled file, not a symbolic link."
    assert os.access(REDACTOR, os.X_OK), f"Redactor binary at {REDACTOR} is not executable."
    with open(REDACTOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Redactor is not a compiled ELF executable."


def test_c_source_exists_compiles_and_is_executable():
    """Require the requested C source and verify that it builds successfully."""
    assert os.path.exists(SOURCE), f"C source not found at {SOURCE}"
    assert os.path.isfile(SOURCE), f"Expected a regular C source file at {SOURCE}"
    assert not os.path.islink(SOURCE), "C source must not be a symbolic link."
    assert os.path.getsize(SOURCE) > 0, "C source is empty."

    proc = subprocess.run(
        ["gcc", "-std=c11", SOURCE, "-o", REBUILT],
        text=True,
        capture_output=True,
        timeout=20,
    )
    assert proc.returncode == 0, f"redactor.c did not compile:\n{proc.stderr}"
    assert os.path.isfile(REBUILT) and os.access(REBUILT, os.X_OK)


def test_corpus_extracted():
    """Verify the student extracted the complete decrypted corpus."""
    clean_dir = "/home/user/corpus/clean"
    evil_dir = "/home/user/corpus/evil"

    assert os.path.isdir(clean_dir), f"Clean corpus directory not found at {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil corpus directory not found at {evil_dir}"

    clean_files = glob.glob(os.path.join(clean_dir, "*"))
    evil_files = glob.glob(os.path.join(evil_dir, "*"))
    assert len(clean_files) > 0, "No files found in clean corpus directory. Extraction may have failed."
    assert len(evil_files) > 0, "No files found in evil corpus directory. Extraction may have failed."

    corpus_root = "/home/user/corpus"
    actual = set()
    for root, dirs, files in os.walk(corpus_root):
        rel_root = os.path.relpath(root, corpus_root)
        if rel_root == ".":
            assert set(dirs) == {"clean", "evil"}, "Corpus has missing or unexpected directories."
        else:
            assert not dirs, "Unexpected nested directory in corpus."
        for name in files:
            path = os.path.join(root, name)
            assert not os.path.islink(path), f"Corpus entry is a symbolic link: {path}"
            actual.add(os.path.relpath(path, corpus_root))

    assert actual == set(EXPECTED_CORPUS), "Corpus files do not match the decrypted archive."
    for relative_path, expected_bytes in EXPECTED_CORPUS.items():
        path = os.path.join(corpus_root, relative_path)
        with open(path, "rb") as f:
            assert f.read() == expected_bytes, f"Corpus file has incorrect content: {relative_path}"


def test_clean_corpus_preserved():
    """Verify that the submitted redactor leaves clean corpus files unchanged."""
    clean_files = glob.glob("/home/user/corpus/clean/*")
    if not clean_files:
        pytest.skip("Clean corpus files not found.")

    failed_files = []
    for filepath in clean_files:
        with open(filepath, 'r') as f:
            original_content = f.read()
        proc = run_redactor(REDACTOR, original_content)
        if proc.returncode != 0 or proc.stdout != original_content:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified: {', '.join(failed_files)}")


def test_evil_corpus_redacted():
    """Verify that the submitted redactor correctly redacts the evil corpus."""
    evil_files = glob.glob("/home/user/corpus/evil/*")
    if not evil_files:
        pytest.skip("Evil corpus files not found.")

    failed_files = []
    for filepath in evil_files:
        with open(filepath, 'r') as f:
            original_content = f.read()
        expected_content = get_expected_redaction(original_content)
        proc = run_redactor(REDACTOR, original_content)
        if proc.returncode != 0 or proc.stdout != expected_content:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil bypassed: {', '.join(failed_files)}")


def test_submitted_and_rebuilt_redactors_on_fresh_inputs():
    """Exercise both the installed binary and freshly compiled C on unpredictable values."""
    secret1 = secrets.token_hex(19)
    secret2 = secrets.token_urlsafe(21)
    secret3 = secrets.token_hex(23)

    cases = [
        f"./legacy_deployer --db-pass {secret1} -v",
        f"./legacy_deployer -K {secret2} --target production",
        f"./legacy_deployer --auth-token={secret3}",
        f"./legacy_deployer --db-pass {secret1} -K {secret2} --auth-token={secret3} done",
        f"printf {secret1} --db-password {secret2} -K-not-the-key --auth-token {secret3}",
        "ls  -l /var/log",
    ]

    for executable in (REDACTOR, REBUILT):
        for input_text in cases:
            expected = get_expected_redaction(input_text)
            proc = run_redactor(executable, input_text)
            assert proc.returncode == 0, f"{executable} exited with {proc.returncode}: {proc.stderr}"
            assert proc.stdout == expected, (
                f"{executable} produced incorrect output for {input_text!r}: "
                f"expected {expected!r}, got {proc.stdout!r}"
            )
            assert proc.stderr == "", f"{executable} wrote unexpected stderr output."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
