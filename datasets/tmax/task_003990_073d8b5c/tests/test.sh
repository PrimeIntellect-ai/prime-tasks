#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import subprocess
import tempfile


def run_sanitizer(path):
    return subprocess.run(
        ["/home/user/loc_sanitizer", path],
        capture_output=True,
        timeout=10,
    )


def csv_record(string_id, language, translation):
    escaped = translation.replace('"', '""')
    return f'{string_id},{language},"{escaped}"\n'


def test_sanitizer_exists_and_executable():
    """Test that the compiled C program exists and is executable."""
    sanitizer_path = "/home/user/loc_sanitizer"
    assert os.path.isfile(sanitizer_path), f"Sanitizer executable is missing: {sanitizer_path}"
    assert os.access(sanitizer_path, os.X_OK), f"Sanitizer is not executable: {sanitizer_path}"
    with open(sanitizer_path, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", "Sanitizer must be a compiled executable"


def test_adversarial_corpus():
    """Test the sanitizer against the clean and evil corpora."""
    sanitizer_path = "/home/user/loc_sanitizer"
    clean_dir = "/app/corpus/clean/"
    evil_dir = "/app/corpus/evil/"

    assert os.path.isfile(sanitizer_path), "Sanitizer executable not found."

    clean_files = glob.glob(os.path.join(clean_dir, "*.csv"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.csv"))

    assert len(clean_files) > 0, "No clean files found."
    assert len(evil_files) > 0, "No evil files found."

    failed_clean = []
    for f in clean_files:
        result = run_sanitizer(f)
        if result.returncode != 0:
            failed_clean.append(os.path.basename(f))

    failed_evil = []
    for f in evil_files:
        result = run_sanitizer(f)
        if result.returncode == 0:
            failed_evil.append(os.path.basename(f))

    errors = []
    if failed_clean:
        errors.append(f"{len(failed_clean)} of {len(clean_files)} clean files modified/rejected: {', '.join(failed_clean)}")
    if failed_evil:
        errors.append(f"{len(failed_evil)} of {len(evil_files)} evil files bypassed: {', '.join(failed_evil)}")

    assert not errors, " | ".join(errors)


def test_generated_csv_inputs_on_unpredictable_paths():
    """Exercise CSV parsing and template validation without corpus path labels."""
    header = "string_id,language_code,translation_text\n"
    token_a = "field_" + secrets.token_hex(8)
    token_b = "field_" + secrets.token_hex(8)

    valid_multiline = (
        header
        + csv_record("row_" + secrets.token_hex(4), "en", f"First line\nSecond line with {{{{{token_a}}}}}")
        + csv_record("row_" + secrets.token_hex(4), "fr", "A later row with no variables")
    )
    valid_escaped_csv = (
        header
        + csv_record(
            "row_" + secrets.token_hex(4),
            "en",
            f'Comma, embedded quote "quoted", and newline\nwith {{{{{token_b}}}}}',
        )
        + csv_record("row_" + secrets.token_hex(4), "de", f"Another {{{{{token_a}}}}} value")
    )

    cases = [
        (valid_multiline, True, "valid multiline CSV"),
        (valid_escaped_csv, True, "valid escaped CSV"),
        (header + csv_record("r1", "en", f"line one\nline two [[{token_a}]]"), False, "square-bracket variable"),
        (header + csv_record("r2", "en", f"line one\nline two <{token_a}>"), False, "angle-bracket variable"),
        (header + csv_record("r3", "en", f"line one\nline two {{{token_a}}}"), False, "single-curly variable"),
        (header + csv_record("r4", "en", f"line one\nline two {{{{{token_a}}}"), False, "unclosed template variable"),
        (
            header
            + csv_record("r5", "en", f"valid first row\nwith {{{{{token_a}}}}}")
            + csv_record("r6", "en", f"invalid later row [[{token_b}]]"),
            False,
            "invalid variable after multiline row",
        ),
        (header + 'r7,en,"an unclosed multiline field\nwith more text\n', False, "unclosed CSV quote"),
        (header + 'r8,en,"valid text",unexpected_column\n', False, "extra CSV column"),
        (header + 'r9,en\n', False, "missing CSV column"),
    ]

    secrets.SystemRandom().shuffle(cases)
    failures = []
    with tempfile.TemporaryDirectory(prefix="loccheck_") as directory:
        for contents, should_accept, description in cases:
            path = os.path.join(directory, secrets.token_hex(12) + ".csv")
            with open(path, "w", encoding="utf-8", newline="") as generated:
                generated.write(contents)

            result = run_sanitizer(path)
            accepted = result.returncode == 0
            if accepted != should_accept:
                failures.append(
                    f"{description}: expected {'acceptance' if should_accept else 'rejection'}, "
                    f"got exit code {result.returncode}"
                )

    assert not failures, " | ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
