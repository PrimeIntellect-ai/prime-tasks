#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess
import tempfile


def test_flag_txt_content():
    flag_path = "/home/user/recovery/flag.txt"
    assert os.path.isfile(flag_path), f"File {flag_path} does not exist. Did you extract the flag?"

    with open(flag_path, "rb") as f:
        content = f.read()

    expected_flag = b"FLAG{w4l_p4rs3}"
    assert content == expected_flag, f"Content of {flag_path} is incorrect. Expected {expected_flag!r}, got {content!r}"


def test_zip_slip_fix():
    malicious_path_outside = "/home/user/malicious.txt"
    assert not os.path.exists(malicious_path_outside), f"File {malicious_path_outside} exists. The Zip Slip vulnerability was not properly fixed."


def test_extracted_files():
    malicious_path_inside = "/home/user/recovery/malicious.txt"
    wal_path = "/home/user/recovery/database.wal"

    assert os.path.isfile(malicious_path_inside), f"File {malicious_path_inside} does not exist. The malicious file was not extracted to the recovery directory using its base name."
    assert os.path.isfile(wal_path), f"File {wal_path} does not exist. The database.wal file was not extracted."


def test_modified_extractor_enforces_basename_extraction():
    source = "/home/user/extractor.c"
    assert os.path.isfile(source), f"Extractor source {source} does not exist"

    with tempfile.TemporaryDirectory(prefix="extractor-verifier-") as root:
        executable = os.path.join(root, "extractor")
        subprocess.run(
            ["gcc", "-std=c11", "-O2", source, "-o", executable],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )

        recovery = os.path.join(root, "recovery")
        os.mkdir(recovery)
        token = secrets.token_hex(12)
        traversal_base = f"escaped_{token}.bin"
        nested_base = f"nested_{token}.bin"
        absolute_base = f"absolute_{token}.bin"
        plain_base = f"plain_{token}.bin"

        traversal_target = os.path.join(root, traversal_base)
        absolute_target = os.path.join(root, absolute_base)
        entries = [
            (f"../{traversal_base}", secrets.token_bytes(37)),
            (f"missing/subdirectory/{nested_base}", secrets.token_bytes(41)),
            (absolute_target, secrets.token_bytes(43)),
            (plain_base, secrets.token_bytes(47)),
        ]

        archive = os.path.join(root, "challenge.cba")
        with open(archive, "wb") as f:
            f.write(struct.pack("<II", 0x43424143, len(entries)))
            for name, payload in entries:
                encoded = name.encode("utf-8")
                assert len(encoded) < 256
                f.write(encoded.ljust(256, b"\0"))
                f.write(struct.pack("<I", len(payload)))
                f.write(payload)

        result = subprocess.run(
            [executable, archive],
            cwd=recovery,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert result.returncode == 0, f"Compiled extractor failed with exit code {result.returncode}: {result.stderr!r}"

        for name, payload in entries:
            basename = os.path.basename(name)
            output = os.path.join(recovery, basename)
            assert os.path.isfile(output), f"Extractor did not create basename-only output {output}"
            with open(output, "rb") as f:
                assert f.read() == payload, f"Extractor wrote incorrect data for {basename}"

        assert not os.path.exists(traversal_target), "Extractor followed a ../ traversal path outside the recovery directory"
        assert not os.path.exists(absolute_target), "Extractor followed an absolute archive path outside the recovery directory"
        assert set(os.listdir(recovery)) == {os.path.basename(name) for name, _ in entries}, "Extractor created paths other than the required basename-only outputs"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
