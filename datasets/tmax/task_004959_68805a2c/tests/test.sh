#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest


def test_artifact_report_exists():
    """Check that the artifact_report.csv file was created."""
    report_path = '/home/user/artifact_report.csv'
    assert os.path.exists(report_path), f"Missing required file: {report_path}"
    assert os.path.isfile(report_path), f"Path is not a file: {report_path}"


def test_artifact_report_contents():
    """Check that the artifact_report.csv file contains the correct sorted data."""
    report_path = '/home/user/artifact_report.csv'

    expected_lines = [
        "filename,version,description",
        "alpha.bin,1,Alpha_Component",
        "beta.bin,2,Beta_Module",
        "delta.bin,3,Delta_Core",
        "gamma.bin,1,Gamma_Service"
    ]

    with open(report_path, 'r', encoding='utf-8') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), (
        f"Report contains {len(actual_lines)} lines, expected {len(expected_lines)}"
    )

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Line {i+1} mismatch.\nExpected: '{expected}'\nActual: '{actual}'"
        )


def _write_artifact(path, magic, version, description):
    data = description.encode('ascii')
    path.write_bytes(magic + version.to_bytes(2, 'little') +
                     len(data).to_bytes(2, 'little') + data + b'\x91\x00\xfe')


def _captured_text(run_dir, input_path, stdout, stderr):
    chunks = [stdout, stderr]
    for path in run_dir.iterdir():
        if path == input_path or not path.is_file() or path.stat().st_size > 1024 * 1024:
            continue
        try:
            chunks.append(path.read_bytes())
        except OSError:
            pass
    return b'\n'.join(chunks).decode('utf-8', errors='replace')


def _exercise_mode(executable, cases, mode):
    for filename, magic, version, description in cases:
        with tempfile.TemporaryDirectory(prefix='parser-run-') as td:
            run_dir = Path(td)
            input_path = run_dir / filename
            _write_artifact(input_path, magic, version, description)
            output_path = run_dir / 'result.csv'

            if mode == 'absolute':
                argv = [str(executable), str(input_path)]
            elif mode == 'relative':
                argv = [str(executable), filename]
            elif mode == 'output':
                argv = [str(executable), str(input_path), str(output_path)]
            elif mode == 'noargs':
                argv = [str(executable)]
            else:
                raise AssertionError(mode)

            try:
                result = subprocess.run(argv, cwd=run_dir, stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE, timeout=5)
            except (OSError, subprocess.TimeoutExpired):
                return False

            text = _captured_text(run_dir, input_path, result.stdout, result.stderr)
            if magic == b'ARTI':
                if description not in text:
                    return False
                if re.search(r'(?<!\d)' + re.escape(str(version)) + r'(?!\d)', text) is None:
                    return False
            elif description in text:
                return False
    return True


def test_c_parser_was_written_compiled_and_parses_runtime_inputs():
    home = Path('/home/user')
    sources = [p for p in home.rglob('*.c') if p.is_file()]
    assert sources, "No C source file was written under /home/user"

    elf_files = []
    for path in home.rglob('*'):
        try:
            if path.is_file() and os.access(path, os.X_OK) and path.read_bytes()[:4] == b'\x7fELF':
                elf_files.append(path)
        except OSError:
            pass
    assert elf_files, "No compiled ELF executable was left under /home/user"

    nonce = secrets.token_hex(6)
    cases = [
        ('runtime_one.bin', b'ARTI', secrets.randbelow(50000) + 1000, 'Runtime_A_' + nonce),
        ('runtime_two.bin', b'ARTI', secrets.randbelow(50000) + 1000, 'Runtime_B_' + nonce),
        ('runtime_bad.bin', b'NOPE', secrets.randbelow(50000) + 1000, 'Must_Ignore_' + nonce),
    ]

    with tempfile.TemporaryDirectory(prefix='c-build-') as build:
        build = Path(build)
        compiled = []
        attempts = [[src] for src in sources]
        by_directory = {}
        for src in sources:
            by_directory.setdefault(src.parent, []).append(src)
        attempts.extend(group for group in by_directory.values() if len(group) > 1)

        for index, group in enumerate(attempts):
            output = build / ('candidate_' + str(index))
            try:
                result = subprocess.run(
                    ['gcc', '-std=c11', '-O2', '-o', str(output)] + [str(p) for p in group],
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
                )
            except (OSError, subprocess.TimeoutExpired):
                continue
            if result.returncode == 0 and output.exists():
                compiled.append(output)

        assert compiled, "The submitted C source could not be compiled"

        modes = ('absolute', 'relative', 'output', 'noargs')
        assert any(_exercise_mode(exe, cases, mode) for exe in compiled for mode in modes), (
            "The compiled C source did not parse fresh valid headers and ignore a fresh invalid-magic file"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
