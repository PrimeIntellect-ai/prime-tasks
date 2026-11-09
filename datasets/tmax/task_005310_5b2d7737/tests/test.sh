#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess
import tempfile


def test_extractor_cpp_exists():
    assert os.path.isfile("/home/user/extractor.cpp"), "The C++ source file /home/user/extractor.cpp is missing."


def test_extractor_executable_exists():
    assert os.path.isfile("/home/user/extractor"), "The compiled executable /home/user/extractor is missing."
    assert os.access("/home/user/extractor", os.X_OK), "The file /home/user/extractor is not executable."


def _run_extractor(path, data, args=None):
    result = subprocess.run(
        [path] + (args or []),
        input=data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert result.returncode == 0, f"{path} exited with status {result.returncode}: {result.stderr!r}"
    return result.stdout


def test_source_compiles_and_both_extractors_work():
    with open("/home/user/extractor", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/extractor is not a compiled executable."

    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt = os.path.join(tmpdir, "extractor_from_source")
        compile_result = subprocess.run(
            ["g++", "-std=c++17", "-O2", "/home/user/extractor.cpp", "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert compile_result.returncode == 0, (
            "The submitted C++ source does not compile: " + compile_result.stderr.decode(errors="replace")
        )

        cases = [
            (b"", b"INVALID\n"),
            (b"A", b"INVALID\n"),
            (b"ART", b"INVALID\n"),
            (b"ARTF", b"INVALID\n"),
            (b"ARTF\x01\x00\x00", b"INVALID\n"),
            (b"NOPE" + struct.pack("<I", 3) + b"abc", b"INVALID\n"),
            (b"ARTF" + struct.pack("<I", 0), b"\n"),
            (b"ARTF" + struct.pack("<I", 4) + b"\x00\x7f\x80\xff", b"007F80FF\n"),
            (b"ARTF" + struct.pack("<I", 5) + b"abcd", b"INVALID\n"),
            (b"ARTF" + struct.pack("<I", 0xFFFFFFFF) + b"short", b"INVALID\n"),
        ]

        for _ in range(12):
            payload = secrets.token_bytes(secrets.randbelow(128))
            trailing = secrets.token_bytes(secrets.randbelow(16))
            cases.append((
                b"ARTF" + struct.pack("<I", len(payload)) + payload + trailing,
                payload.hex().upper().encode() + b"\n",
            ))

            declared = secrets.randbelow(128) + 1
            available = secrets.randbelow(declared)
            cases.append((
                b"ARTF" + struct.pack("<I", declared) + secrets.token_bytes(available),
                b"INVALID\n",
            ))

            bad_magic = bytearray(secrets.token_bytes(4))
            if bytes(bad_magic) == b"ARTF":
                bad_magic[0] ^= 1
            cases.append((
                bytes(bad_magic) + struct.pack("<I", 2) + secrets.token_bytes(2),
                b"INVALID\n",
            ))

        for executable in ("/home/user/extractor", rebuilt):
            for data, expected in cases:
                actual = _run_extractor(executable, data)
                assert actual == expected, (
                    f"{executable} produced {actual!r} for input {data!r}; expected {expected!r}"
                )


def test_curation_report_exists_and_correct():
    report_path = "/home/user/curation_report.txt"
    assert os.path.isfile(report_path), f"The report file {report_path} is missing."

    expected_lines = [
        "/home/user/artifacts/alpha.bin - 0102030405060708090A",
        "/home/user/artifacts/beta.bin - INVALID",
        "/home/user/artifacts/epsilon.bin - INVALID",
        "/home/user/artifacts/zeta.bin - DEADBEEFCAFEBABE"
    ]

    with open(report_path, "r") as f:
        content = f.read().strip().splitlines()

    assert len(content) == len(expected_lines), f"Expected {len(expected_lines)} lines in the report, but found {len(content)}."

    for i, (actual, expected) in enumerate(zip(content, expected_lines)):
        assert actual.strip() == expected, f"Line {i+1} mismatch. Expected: '{expected}', Got: '{actual.strip()}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
