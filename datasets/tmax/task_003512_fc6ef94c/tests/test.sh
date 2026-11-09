#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import shutil
import stat
import subprocess
import tempfile


def test_extracted_files_content():
    extracted_dir = "/home/user/extracted"
    assert os.path.exists(extracted_dir), f"Directory {extracted_dir} does not exist."
    assert os.path.isdir(extracted_dir), f"Path {extracted_dir} is not a directory."

    expected_files = {
        "alpha.bin": bytes([0x0A, 0x0B, 0xFF, 0xFF, 0xFF, 0x0C, 0x00, 0x00, 0x00, 0x00, 0x0D, 0xFF, 0xFF, 0xFF]),
        "beta.bin": bytes([0xFF, 0xAA, 0xFF, 0xFF, 0xFF, 0xBB, 0x00, 0x00, 0xCC]),
        "gamma.bin": bytes([0x11, 0x22, 0x33, 0x44, 0x55])
    }

    for fname, expected_bytes in expected_files.items():
        file_path = os.path.join(extracted_dir, fname)
        assert os.path.exists(file_path), f"Extracted file {file_path} is missing."
        assert os.path.isfile(file_path), f"Path {file_path} is not a file."

        with open(file_path, "rb") as f:
            actual_bytes = f.read()

        assert actual_bytes == expected_bytes, f"Content of {file_path} is incorrect. Expected {expected_bytes.hex()}, got {actual_bytes.hex()}."


def test_manifest_file_content():
    manifest_path = "/home/user/manifest.txt"
    assert os.path.exists(manifest_path), f"Manifest file {manifest_path} is missing."
    assert os.path.isfile(manifest_path), f"Path {manifest_path} is not a file."

    expected_manifest_lines = [
        "8f36cfae2e8e3d085938d8d4ec08dfeb0de8f51a4461bb3bc5e933e4b752496a  alpha.bin",
        "a15a818c99f935f8d6d84ce5a59f5188828b6d37012678f5f64d084c8a16fa9c  beta.bin",
        "08b534608c02452c6f1cd0b8c667a4d5218d6e3c0429df92a3d76e3381e4b868  gamma.bin"
    ]

    with open(manifest_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_manifest_lines, f"Manifest content is incorrect. Expected:\n{chr(10).join(expected_manifest_lines)}\nGot:\n{chr(10).join(actual_lines)}"


def correct_exact_three(data):
    result = bytearray()
    i = 0
    while i < len(data):
        if data[i] != 0:
            result.append(data[i])
            i += 1
            continue
        j = i
        while j < len(data) and data[j] == 0:
            j += 1
        run_length = j - i
        result.extend(b"\xff\xff\xff" if run_length == 3 else b"\x00" * run_length)
        i = j
    return bytes(result)


def test_extractor_source_compiles_and_processes_fresh_archive():
    source = "/home/user/extractor.c"
    assert os.path.exists(source), f"Required C source {source} is missing."
    assert not os.path.islink(source), f"{source} must be a C source file, not a symbolic link."
    assert stat.S_ISREG(os.stat(source).st_mode), f"{source} is not a regular file."

    archive_path = "/home/user/artifacts.hexar"
    extracted_dir = "/home/user/extracted"
    manifest_path = "/home/user/manifest.txt"

    token = secrets.token_hex(6)
    entries = {
        f"mixed_{token}.bin": bytes([
            0x21, 0x00, 0x31,
            0x00, 0x00, 0x41,
            0x00, 0x00, 0x00, 0x51,
            0x00, 0x00, 0x00, 0x00, 0x61,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x71,
            0x00, 0x00, 0x00
        ]),
        f"edges_{token}.dat": bytes([
            0x00, 0x00, 0x00, 0x82,
            0x00, 0x00, 0x92,
            0x00, 0x00, 0x00, 0x00,
            0xA2, 0x00, 0x00, 0x00
        ]),
        f"plain_{token}.raw": bytes([0x13, 0x27, 0x3B, 0x4F, 0x63])
    }
    expected = {name: correct_exact_three(data) for name, data in entries.items()}

    original_archive = open(archive_path, "rb").read()
    original_manifest = open(manifest_path, "rb").read()

    with tempfile.TemporaryDirectory(prefix="extractor_test_") as temp_dir:
        executable = os.path.join(temp_dir, "extractor")
        extracted_backup = os.path.join(temp_dir, "extracted_backup")
        shutil.copytree(extracted_dir, extracted_backup)

        compile_result = subprocess.run(
            ["gcc", "-std=c11", "-O2", source, "-o", executable],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30
        )
        assert compile_result.returncode == 0, (
            "extractor.c failed to compile with gcc:\n" + compile_result.stderr
        )
        assert os.path.isfile(executable) and os.access(executable, os.X_OK), (
            "Compiling extractor.c did not produce an executable."
        )

        try:
            archive_lines = []
            for name, data in entries.items():
                archive_lines.append(f"=== FILE: {name} ===")
                hex_values = [f"{value:02X}" for value in data]
                for start in range(0, len(hex_values), 7):
                    archive_lines.append("  ".join(hex_values[start:start + 7]))
                archive_lines.append("=== END ===")
            with open(archive_path, "w", encoding="ascii") as archive:
                archive.write("\n".join(archive_lines) + "\n")

            shutil.rmtree(extracted_dir)
            if os.path.lexists(manifest_path):
                os.remove(manifest_path)

            run_result = subprocess.run(
                [executable],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30
            )
            assert run_result.returncode == 0, (
                f"Compiled extractor exited with status {run_result.returncode}.\n"
                f"stdout:\n{run_result.stdout}\nstderr:\n{run_result.stderr}"
            )
            assert os.path.isdir(extracted_dir), "Compiled extractor did not create /home/user/extracted."

            actual_names = sorted(
                name for name in os.listdir(extracted_dir)
                if os.path.isfile(os.path.join(extracted_dir, name))
            )
            assert actual_names == sorted(expected), (
                f"Extractor produced the wrong files for a fresh archive: {actual_names}"
            )
            for name, expected_bytes in expected.items():
                output_path = os.path.join(extracted_dir, name)
                with open(output_path, "rb") as output:
                    actual_bytes = output.read()
                assert actual_bytes == expected_bytes, (
                    f"Compiled extractor handled {name} incorrectly. "
                    f"Expected {expected_bytes.hex()}, got {actual_bytes.hex()}."
                )
        finally:
            with open(archive_path, "wb") as archive:
                archive.write(original_archive)
            if os.path.lexists(extracted_dir):
                if os.path.isdir(extracted_dir) and not os.path.islink(extracted_dir):
                    shutil.rmtree(extracted_dir)
                else:
                    os.remove(extracted_dir)
            shutil.copytree(extracted_backup, extracted_dir)
            with open(manifest_path, "wb") as manifest:
                manifest.write(original_manifest)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
