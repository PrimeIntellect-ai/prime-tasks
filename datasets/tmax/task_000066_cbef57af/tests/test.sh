#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
from pathlib import Path
import random
import shutil
import string
import subprocess
import tempfile

import pytest

PROJECT = Path("/app/vendored/xsv-0.13.0")
BINARY = PROJECT / "target/release/xsv"
SCRIPT = Path("/home/user/sanitize_feed.sh")
TRIGGER = "__PANIC_" + "UNWRAP_TRIGGER__"


def test_binary_compiled():
    binary_path = str(BINARY)
    assert os.path.isfile(binary_path), f"Compiled binary not found at {binary_path}"
    assert os.access(binary_path, os.X_OK), f"Binary at {binary_path} is not executable"


def test_makefile_rebuilds_real_release_binary():
    makefile = PROJECT / "Makefile"
    assert makefile.is_file(), "Makefile is missing"
    assert "crago" not in makefile.read_text(errors="replace"), "Makefile still contains the broken command"

    if BINARY.exists():
        BINARY.unlink()

    result = subprocess.run(
        ["make", "-B", "build"],
        cwd=PROJECT,
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, f"Makefile build failed:\n{result.stdout}\n{result.stderr}"
    assert BINARY.is_file(), "Makefile did not produce target/release/xsv"
    assert os.access(BINARY, os.X_OK), "Rebuilt release binary is not executable"
    assert BINARY.read_bytes()[:4] == b"\x7fELF", "Rebuilt xsv is not an ELF binary"

    with tempfile.TemporaryDirectory(prefix="xsv-reference-") as target_dir:
        env = os.environ.copy()
        env["CARGO_TARGET_DIR"] = target_dir
        reference_build = subprocess.run(
            ["cargo", "build", "--release"],
            cwd=PROJECT,
            env=env,
            capture_output=True,
            text=True,
            timeout=180,
        )
        assert reference_build.returncode == 0, (
            f"Cargo could not compile the vendored source:\n"
            f"{reference_build.stdout}\n{reference_build.stderr}"
        )
        reference = Path(target_dir) / "release/xsv"
        assert reference.is_file(), "Cargo did not produce the reference xsv binary"
        assert hashlib.sha256(BINARY.read_bytes()).digest() == hashlib.sha256(reference.read_bytes()).digest(), (
            "Makefile output is not the release binary compiled from the vendored Rust source"
        )

    probe = subprocess.run(
        [str(BINARY), "stats"],
        input=b"id,bytes_transferred\n1,100\n",
        capture_output=True,
        timeout=10,
    )
    assert probe.returncode == 0, f"Rebuilt xsv failed when executed: {probe.stderr!r}"


def test_sanitize_script_exists():
    script_path = str(SCRIPT)
    assert os.path.isfile(script_path), f"Sanitize script not found at {script_path}"
    assert os.access(script_path, os.X_OK), f"Sanitize script at {script_path} is not executable"


def test_sanitize_script_empty_file():
    empty_file = "/tmp/empty.csv"
    open(empty_file, "w").close()

    result = subprocess.run([str(SCRIPT), empty_file], capture_output=True)
    assert result.returncode == 1, "Script should exit with code 1 for empty files"

    missing = f"/tmp/does_not_exist_{os.getpid()}.csv"
    result_missing = subprocess.run([str(SCRIPT), missing], capture_output=True)
    assert result_missing.returncode == 1, "Script should exit with code 1 for missing files"


def test_sanitize_script_adversarial_corpus():
    clean_corpus_dir = "/app/corpus/clean"
    evil_corpus_dir = "/app/corpus/evil"

    clean_files = [os.path.join(clean_corpus_dir, f) for f in os.listdir(clean_corpus_dir) if f.endswith(".csv")]
    clean_failures = []
    for cf in clean_files:
        with open(cf, "r") as f:
            expected_output = f.read()
        result = subprocess.run([str(SCRIPT), cf], capture_output=True, text=True)
        if result.returncode != 0:
            clean_failures.append(f"{os.path.basename(cf)} (non-zero exit)")
        elif result.stdout != expected_output:
            clean_failures.append(f"{os.path.basename(cf)} (modified)")

    evil_files = [os.path.join(evil_corpus_dir, f) for f in os.listdir(evil_corpus_dir) if f.endswith(".csv")]
    evil_failures = []
    for ef in evil_files:
        with open(ef, "r") as f:
            lines = f.readlines()
        expected_output = "".join(line for line in lines if TRIGGER not in line)
        result = subprocess.run([str(SCRIPT), ef], capture_output=True, text=True)
        if result.returncode != 0:
            evil_failures.append(f"{os.path.basename(ef)} (non-zero exit)")
        elif result.stdout != expected_output:
            evil_failures.append(f"{os.path.basename(ef)} (bypassed or incorrectly modified)")

    errors = []
    if evil_failures:
        errors.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        errors.append(f"{len(clean_failures)} of {len(clean_files)} clean modified: {', '.join(clean_failures)}")
    if errors:
        pytest.fail(" | ".join(errors))


def _token(rng, length=14):
    alphabet = string.ascii_letters + string.digits
    return "".join(rng.choice(alphabet) for _ in range(length))


def test_sanitizer_on_generated_unseen_inputs(tmp_path):
    rng = random.SystemRandom()

    for case_number in range(8):
        header = f"event_id,source,bytes_transferred,note_{_token(rng, 7)}\n"
        rows = []
        malicious_indexes = set(rng.sample(range(18), rng.randint(3, 8)))

        for index in range(18):
            event_id = rng.randrange(100000, 999999)
            source = _token(rng)
            amount = rng.randrange(0, 10_000_000)
            if index in malicious_indexes:
                placements = [
                    TRIGGER,
                    f"prefix-{_token(rng, 5)}-{TRIGGER}",
                    f"{TRIGGER}-suffix-{_token(rng, 5)}",
                    f'"quoted-{_token(rng, 4)}-{TRIGGER}"',
                ]
                note = rng.choice(placements)
            else:
                safe_near_misses = [
                    "__PANIC_UNWRAP_TRIGGEX__",
                    "__PANIC_WRAP_TRIGGER__",
                    "__panic_unwrap_trigger__",
                    "ordinary-" + _token(rng),
                    "",
                ]
                note = rng.choice(safe_near_misses)
            rows.append(f"{event_id},{source},{amount},{note}\n")

        data = (header + "".join(rows)).encode()
        expected = (header + "".join(row for i, row in enumerate(rows) if i not in malicious_indexes)).encode()
        input_path = tmp_path / f"generated_{case_number}_{_token(rng, 8)}.csv"
        input_path.write_bytes(data)

        result = subprocess.run([str(SCRIPT), str(input_path)], capture_output=True, timeout=15)
        assert result.returncode == 0, f"Sanitizer failed on generated case {case_number}: {result.stderr!r}"
        assert result.stdout == expected, (
            f"Sanitizer did not exactly preserve clean rows and remove malicious rows in generated case {case_number}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
