#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import stat
import struct
import subprocess
import tempfile

import pytest

HOME = "/home/user"
SOURCE = f"{HOME}/caf_extractor.c"
SCRIPT = f"{HOME}/process.sh"
REPO = f"{HOME}/repo.caf"
OUTPUT = f"{HOME}/output"


def rle_encode(data):
    encoded = bytearray()
    i = 0
    while i < len(data):
        count = 1
        while i + count < len(data) and data[i + count] == data[i] and count < 255:
            count += 1
        encoded.extend((count, data[i]))
        i += count
    return bytes(encoded)


def make_archive(entries):
    result = bytearray(b"CAF\x01")
    for path, data in entries:
        path_bytes = path.encode("ascii")
        assert len(path_bytes) <= 255
        compressed = rle_encode(data)
        result += struct.pack("<B", len(path_bytes))
        result += path_bytes
        result += struct.pack("<I", len(compressed))
        result += compressed
    return bytes(result)


def run_pipeline(timeout=20):
    return subprocess.run(
        ["/bin/bash", SCRIPT],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )


@pytest.fixture(scope="session", autouse=True)
def execute_submitted_pipeline():
    for path in (SOURCE, SCRIPT):
        info = os.lstat(path)
        assert stat.S_ISREG(info.st_mode), f"Expected {path} to be a regular file."

    csv_content = b"id,artifact_name,checksum\n1,kernel_mod,a1b2c3d4\n2,libssl_custom,f9e8d7c6\n"
    binary_content = b"\x00\x00\x00\x00\xFF\xFF\xFF\xFF" * 10
    archive = make_archive([
        ("artifacts.csv", csv_content),
        ("../secret_overwrite.txt", b"YOU HAVE BEEN HACKED!"),
        ("binary.bin", binary_content),
    ])
    with open(REPO, "wb") as f:
        f.write(archive)
    with open(f"{HOME}/secret_overwrite.txt", "w") as f:
        f.write("SAFE")
    shutil.rmtree(OUTPUT, ignore_errors=True)

    result = run_pipeline()
    assert result.returncode == 0, (
        f"{SCRIPT} failed with exit status {result.returncode}.\n"
        f"stdout: {result.stdout!r}\nstderr: {result.stderr!r}"
    )
    warning = "WARNING: Skipped malicious path: ../secret_overwrite.txt"
    assert warning in result.stderr.decode("utf-8", errors="replace").splitlines()


def test_artifacts_csv_extracted():
    path = "/home/user/output/artifacts.csv"
    assert os.path.isfile(path), f"Expected extracted file {path} does not exist."
    with open(path, "rb") as f:
        content = f.read()
    expected = b"id,artifact_name,checksum\n1,kernel_mod,a1b2c3d4\n2,libssl_custom,f9e8d7c6\n"
    assert content == expected, f"{path} content does not match the expected decompressed payload."


def test_binary_bin_extracted():
    path = "/home/user/output/binary.bin"
    assert os.path.isfile(path), f"Expected extracted file {path} does not exist."
    with open(path, "rb") as f:
        content = f.read()
    expected = b"\x00\x00\x00\x00\xFF\xFF\xFF\xFF" * 10
    assert content == expected, f"{path} content does not match the expected decompressed payload."


def test_malicious_file_not_extracted():
    path = "/home/user/secret_overwrite.txt"
    assert os.path.isfile(path), f"{path} is missing, it should have been left intact."
    with open(path, "r") as f:
        content = f.read()
    assert content == "SAFE", f"Directory traversal attack succeeded! {path} was overwritten."


def test_summary_json_content():
    path = "/home/user/output/summary.json"
    assert os.path.isfile(path), f"JSON output file {path} does not exist."

    with open(path, "r") as f:
        raw_content = f.read()

    try:
        parsed = json.loads(raw_content)
    except json.JSONDecodeError:
        assert False, f"{path} does not contain valid JSON."

    expected_parsed = [
        {
            "id": "1",
            "artifact_name": "kernel_mod",
            "checksum": "a1b2c3d4"
        },
        {
            "id": "2",
            "artifact_name": "libssl_custom",
            "checksum": "f9e8d7c6"
        }
    ]

    assert parsed == expected_parsed, f"The parsed JSON in {path} does not match the expected structure and values."

    expected_exact = '[\n  {\n    "id": "1",\n    "artifact_name": "kernel_mod",\n    "checksum": "a1b2c3d4"\n  },\n  {\n    "id": "2",\n    "artifact_name": "libssl_custom",\n    "checksum": "f9e8d7c6"\n  }\n]'
    assert raw_content.strip() == expected_exact.strip(), f"The JSON in {path} is correct but does not match the exact expected whitespace/formatting."


