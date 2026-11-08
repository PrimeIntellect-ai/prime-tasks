#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
import pytest


def test_bats_core_fixed():
    """Test that the vendored bats-core package is fixed and can run tests."""
    bats_bin = "/app/bats-core-1.11.0/bin/bats"
    test_file = "/app/corpus/clean/basic.bats"

    assert os.path.isfile(bats_bin), f"Bats executable {bats_bin} is missing."
    assert os.path.isfile(test_file), f"Test file {test_file} is missing."

    # Preserve the original corpus assertion.
    result = subprocess.run([bats_bin, test_file], capture_output=True, text=True)
    assert result.returncode == 0, (
        f"bats-core is still broken. Running {bats_bin} {test_file} failed with exit code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )

    exec_test = "/app/bats-core-1.11.0/libexec/bats-core/bats-exec-test"
    assert os.path.isfile(exec_test), f"Required bats-core component {exec_test} is missing."
    with open(exec_test, "rb") as f:
        assert b"BATS_TEST_FILENAME_BROKEN" not in f.read(), "The deliberate bats-exec-test perturbation remains."

    # Exercise dynamically generated tests and require actual test execution,
    # correct TAP output, and correct propagation of a failing test.
    token = secrets.token_hex(16)
    with tempfile.TemporaryDirectory(prefix="bats-core-check-") as td:
        pass_file = os.path.join(td, secrets.token_hex(8) + ".bats")
        fail_file = os.path.join(td, secrets.token_hex(8) + ".bats")
        pass_marker = os.path.join(td, "pass-" + secrets.token_hex(8))
        fail_marker = os.path.join(td, "fail-" + secrets.token_hex(8))

        with open(pass_file, "w") as f:
            f.write(f'''#!/usr/bin/env bats

@test "dynamic side effect {token}" {{
  printf '%s' '{token}' > '{pass_marker}'
  [ "$(cat '{pass_marker}')" = '{token}' ]
}}

@test "dynamic run semantics {token}" {{
  run bash -c 'printf %s "$1"' _ '{token}'
  [ "$status" -eq 0 ]
  [ "$output" = '{token}' ]
}}
''')

        with open(fail_file, "w") as f:
            f.write(f'''#!/usr/bin/env bats

@test "dynamic intentional failure {token}" {{
  printf '%s' '{token}' > '{fail_marker}'
  [ 1 -eq 2 ]
}}
''')

        passed = subprocess.run([bats_bin, pass_file], capture_output=True, text=True, timeout=30)
        assert passed.returncode == 0, f"Generated valid Bats suite failed:\n{passed.stdout}\n{passed.stderr}"
        assert os.path.isfile(pass_marker) and open(pass_marker).read() == token, "Generated Bats test was not executed."
        assert re.search(r"^1\.\.2\s*$", passed.stdout, re.MULTILINE), f"Missing Bats TAP plan:\n{passed.stdout}"
        assert re.search(r"^ok 1\b", passed.stdout, re.MULTILINE), f"First passing test was not reported:\n{passed.stdout}"
        assert re.search(r"^ok 2\b", passed.stdout, re.MULTILINE), f"Second passing test was not reported:\n{passed.stdout}"

        failed = subprocess.run([bats_bin, fail_file], capture_output=True, text=True, timeout=30)
        assert failed.returncode != 0, "bats returned success for an intentionally failing generated test."
        assert os.path.isfile(fail_marker) and open(fail_marker).read() == token, "Failing generated Bats test was not executed."
        assert re.search(r"^1\.\.1\s*$", failed.stdout, re.MULTILINE), f"Missing failing-suite TAP plan:\n{failed.stdout}"
        assert re.search(r"^not ok 1\b", failed.stdout, re.MULTILINE), f"Failure was not reported as Bats TAP:\n{failed.stdout}"


def test_bats_linter_adversarial_corpus():
    """Test the bats_linter.sh against the supplied and generated corpora."""
    linter_script = "/home/user/bats_linter.sh"
    assert os.path.isfile(linter_script), f"Linter script {linter_script} is missing."

    clean_corpus_dir = "/app/corpus/clean"
    evil_corpus_dir = "/app/corpus/evil"
    assert os.path.isdir(clean_corpus_dir), f"Clean corpus directory {clean_corpus_dir} is missing."
    assert os.path.isdir(evil_corpus_dir), f"Evil corpus directory {evil_corpus_dir} is missing."

    clean_files = [os.path.join(clean_corpus_dir, f) for f in os.listdir(clean_corpus_dir) if os.path.isfile(os.path.join(clean_corpus_dir, f))]
    evil_files = [os.path.join(evil_corpus_dir, f) for f in os.listdir(evil_corpus_dir) if os.path.isfile(os.path.join(evil_corpus_dir, f))]
    failed_clean = []
    failed_evil = []

    # Preserve all original fixed-corpus checks.
    for f in clean_files:
        res = subprocess.run(["bash", linter_script, f], capture_output=True)
        if res.returncode != 0:
            failed_clean.append(os.path.basename(f))
    for f in evil_files:
        res = subprocess.run(["bash", linter_script, f], capture_output=True)
        if res.returncode == 0:
            failed_evil.append(os.path.basename(f))

    error_messages = []
    if failed_clean:
        error_messages.append(f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_clean)}")
    if failed_evil:
        error_messages.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed/accepted: {', '.join(failed_evil)}")
    assert not error_messages, "Linter failed corpus checks:\n" + "\n".join(error_messages)

    token = secrets.token_hex(12).encode()
    shebang = b"#!/usr/bin/env bats"
    cases = [
        ("only-shebang", shebang, 0),
        ("ordinary-clean", shebang + b"\n# " + token + b"\n@test \"ok\" { true; }\n", 0),
        ("word-prefix", shebang + b"\n# evaluate devaluation pre_eval eval2 2eval\n", 0),
        ("case-sensitive", shebang + b"\n# EVAL Eval eVaL\n", 0),
        ("long-clean", shebang + b"\n# " + b"x" * 100000 + b" evaluate\n", 0),
        ("wrong-interpreter", b"#!/bin/bash\n@test \"x\" { true; }\n", 1),
        ("leading-blank", b"\n" + shebang + b"\n", 1),
        ("leading-space", b" " + shebang + b"\n", 1),
        ("trailing-space", shebang + b" \n", 1),
        ("crlf-header", shebang + b"\r\n@test \"x\" { true; }\n", 1),
        ("bom-header", b"\xef\xbb\xbf" + shebang + b"\n", 1),
        ("extra-argument", shebang + b" --trace\n", 1),
        ("empty", b"", 1),
        ("bare-keyword", shebang + b"\neval\n", 1),
        ("comment-keyword", shebang + b"\n# " + token + b" eval now\n", 1),
        ("quoted-keyword", shebang + b"\nvalue=\"eval\"\n", 1),
        ("punctuation-keyword", shebang + b"\n# (eval), eval; eval-here\n", 1),
        ("variable-keyword", shebang + b"\n# $eval\n", 1),
        ("tab-keyword", shebang + b"\n#\teval\t\n", 1),
        ("nul-keyword", shebang + b"\n# \x00eval\x00\n", 1),
        ("far-keyword", shebang + b"\n# " + b"z" * 100000 + b" eval\n", 1),
    ]

    with tempfile.TemporaryDirectory(prefix="linter-check-" + secrets.token_hex(6) + "-") as td:
        for index, (label, data, expected) in enumerate(cases):
            # Include misleading words in filenames to catch filename-specific logic.
            filename = f"{secrets.token_hex(8)} eval fixture {index}.bats"
            path = os.path.join(td, filename)
            with open(path, "wb") as f:
                f.write(data)
            result = subprocess.run(["bash", linter_script, path], capture_output=True, timeout=10)
            assert result.returncode == expected, (
                f"Generated linter case {label!r} returned {result.returncode}, expected {expected}. "
                f"stdout={result.stdout!r}, stderr={result.stderr!r}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
