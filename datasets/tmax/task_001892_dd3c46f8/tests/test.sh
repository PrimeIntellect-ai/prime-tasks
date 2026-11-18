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

SCRIPT_PATH = "/home/user/process_pipeline.sh"
CLEAN_CORPUS_DIR = "/home/user/corpora/clean"
EVIL_CORPUS_DIR = "/home/user/corpora/evil"


def get_expected_clean_output(input_filepath):
    expected_lines = []
    with open(input_filepath, 'r') as f:
        for line in f:
            if "DEBUG_TRACE" in line:
                continue
            masked_line = re.sub(r'\b\d{3}-\d{2}-\d{4}\b', '***-**-****', line)
            expected_lines.append(masked_line)
    return "".join(expected_lines)


def expected_from_lines(lines):
    return "".join(
        re.sub(r'\b\d{3}-\d{2}-\d{4}\b', '***-**-****', line)
        for line in lines
        if "DEBUG_TRACE" not in line
    )


def run_generated_case(lines, expected_returncode, expected_output):
    with tempfile.TemporaryDirectory(prefix="pipeline_case_") as root:
        nested = os.path.join(root, secrets.token_hex(8), secrets.token_hex(8))
        os.makedirs(nested)
        input_file = os.path.join(nested, secrets.token_hex(12) + ".data")
        output_file = os.path.join(root, secrets.token_hex(12) + ".result")

        with open(input_file, "w") as f:
            f.writelines(lines)
        # A rejected input must clear an existing destination rather than leave
        # stale or partially processed data behind.
        with open(output_file, "w") as f:
            f.write("PREEXISTING_DESTINATION_CONTENT\n")

        result = subprocess.run(
            [SCRIPT_PATH, input_file, output_file],
            capture_output=True,
            timeout=10,
        )
        assert result.returncode == expected_returncode, (
            f"expected exit {expected_returncode}, got {result.returncode}; "
            f"stderr={result.stderr!r}"
        )
        assert os.path.exists(output_file), "destination file was not created"
        with open(output_file, "r") as f:
            actual_output = f.read()
        assert actual_output == expected_output


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable"


def test_evil_corpus_rejected():
    if not os.path.exists(EVIL_CORPUS_DIR):
        pytest.skip(f"Evil corpus directory {EVIL_CORPUS_DIR} not found.")

    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    bypassed_files = []

    for filename in evil_files:
        input_file = os.path.join(EVIL_CORPUS_DIR, filename)
        with tempfile.NamedTemporaryFile() as tmp_out:
            result = subprocess.run(
                [SCRIPT_PATH, input_file, tmp_out.name],
                capture_output=True
            )
            with open(tmp_out.name, 'r') as f:
                output = f.read()
            if result.returncode != 1 or output != "":
                bypassed_files.append(filename)

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil bypassed or produced output. Offending files: {', '.join(bypassed_files)}")


def test_clean_corpus_accepted():
    if not os.path.exists(CLEAN_CORPUS_DIR):
        pytest.skip(f"Clean corpus directory {CLEAN_CORPUS_DIR} not found.")

    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    modified_files = []

    for filename in clean_files:
        input_file = os.path.join(CLEAN_CORPUS_DIR, filename)
        expected_output = get_expected_clean_output(input_file)

        with tempfile.NamedTemporaryFile() as tmp_out:
            result = subprocess.run(
                [SCRIPT_PATH, input_file, tmp_out.name],
                capture_output=True
            )

            if result.returncode != 0:
                modified_files.append(f"{filename} (exit code {result.returncode})")
                continue

            with open(tmp_out.name, 'r') as f:
                actual_output = f.read()

            if actual_output != expected_output:
                modified_files.append(f"{filename} (content mismatch)")

    if modified_files:
        pytest.fail(f"{len(modified_files)} of {len(clean_files)} clean modified or failed. Offending files: {', '.join(modified_files)}")


def test_generated_clean_inputs_at_runtime():
    tag = secrets.token_hex(16)

    # Exactly 1000 is permitted, and filtering occurs only after validation.
    lines = [
        f"INFO {tag} user 111-22-3333 BYTES: 200\n",
        f"DEBUG_TRACE {tag} secret 222-33-4444 BYTES: 300\n",
        f"WARN {tag} user 555-66-7777 BYTES: 500\n",
        f"INFO {tag} two SSNs 888-99-0000 and 123-45-6789 BYTES: 100\n",
    ]
    run_generated_case(lines, 0, expected_from_lines(lines))

    # With fewer than three lines there is no three-line window.
    tag = secrets.token_hex(16)
    lines = [
        f"INFO {tag} 314-15-9265 BYTES: 5000\n",
        f"INFO {tag} 271-82-8182 BYTES: 6000\n",
    ]
    run_generated_case(lines, 0, expected_from_lines(lines))

    # Exercise several overlapping windows using values selected at test time.
    tag = secrets.token_hex(16)
    values = [secrets.randbelow(251) for _ in range(9)]
    lines = []
    for i, value in enumerate(values):
        prefix = "DEBUG_TRACE" if i in (2, 7) else "INFO"
        lines.append(f"{prefix} {tag}-{i} 765-43-2109 BYTES: {value}\n")
    run_generated_case(lines, 0, expected_from_lines(lines))


def test_generated_anomalies_rejected_with_empty_destination():
    # Put the offending window at different offsets and vary its values at
    # verification time so behavior cannot be keyed to the shipped corpus.
    for offset in (0, 1, 3, 5):
        tag = secrets.token_hex(16)
        first = 100 + secrets.randbelow(301)
        second = 100 + secrets.randbelow(301)
        excess = 1 + secrets.randbelow(200)
        third = 1000 - first - second + excess
        values = [10] * offset + [first, second, third] + [10, 20]
        lines = []
        for i, value in enumerate(values):
            prefix = "DEBUG_TRACE" if i == offset + 1 else "INFO"
            lines.append(
                f"{prefix} runtime-{tag}-{i} user 246-80-1357 BYTES: {value}\n"
            )
        run_generated_case(lines, 1, "")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