def test_pipeline_on_fresh_archive():
    token = secrets.token_hex(8)
    rows = [
        {"id": "17", "artifact_name": f"module_{token}", "checksum": secrets.token_hex(7)},
        {"id": "29", "artifact_name": f"library_{token}", "checksum": secrets.token_hex(9)},
    ]
    csv_data = (
        "id,artifact_name,checksum\n"
        + "".join(f"{r['id']},{r['artifact_name']},{r['checksum']}\n" for r in rows)
    ).encode("ascii")
    blob_name = f"blob_{token}.bin"
    blob_data = os.urandom(97) + b"Z" * 300 + os.urandom(31)
    relative_guard = f"dynamic_guard_{token}"
    relative_guard_path = f"{HOME}/{relative_guard}"
    absolute_guard_path = f"/tmp/caf_absolute_guard_{token}"

    with open(relative_guard_path, "wb") as f:
        f.write(b"RELATIVE SAFE")
    if os.path.exists(absolute_guard_path):
        os.unlink(absolute_guard_path)

    with open(REPO, "wb") as f:
        f.write(make_archive([
            ("artifacts.csv", csv_data),
            (blob_name, blob_data),
            (f"../{relative_guard}", b"RELATIVE ATTACK"),
            (absolute_guard_path, b"ABSOLUTE ATTACK"),
        ]))
    shutil.rmtree(OUTPUT, ignore_errors=True)

    result = run_pipeline()
    assert result.returncode == 0, result.stderr.decode("utf-8", errors="replace")
    stderr_lines = result.stderr.decode("utf-8", errors="replace").splitlines()
    assert f"WARNING: Skipped malicious path: ../{relative_guard}" in stderr_lines
    assert f"WARNING: Skipped malicious path: {absolute_guard_path}" in stderr_lines

    with open(f"{OUTPUT}/artifacts.csv", "rb") as f:
        assert f.read() == csv_data
    with open(f"{OUTPUT}/{blob_name}", "rb") as f:
        assert f.read() == blob_data
    with open(relative_guard_path, "rb") as f:
        assert f.read() == b"RELATIVE SAFE"
    assert not os.path.exists(absolute_guard_path)

    with open(f"{OUTPUT}/summary.json", "r") as f:
        raw_summary = f.read()
    assert raw_summary.strip() == json.dumps(rows, indent=2).strip()


def test_compiled_extractor_on_independent_archive():
    token = secrets.token_hex(8)
    with tempfile.TemporaryDirectory(prefix="caf-verifier-") as tempdir:
        executable = os.path.join(tempdir, "caf_extractor")
        compile_result = subprocess.run(
            ["/usr/bin/gcc", SOURCE, "-o", executable],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
            check=False,
        )
        assert compile_result.returncode == 0, compile_result.stderr.decode("utf-8", errors="replace")

        workdir = os.path.join(tempdir, "work")
        os.mkdir(workdir)
        valid_name = f"random_{token}.dat"
        valid_data = os.urandom(64) + b"A" * 600 + b"\x00" * 260 + os.urandom(53)
        parent_guard = os.path.join(tempdir, f"guard_{token}")
        with open(parent_guard, "wb") as f:
            f.write(b"UNCHANGED")
        absolute_guard = f"/tmp/caf_extractor_guard_{token}"
        if os.path.exists(absolute_guard):
            os.unlink(absolute_guard)

        archive = make_archive([
            (valid_name, valid_data),
            (f"../guard_{token}", b"TRAVERSAL"),
            (absolute_guard, b"ABSOLUTE"),
        ])
        result = subprocess.run(
            [executable],
            cwd=workdir,
            input=archive,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
            check=False,
        )
        assert result.returncode == 0, result.stderr.decode("utf-8", errors="replace")
        with open(os.path.join(workdir, valid_name), "rb") as f:
            assert f.read() == valid_data
        with open(parent_guard, "rb") as f:
            assert f.read() == b"UNCHANGED"
        assert not os.path.exists(absolute_guard)

        stderr_lines = result.stderr.decode("utf-8", errors="replace").splitlines()
        assert f"WARNING: Skipped malicious path: ../guard_{token}" in stderr_lines
        assert f"WARNING: Skipped malicious path: {absolute_guard}" in stderr_lines
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
