#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import hashlib
import io
import os
import re
import subprocess
import tarfile
import time
import zipfile

import pytest

C_FILE = "/home/user/merger.c"
MERGED_FILE = "/home/user/repo/merged.tar.gz"
ARTIFACT_FILE = "/home/user/repo/artifact.bin"
REPORT_FILE = "/home/user/curation_report.txt"
CHUNKS = [
    "/home/user/repo/blob.parta",
    "/home/user/repo/blob.partb",
]
EXPECTED_CONTENT = b"CRITICAL_ARTIFACT_DATA_V1\n"
EXPECTED_HASH = "f3411e809311029e0de55bba20bce32ba71ab73cebc4eb03eb0cd7631ccca17a"


@pytest.fixture(scope="session")
def merger_binary(tmp_path_factory):
    assert os.path.isfile(C_FILE), f"File {C_FILE} does not exist."

    with open(C_FILE, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "flock" in content, f"{C_FILE} does not contain 'flock'."
    assert "LOCK_EX" in content, f"{C_FILE} does not contain 'LOCK_EX'."

    binary = tmp_path_factory.mktemp("build") / "merger"
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", C_FILE, "-o", str(binary)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"merger.c failed to compile:\n{result.stderr}"

    nm_output = subprocess.check_output(["nm", "-u", str(binary)], text=True)
    assert re.search(r"\bflock(?:@|\s|$)", nm_output), \
        "The compiled merger does not call POSIX flock()."
    return str(binary)


def test_merger_c_exists_and_contains_flock(merger_binary):
    assert os.path.isfile(C_FILE), f"File {C_FILE} does not exist."
    assert os.path.isfile(merger_binary)


def test_compiled_merger_concatenates_inputs_in_order(merger_binary, tmp_path):
    first = os.urandom(8193) + b"first-end"
    second = b"second-start" + os.urandom(5007)
    third = os.urandom(311)
    inputs = []
    for index, data in enumerate((first, second, third)):
        path = tmp_path / f"chunk-{index}"
        path.write_bytes(data)
        inputs.append(str(path))

    output = tmp_path / "output.bin"
    output.write_bytes(b"stale data that must not remain")
    result = subprocess.run(
        [merger_binary, str(output), *inputs],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    assert output.read_bytes() == first + second + third

    bad = subprocess.run(
        [merger_binary, str(tmp_path / "bad-output"), str(tmp_path / "missing-input")],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert bad.returncode != 0, "The merger reported success for a missing input file."


def test_merger_takes_exclusive_lock_before_modifying_output(merger_binary, tmp_path):
    part_a = tmp_path / "a"
    part_b = tmp_path / "b"
    part_a.write_bytes(os.urandom(2048))
    part_b.write_bytes(os.urandom(1024))
    expected = part_a.read_bytes() + part_b.read_bytes()

    output = tmp_path / "locked-output"
    sentinel = b"OUTPUT_MUST_NOT_CHANGE_BEFORE_EXCLUSIVE_LOCK"
    output.write_bytes(sentinel)

    lock_fd = os.open(output, os.O_RDWR)
    proc = None
    try:
        # A shared lock permits another shared lock but blocks the required LOCK_EX.
        fcntl.flock(lock_fd, fcntl.LOCK_SH)
        proc = subprocess.Popen(
            [merger_binary, str(output), str(part_a), str(part_b)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            close_fds=True,
        )
        time.sleep(0.5)
        assert proc.poll() is None, \
            "The merger did not wait for an exclusive output-file lock."
        assert output.read_bytes() == sentinel, \
            "The merger modified or truncated the output before acquiring LOCK_EX."

        fcntl.flock(lock_fd, fcntl.LOCK_UN)
        stdout, stderr = proc.communicate(timeout=10)
        assert proc.returncode == 0, stderr.decode(errors="replace")
        assert output.read_bytes() == expected
    finally:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
        finally:
            os.close(lock_fd)
        if proc is not None and proc.poll() is None:
            proc.kill()
            proc.wait()


def test_merged_tar_exists_and_matches_chunks(merger_binary, tmp_path):
    assert os.path.isfile(MERGED_FILE), f"File {MERGED_FILE} does not exist."
    expected_merged = b"".join(open(path, "rb").read() for path in CHUNKS)
    with open(MERGED_FILE, "rb") as f:
        submitted_merged = f.read()
    assert submitted_merged == expected_merged, \
        "merged.tar.gz is not the ordered concatenation of blob.parta and blob.partb."

    # Execute the submitted C implementation on copies of the real chunks too.
    copied_chunks = []
    for index, source in enumerate(CHUNKS):
        destination = tmp_path / f"real-chunk-{index}"
        with open(source, "rb") as f:
            destination.write_bytes(f.read())
        copied_chunks.append(str(destination))
    rebuilt = tmp_path / "rebuilt.tar.gz"
    result = subprocess.run(
        [merger_binary, str(rebuilt), *copied_chunks],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    assert rebuilt.read_bytes() == expected_merged


def test_nested_archives_and_artifact_integrity():
    expected_merged = b"".join(open(path, "rb").read() for path in CHUNKS)
    with tarfile.open(fileobj=io.BytesIO(expected_merged), mode="r:gz") as outer:
        member = outer.getmember("inner.zip")
        extracted = outer.extractfile(member)
        assert extracted is not None
        inner_bytes = extracted.read()

    with zipfile.ZipFile(io.BytesIO(inner_bytes), mode="r") as inner:
        assert inner.testzip() is None, "inner.zip failed its CRC integrity test."
        nested_artifact = inner.read("artifact.bin")

    assert os.path.isfile(ARTIFACT_FILE), f"File {ARTIFACT_FILE} does not exist."
    with open(ARTIFACT_FILE, "rb") as f:
        content = f.read()

    # Preserve the original fixed-content assertion and also tie the result to the archives.
    assert content == EXPECTED_CONTENT, \
        f"Contents of {ARTIFACT_FILE} do not match the expected data."
    assert content == nested_artifact, \
        "The extracted artifact.bin does not match artifact.bin inside inner.zip."


def test_curation_report():
    assert os.path.isfile(REPORT_FILE), f"File {REPORT_FILE} does not exist."
    with open(ARTIFACT_FILE, "rb") as f:
        derived_hash = hashlib.sha256(f.read()).hexdigest()
    assert derived_hash == EXPECTED_HASH

    expected_line = f"Artifact SHA256: {EXPECTED_HASH}"
    with open(REPORT_FILE, "r") as f:
        raw_content = f.read()

    # Preserve the original comparison, then enforce exactly one report line.
    assert raw_content.strip() == expected_line, \
        f"Contents of {REPORT_FILE} are incorrect. Expected '{expected_line}', got '{raw_content.strip()}'."
    assert raw_content in (expected_line, expected_line + "\n"), \
        "curation_report.txt must contain exactly the required single line."
    assert raw_content.rstrip("\n") == f"Artifact SHA256: {derived_hash}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
