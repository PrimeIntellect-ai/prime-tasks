#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/sanitize_fasta.sh"
CLEAN_DIR = "/home/user/data/clean"
EVIL_DIR = "/home/user/data/evil"
VALID_AA = set("ACDEFGHIKLMNPQRSTVWY")
GC_EQUIV = set("GCPW")


def run_script(input_path, output_path):
    return subprocess.run(
        [SCRIPT_PATH, input_path, output_path],
        capture_output=True,
        text=True,
        timeout=15,
    )


def accepted_records(content):
    records = []
    current = []
    for line in content.splitlines(keepends=True):
        if line.startswith(">"):
            if current:
                records.append(current)
            current = [line]
        elif current:
            current.append(line)
    if current:
        records.append(current)

    accepted = []
    for record in records:
        sequence = "".join(line.strip() for line in record[1:])
        valid_chars = bool(sequence) and all(char in VALID_AA for char in sequence)
        valid_length = 20 <= len(sequence) <= 500
        valid_content = len(sequence) > 0 and 100 * sum(char in GC_EQUIV for char in sequence) <= 60 * len(sequence)
        if valid_chars and valid_length and valid_content:
            accepted.append("".join(record))
    return "".join(accepted)


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Path is not a file: {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script is not executable: {SCRIPT_PATH}"


def test_requires_exactly_two_arguments():
    no_args = subprocess.run([SCRIPT_PATH], capture_output=True, text=True, timeout=15)
    too_many = subprocess.run(
        [SCRIPT_PATH, "/dev/null", "/tmp/out", "extra"],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert no_args.returncode != 0
    assert too_many.returncode != 0


def test_clean_corpus_preserved():
    clean_files = [f for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f))]
    assert len(clean_files) > 0, f"No files found in {CLEAN_DIR}"

    modified_files = []
    with tempfile.TemporaryDirectory() as tmpdir:
        for filename in clean_files:
            input_path = os.path.join(CLEAN_DIR, filename)
            output_path = os.path.join(tmpdir, filename)
            result = run_script(input_path, output_path)
            if result.returncode != 0:
                modified_files.append((filename, f"Script failed with return code {result.returncode}"))
                continue
            if not os.path.exists(output_path):
                modified_files.append((filename, "Output file not created"))
                continue
            with open(input_path) as f_in, open(output_path) as f_out:
                if f_in.read() != f_out.read():
                    modified_files.append((filename, "Output does not match input exactly"))

    if modified_files:
        error_msg = f"{len(modified_files)} of {len(clean_files)} clean files modified or failed.\n"
        error_msg += "Offending files:\n" + "\n".join(f"{name}: {reason}" for name, reason in modified_files[:10])
        if len(modified_files) > 10:
            error_msg += f"\n... and {len(modified_files) - 10} more."
        pytest.fail(error_msg)


def test_evil_corpus_filtered_according_to_rules():
    evil_files = [f for f in os.listdir(EVIL_DIR) if os.path.isfile(os.path.join(EVIL_DIR, f))]
    assert len(evil_files) > 0, f"No files found in {EVIL_DIR}"

    failures = []
    with tempfile.TemporaryDirectory() as tmpdir:
        for filename in evil_files:
            input_path = os.path.join(EVIL_DIR, filename)
            output_path = os.path.join(tmpdir, filename)
            with open(input_path) as f_in:
                expected = accepted_records(f_in.read())
            result = run_script(input_path, output_path)
            if result.returncode != 0:
                failures.append((filename, f"Script failed with return code {result.returncode}"))
                continue
            if not os.path.exists(output_path):
                failures.append((filename, "Output file not created"))
                continue
            with open(output_path) as f_out:
                actual = f_out.read()
            if actual != expected:
                failures.append((filename, "Output does not match rule-derived result"))

    if failures:
        error_msg = f"{len(failures)} of {len(evil_files)} corpus files were handled incorrectly.\n"
        error_msg += "Offending files:\n" + "\n".join(f"{name}: {reason}" for name, reason in failures[:10])
        if len(failures) > 10:
            error_msg += f"\n... and {len(failures) - 10} more."
        pytest.fail(error_msg)


def test_unpredictable_mixed_multirecord_input_and_append_behavior():
    rng = secrets.SystemRandom()

    cases = [
        "G" * 12 + "A" * 8,                    # valid: length 20, exactly 60%
        "G" * 13 + "A" * 7,                    # invalid: over 60%
        "A" * 499 + "W",                       # valid: length 500
        "A" * 501,                              # invalid: too long
        "ACDEFGHIKLMNPQRSTVW",                  # valid: length 20
        "A" * 19,                               # invalid: too short
        "A" * 25 + "X" + "A" * 25,             # invalid character
        "C" * 30 + "D" * 21,                    # valid: below 60%
        "P" * 31 + "E" * 20,                    # invalid: over 60%
        "Y" * 37,
    ]
    rng.shuffle(cases)

    records = []
    for sequence in cases:
        token = secrets.token_hex(12)
        cut = rng.randrange(1, len(sequence))
        records.append(f">sample {token}\n{sequence[:cut]}\n{sequence[cut:]}\n")
    content = "".join(records)
    expected = accepted_records(content)

    with tempfile.TemporaryDirectory(prefix="fasta-check-") as tmpdir:
        input_path = os.path.join(tmpdir, secrets.token_hex(10) + ".fa")
        output_path = os.path.join(tmpdir, secrets.token_hex(10) + ".result")
        prefix = "preexisting-output\n"
        with open(input_path, "w") as f:
            f.write(content)
        with open(output_path, "w") as f:
            f.write(prefix)

        result = run_script(input_path, output_path)
        assert result.returncode == 0, result.stderr
        assert os.path.isfile(output_path)
        with open(output_path) as f:
            actual = f.read()
        assert actual == prefix + expected


def test_unpredictable_all_anomalous_input_creates_empty_output():
    records = [
        f">{secrets.token_hex(8)}\n{'A' * 19}\n",
        f">{secrets.token_hex(8)}\n{'G' * 61 + 'A' * 39}\n",
        f">{secrets.token_hex(8)}\n{'A' * 30 + 'Z'}\n",
        f">{secrets.token_hex(8)}\n{'A' * 501}\n",
    ]
    secrets.SystemRandom().shuffle(records)

    with tempfile.TemporaryDirectory(prefix="sequence-input-") as tmpdir:
        input_path = os.path.join(tmpdir, secrets.token_hex(10))
        output_path = os.path.join(tmpdir, secrets.token_hex(10))
        with open(input_path, "w") as f:
            f.write("".join(records))

        result = run_script(input_path, output_path)
        assert result.returncode == 0, result.stderr
        assert os.path.isfile(output_path), "Output file was not created"
        with open(output_path) as f:
            assert f.read() == ""
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
