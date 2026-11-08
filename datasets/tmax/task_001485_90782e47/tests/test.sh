#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import uuid
from pathlib import Path

import pytest

APP = Path("/app")
LIBDIR = APP / "libparser"
VALIDATOR = APP / "validator"
MAGIC = b"PY3_V2"


def validator_env(extra=None):
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = str(LIBDIR) + ":" + env.get("LD_LIBRARY_PATH", "")
    if extra:
        env.update(extra)
    return env


def run_validator(path, env=None):
    return subprocess.run(
        [str(VALIDATOR), str(path)],
        env=env or validator_env(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )


def test_libparser_built_and_makefile_fixed():
    """Verify the library exists and can be rebuilt by the fixed Makefile."""
    so_path = LIBDIR / "libparser.so"
    assert so_path.is_file(), f"Shared library {so_path} is missing. Did the Makefile build succeed?"

    dry_run = subprocess.run(
        ["make", "-Bn"], cwd=LIBDIR, text=True, capture_output=True, timeout=20
    )
    assert dry_run.returncode == 0, f"Makefile dry run failed:\n{dry_run.stdout}\n{dry_run.stderr}"
    compile_lines = [line for line in dry_run.stdout.splitlines() if "parser.c" in line]
    assert any(re.search(r"(^|\\s)-fPIC(\\s|$)", line) for line in compile_lines), (
        "The parser object is not compiled with -fPIC. Make output:\n" + dry_run.stdout
    )

    for output in (LIBDIR / "parser.o", so_path):
        if output.exists() or output.is_symlink():
            output.unlink()
    built = subprocess.run(
        ["make"], cwd=LIBDIR, text=True, capture_output=True, timeout=30
    )
    assert built.returncode == 0, f"make failed:\n{built.stdout}\n{built.stderr}"
    assert so_path.is_file(), "make succeeded without producing libparser.so"


def test_validator_exists_and_linked():
    """Verify that the required source and executable exist and link to libparser.so."""
    source_path = APP / "validator.c"
    assert source_path.is_file(), f"Validator source {source_path} is missing."
    assert VALIDATOR.is_file(), f"Validator executable {VALIDATOR} is missing."
    assert os.access(VALIDATOR, os.X_OK), f"Validator executable {VALIDATOR} is not executable."

    try:
        ldd_output = subprocess.check_output(["ldd", str(VALIDATOR)], text=True, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as exc:
        pytest.fail(f"Failed to run ldd on {VALIDATOR}: {exc.output}")
    assert "libparser.so" in ldd_output, (
        f"Validator is not linked against libparser.so. ldd output: {ldd_output}"
    )


def test_validator_clean_corpus():
    """Verify that the validator accepts all files in the clean corpus."""
    clean_dir = APP / "corpus" / "clean"
    assert clean_dir.is_dir(), f"Clean corpus directory {clean_dir} is missing."
    clean_files = list(clean_dir.iterdir())
    assert clean_files, "Clean corpus is empty."

    failed_files = []
    for f in clean_files:
        if f.is_file() and run_validator(f).returncode != 0:
            failed_files.append(f.name)
    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(clean_files)} clean modified (rejected). "
            f"Offending files: {', '.join(failed_files)}"
        )


def test_validator_evil_corpus():
    """Verify that the validator rejects all files in the evil corpus."""
    evil_dir = APP / "corpus" / "evil"
    assert evil_dir.is_dir(), f"Evil corpus directory {evil_dir} is missing."
    evil_files = list(evil_dir.iterdir())
    assert evil_files, "Evil corpus is empty."

    bypassed_files = []
    for f in evil_files:
        if f.is_file() and run_validator(f).returncode == 0:
            bypassed_files.append(f.name)
    if bypassed_files:
        pytest.fail(
            f"{len(bypassed_files)} of {len(evil_files)} evil bypassed (accepted). "
            f"Offending files: {', '.join(bypassed_files)}"
        )


