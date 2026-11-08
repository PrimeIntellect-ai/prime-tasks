#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
from pathlib import Path
import pytest

def test_debug_report():
    report_path = "/home/user/debug_report.txt"
    assert os.path.isfile(report_path), f"Missing debug report: {report_path}"
    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {report_path}, got {len(lines)}"
    assert lines[0] == "liblegacy_parser.so.4", f"Incorrect shared library in debug report: {lines[0]}"
    assert lines[1] == "asset_8921.asset", f"Incorrect last processed asset in debug report: {lines[1]}"

def test_filter_script_adversarial_corpus():
    script_path = "/home/user/filter_assets.sh"
    assert os.path.isfile(script_path), f"Missing filter script: {script_path}"
    assert os.access(script_path, os.X_OK), f"Filter script is not executable: {script_path}"

    evil_dir = "/app/verifier_assets/evil"
    clean_dir = "/app/verifier_assets/clean"

    with tempfile.TemporaryDirectory() as evil_out, tempfile.TemporaryDirectory() as clean_out:
        # Run script on evil corpus
        result_evil = subprocess.run([script_path, evil_dir, evil_out], capture_output=True, text=True)
        assert result_evil.returncode == 0, f"Script failed on evil corpus: {result_evil.stderr}"

        # Run script on clean corpus
        result_clean = subprocess.run([script_path, clean_dir, clean_out], capture_output=True, text=True)
        assert result_clean.returncode == 0, f"Script failed on clean corpus: {result_clean.stderr}"

        evil_files = set(os.listdir(evil_dir))
        clean_files = set(os.listdir(clean_dir))

        evil_out_files = set(os.listdir(evil_out))
        clean_out_files = set(os.listdir(clean_out))

        bypassed_evil = evil_out_files.intersection(evil_files)
        if bypassed_evil:
            pytest.fail(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_evil)}")

        missing_clean = clean_files - clean_out_files
        if missing_clean:
            pytest.fail(f"{len(missing_clean)} of {len(clean_files)} clean modified/missing: {', '.join(missing_clean)}")

def test_filter_script_unseen_mixed_corpus():
    script_path = "/home/user/filter_assets.sh"

    core = Path("/app/build_state/core.dump").read_bytes()
    match = re.search(rb"\[\[\[MACRO[^\x00\r\n]*?\]\]\]", core)
    assert match is not None, "Could not derive malicious payload from core dump"
    payload = match.group(0)

    with tempfile.TemporaryDirectory(prefix="mixed_input_") as input_dir, tempfile.TemporaryDirectory(prefix="mixed_output_") as output_dir:
        input_path = Path(input_dir)
        expected = {}
        malicious_names = set()

        clean_bodies = [
            b"ordinary asset " + secrets.token_hex(12).encode(),
            b"prefix [[[MACRO_SAFE]]] suffix " + secrets.token_hex(10).encode(),
            b"brackets [[MACRO but no trigger " + secrets.token_hex(8).encode(),
            b"text ending with MACRO]]] " + secrets.token_hex(9).encode(),
            b"", 
            ("multiline\nclean\n" + secrets.token_hex(14)).encode(),
        ]
        for body in clean_bodies:
            name = f"clean_{secrets.token_hex(8)}.asset"
            data = body + b"\n"
            (input_path / name).write_bytes(data)
            expected[name] = data

        for index in range(5):
            name = f"suspect_{secrets.token_hex(8)}.asset"
            prefix = ("prefix-" + secrets.token_hex(5)).encode()
            suffix = ("-suffix-" + secrets.token_hex(6)).encode()
            if index % 2:
                data = payload + prefix + b"\n"
            else:
                data = prefix + payload + suffix + b"\n"
            (input_path / name).write_bytes(data)
            malicious_names.add(name)

        result = subprocess.run([script_path, input_dir, output_dir], capture_output=True, text=True)
        assert result.returncode == 0, f"Script failed on unseen mixed corpus: {result.stderr}"

        actual_names = set(os.listdir(output_dir))
        assert actual_names == set(expected), (
            f"Incorrect files in mixed output; expected {sorted(expected)}, got {sorted(actual_names)}"
        )
        assert actual_names.isdisjoint(malicious_names), "A malicious asset was copied"

        for name, original_data in expected.items():
            output_file = Path(output_dir) / name
            assert output_file.is_file(), f"Expected output is not a regular file: {name}"
            assert output_file.read_bytes() == original_data, f"Clean asset was modified: {name}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
