#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import itertools
import os
import re
import secrets
import subprocess
import time


def test_archive_decrypted_and_source_rewritten(tmp_path):
    source_path = "/home/user/redact.cpp"
    sample_path = "/home/user/sample.log"

    assert os.path.isfile(source_path), f"Extracted source not found: {source_path}"
    assert os.path.isfile(sample_path), f"Extracted sample log not found: {sample_path}"

    with open(sample_path, "r", encoding="utf-8") as f:
        sample = f.read()
    assert "1234-5678-9012-3456" in sample
    assert "1234 5678 9012 3456" in sample
    assert "1234567890123456" in sample

    with open(source_path, "r", encoding="utf-8") as f:
        source = f.read()
    assert not re.search(r"#\s*include\s*[<\"]regex[>\"]", source), \
        "redact.cpp still includes the regex library"
    assert "std::regex" not in source, "redact.cpp still uses std::regex"
    assert "regex_replace" not in source, "redact.cpp still uses regex_replace"

    rebuilt = tmp_path / "rebuilt_redactor"
    result = subprocess.run(
        ["g++", "-O2", "-std=c++17", source_path, "-o", str(rebuilt)],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Rewritten redact.cpp does not compile:\n{result.stderr}"

    digits = "".join(str(secrets.randbelow(10)) for _ in range(16))
    dashed = "-".join(digits[i:i+4] for i in range(0, 16, 4))
    spaced = " ".join(digits[i:i+4] for i in range(0, 16, 4))
    input_path = tmp_path / "source_check.log"
    output_path = tmp_path / "source_check.out"
    original = (
        f"dash={dashed}\n"
        f"space={spaced}\n"
        f"plain={digits}\n"
        "leave=1234-5678-9012\n"
    )
    expected = (
        "dash=[REDACTED]\n"
        "space=[REDACTED]\n"
        "plain=[REDACTED]\n"
        "leave=1234-5678-9012\n"
    )
    input_path.write_text(original, encoding="utf-8")
    run = subprocess.run([str(rebuilt), str(input_path), str(output_path)], capture_output=True, text=True)
    assert run.returncode == 0, f"Program rebuilt from redact.cpp failed:\n{run.stderr}"
    assert output_path.is_file(), "Program rebuilt from redact.cpp did not create output"
    assert output_path.read_text(encoding="utf-8") == expected


def test_sshd_config_hardened():
    config_path = "/home/user/sshd_config"
    assert os.path.isfile(config_path), f"File not found: {config_path}"

    with open(config_path, "r") as f:
        content = f.read()

    assert re.search(r"^\s*PermitRootLogin\s+no\b", content, re.MULTILINE), \
        "PermitRootLogin is not set to 'no' or is commented out."
    assert re.search(r"^\s*PasswordAuthentication\s+no\b", content, re.MULTILINE), \
        "PasswordAuthentication is not set to 'no' or is commented out."
    assert not re.search(r"^\s*PermitRootLogin\s+yes\b", content, re.MULTILINE), \
        "Found contradictory 'PermitRootLogin yes' in sshd_config."
    assert not re.search(r"^\s*PasswordAuthentication\s+yes\b", content, re.MULTILINE), \
        "Found contradictory 'PasswordAuthentication yes' in sshd_config."


def test_integrity_sha256():
    binary_path = "/home/user/redactor"
    hash_path = "/home/user/integrity.sha256"

    assert os.path.isfile(binary_path), f"Compiled binary not found: {binary_path}"
    assert os.path.isfile(hash_path), f"Checksum file not found: {hash_path}"
    assert os.access(binary_path, os.X_OK), f"Binary is not executable: {binary_path}"
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "redactor is not a compiled native ELF binary"

    sha256_hash = hashlib.sha256()
    with open(binary_path, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    actual_hash = sha256_hash.hexdigest()

    with open(hash_path, "r") as f:
        hash_content = f.read().strip()

    assert actual_hash in hash_content, \
        f"The SHA256 hash in {hash_path} does not match the actual hash of {binary_path}."


def test_redactor_performance_and_correctness(tmp_path):
    binary_path = "/home/user/redactor"
    assert os.path.isfile(binary_path), f"Compiled binary not found: {binary_path}"
    assert os.access(binary_path, os.X_OK), f"Binary is not executable: {binary_path}"
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "redactor is not a compiled native ELF binary"

    input_file = tmp_path / "hidden_test.log"
    output_file = tmp_path / "hidden_out.log"
    expected_file = tmp_path / "expected_hidden_out.log"

    test_cases = [
        ("User 1234-5678-9012-3456 logged in.", "User [REDACTED] logged in.\n"),
        ("Payment 1234 5678 9012 3456 processed.", "Payment [REDACTED] processed.\n"),
        ("Raw card 1234567890123456 found.", "Raw card [REDACTED] found.\n"),
        ("Normal log entry with numbers 1234 5678.", "Normal log entry with numbers 1234 5678.\n"),
        ("Short card 1234-5678-9012.", "Short card 1234-5678-9012.\n"),
    ]

    multiplier = 100000
    with open(input_file, "w") as fin:
        for _ in range(multiplier):
            for raw, _ in test_cases:
                fin.write(raw + "\n")

    start_time = time.time()
    result = subprocess.run([binary_path, str(input_file), str(output_file)], capture_output=True, text=True)
    elapsed_time = time.time() - start_time

    assert result.returncode == 0, f"Redactor failed with return code {result.returncode}\nStderr: {result.stderr}"
    assert os.path.isfile(output_file), "Redactor did not create the output file."

    # Create the expected file only after the submitted executable has exited.
    with open(expected_file, "w") as fexp:
        for _ in range(multiplier):
            for _, redacted in test_cases:
                fexp.write(redacted)

    sentinel = object()
    with open(output_file, "r") as fout, open(expected_file, "r") as fexp:
        for i, pair in enumerate(itertools.zip_longest(fout, fexp, fillvalue=sentinel), 1):
            out_line, exp_line = pair
            assert out_line is not sentinel, f"Output ended early at line {i}"
            assert exp_line is not sentinel, f"Output has unexpected extra data at line {i}"
            assert out_line == exp_line, f"Mismatch at line {i}:\nExpected: {exp_line}\nGot: {out_line}"

    threshold = 0.5
    assert elapsed_time <= threshold, \
        f"Execution time metric failed: took {elapsed_time:.3f} seconds, which is > threshold of {threshold} seconds."

    # Exercise unpredictable card values so a fixed-output implementation cannot pass.
    digits = "".join(str(secrets.randbelow(10)) for _ in range(16))
    dashed = "-".join(digits[i:i+4] for i in range(0, 16, 4))
    spaced = " ".join(digits[i:i+4] for i in range(0, 16, 4))
    random_input = tmp_path / "random.log"
    random_output = tmp_path / "random.out"
    random_input.write_text(
        f"A {dashed} Z\nB {spaced} Z\nC {digits} Z\nNo 1234-5678 Z\n",
        encoding="utf-8",
    )
    random_expected = "A [REDACTED] Z\nB [REDACTED] Z\nC [REDACTED] Z\nNo 1234-5678 Z\n"
    random_run = subprocess.run(
        [binary_path, str(random_input), str(random_output)], capture_output=True, text=True
    )
    assert random_run.returncode == 0, f"Redactor failed randomized test:\n{random_run.stderr}"
    assert random_output.is_file(), "Redactor did not create randomized output"
    assert random_output.read_text(encoding="utf-8") == random_expected
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