def test_randomized_paths_and_payloads(tmp_path):
    """Exercise content validation using unpredictable paths and file names."""
    random_part = secrets.token_bytes(29)
    while random_part.endswith(b"DONE"):
        random_part = secrets.token_bytes(29)

    cases = [
        (MAGIC + b"DONE", True),
        (MAGIC + secrets.token_bytes(31) + b"DONE", True),
        (MAGIC + b"abc\x00def\xff" + b"DONE", True),
        (b"PY2_V1" + secrets.token_bytes(17) + b"DONE", False),
        (MAGIC + random_part, False),
        (MAGIC, False),
        (b"PY3_V", False),
        (secrets.token_bytes(23), False),
    ]

    for data, should_accept in cases:
        nested = tmp_path / uuid.uuid4().hex / uuid.uuid4().hex
        nested.mkdir(parents=True)
        path = nested / (uuid.uuid4().hex + ".bin")
        path.write_bytes(data)
        result = run_validator(path)
        assert (result.returncode == 0) == should_accept, (
            f"Validator returned {result.returncode} for randomized case "
            f"expected to be {'accepted' if should_accept else 'rejected'}"
        )


def test_validator_calls_parse_data_and_honors_result(tmp_path):
    """Interpose parse_data to verify the post-header bytes are passed to the library."""
    probe_source = tmp_path / "probe.c"
    probe_so = tmp_path / "probe.so"
    marker = tmp_path / "called"
    expected = tmp_path / "expected.bin"

    probe_source.write_text(r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int parse_data(const char *buffer, int len) {
    const char *expected_path = getenv("PROBE_EXPECTED");
    const char *marker_path = getenv("PROBE_MARKER");
    unsigned char expected[4096];
    size_t expected_len = 0;
    FILE *f;

    if (marker_path) {
        f = fopen(marker_path, "ab");
        if (f) {
            fwrite(&len, sizeof(len), 1, f);
            if (len > 0) fwrite(buffer, 1, (size_t)len, f);
            fclose(f);
        }
    }
    if (!expected_path || len < 0) return -1;
    f = fopen(expected_path, "rb");
    if (!f) return -1;
    expected_len = fread(expected, 1, sizeof(expected), f);
    if (!feof(f)) { fclose(f); return -1; }
    fclose(f);
    if ((size_t)len != expected_len) return -1;
    return memcmp(buffer, expected, expected_len) == 0 ? 0 : -1;
}
''')
    compiled = subprocess.run(
        ["gcc", "-shared", "-fPIC", "-o", str(probe_so), str(probe_source)],
        text=True,
        capture_output=True,
        timeout=20,
    )
    assert compiled.returncode == 0, f"Failed to build parse_data probe: {compiled.stderr}"

    payload = secrets.token_bytes(37)
    while payload.endswith(b"DONE"):
        payload = secrets.token_bytes(37)
    expected.write_bytes(payload)
    env = validator_env({
        "LD_PRELOAD": str(probe_so),
        "PROBE_EXPECTED": str(expected),
        "PROBE_MARKER": str(marker),
    })

    valid = tmp_path / (uuid.uuid4().hex + ".bin")
    valid.write_bytes(MAGIC + payload)
    assert run_validator(valid, env).returncode == 0, (
        "Validator did not pass the bytes after the correct header to parse_data, "
        "or did not honor parse_data success"
    )
    assert marker.is_file() and marker.stat().st_size > 0, "parse_data was not called"

    marker.unlink()
    different = tmp_path / (uuid.uuid4().hex + ".bin")
    different.write_bytes(MAGIC + payload + b"x")
    assert run_validator(different, env).returncode != 0, "Validator ignored parse_data failure"
    assert marker.is_file(), "parse_data was not called for a correctly headed payload"

    marker.unlink()
    wrong_header = tmp_path / (uuid.uuid4().hex + ".bin")
    wrong_header.write_bytes(b"PY2_V1" + payload)
    assert run_validator(wrong_header, env).returncode != 0, "Validator accepted an incorrect magic header"
    assert not marker.exists(), "Validator called parse_data before rejecting an incorrect header"


def test_cli_rejects_wrong_argument_count(tmp_path):
    no_arg = subprocess.run([str(VALIDATOR)], env=validator_env(), timeout=5)
    assert no_arg.returncode != 0, "Validator accepted a missing file argument"
    sample = tmp_path / "sample.bin"
    sample.write_bytes(MAGIC + b"DONE")
    two_args = subprocess.run(
        [str(VALIDATOR), str(sample), str(sample)], env=validator_env(), timeout=5
    )
    assert two_args.returncode != 0, "Validator accepted more than one file argument"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
