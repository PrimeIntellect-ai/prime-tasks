#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import stat
import subprocess
import tempfile

import pytest


def test_detector_exists_and_executable():
    detector_path = "/home/user/detector.sh"
    assert os.path.isfile(detector_path), f"Detector script missing: {detector_path}"
    assert os.access(detector_path, os.X_OK), f"Detector script is not executable: {detector_path}"


def test_adversarial_corpus():
    detector_path = "/home/user/detector.sh"
    clean_dir = "/home/user/corpora/clean"
    evil_dir = "/home/user/corpora/evil"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    clean_failed = []
    evil_failed = []

    # Test clean corpus
    for cf in clean_files:
        result = subprocess.run([detector_path, cf], capture_output=True)
        if result.returncode != 0:
            clean_failed.append(os.path.basename(cf))

    # Test evil corpus
    for ef in evil_files:
        result = subprocess.run([detector_path, ef], capture_output=True)
        if result.returncode != 1:
            evil_failed.append(os.path.basename(ef))

    error_messages = []
    if clean_failed:
        error_messages.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    if evil_failed:
        error_messages.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")

    assert not error_messages, " | ".join(error_messages)


def test_confparser_is_fixed_and_reshapes_json_lines():
    parser_path = "/app/confparser-1.0.0/confparser.py"
    assert os.path.isfile(parser_path), f"Vendored parser missing: {parser_path}"

    section_a = "database_" + secrets.token_hex(6)
    section_b = "api_" + secrets.token_hex(6)
    key_a = "host_" + secrets.token_hex(5)
    key_b = "retry_" + secrets.token_hex(5)

    with tempfile.TemporaryDirectory(prefix="confparser_probe_") as td:
        input_path = os.path.join(td, secrets.token_hex(8) + ".cfg")
        with open(input_path, "w", encoding="utf-8") as f:
            f.write(f"[{section_a}]\n{key_a} = localhost value\n")
            f.write("this line is ignored\n\n")
            f.write(f"[{section_b}]\n{key_b}=true=with_equals\n")

        result = subprocess.run(
            ["python3", parser_path, input_path],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, result.stderr
        lines = [line for line in result.stdout.splitlines() if line.strip()]
        assert len(lines) == 2, result.stdout
        parsed = [json.loads(line) for line in lines]
        assert parsed == [
            {"section": section_a, "key": key_a, "value": "localhost value"},
            {"section": section_b, "key": key_b, "value": "true=with_equals"},
        ]


def _write_config(path, records):
    current = None
    with open(path, "w", encoding="utf-8") as f:
        for section, key, value in records:
            if section != current:
                f.write(f"[{section}]\n")
                current = section
            f.write(f"{key}={value}\n")


def _has_duplicate(records):
    seen = set()
    for section, key, _ in records:
        pair = (section, key)
        if pair in seen:
            return True
        seen.add(pair)
    return False


def test_randomized_detector_and_parser_orchestration():
    detector_path = "/home/user/detector.sh"
    parser_path = "/app/confparser-1.0.0/confparser.py"
    parser_backup = "/app/confparser-1.0.0/.confparser.verifier-backup.py"

    assert os.path.isfile(detector_path)
    assert os.access(detector_path, os.X_OK)
    assert os.path.isfile(parser_path)
    assert not os.path.exists(parser_backup)

    with tempfile.TemporaryDirectory(prefix="detector_random_" ) as td:
        marker = os.path.join(td, "parser-invocations-" + secrets.token_hex(8))
        cases = []

        for index in range(12):
            section_one = "sec_" + secrets.token_hex(8)
            section_two = "sec_" + secrets.token_hex(8)
            shared_key = "key_" + secrets.token_hex(8)
            other_key = "key_" + secrets.token_hex(8)
            records = [
                (section_one, shared_key, "first_" + secrets.token_hex(4)),
                (section_one, other_key, "value with spaces " + secrets.token_hex(3)),
            ]
            if index % 2:
                records.append((section_one, shared_key, "duplicate_" + secrets.token_hex(4)))
            records.extend([
                (section_two, shared_key, "allowed_in_other_section_" + secrets.token_hex(4)),
                (section_two, "tail_" + secrets.token_hex(6), "x=y=" + secrets.token_hex(3)),
            ])

            path = os.path.join(td, secrets.token_hex(12) + ".input")
            _write_config(path, records)
            cases.append((path, 1 if _has_duplicate(records) else 0))

        shutil.copy2(parser_path, parser_backup)
        wrapper = (
            "import os, sys\n"
            f"with open({marker!r}, 'a', encoding='utf-8') as marker_file:\n"
            "    marker_file.write('called\\n')\n"
            f"os.execv(sys.executable, [sys.executable, {parser_backup!r}] + sys.argv[1:])\n"
        )

        try:
            with open(parser_path, "w", encoding="utf-8") as f:
                f.write(wrapper)
            os.chmod(parser_path, stat.S_IMODE(os.stat(parser_backup).st_mode))

            failures = []
            for path, expected in cases:
                result = subprocess.run(
                    [detector_path, path],
                    capture_output=True,
                    text=True,
                    timeout=10,
                )
                if result.returncode != expected:
                    failures.append(
                        f"{os.path.basename(path)} expected {expected}, got {result.returncode}; "
                        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
                    )

            assert not failures, " | ".join(failures)
            assert os.path.isfile(marker), "detector.sh did not run the vendored confparser.py"
            with open(marker, encoding="utf-8") as f:
                invocations = sum(1 for line in f if line.strip() == "called")
            assert invocations >= len(cases), (
                f"detector.sh invoked confparser.py only {invocations} times for {len(cases)} inputs"
            )
        finally:
            if os.path.exists(parser_backup):
                os.replace(parser_backup, parser_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
