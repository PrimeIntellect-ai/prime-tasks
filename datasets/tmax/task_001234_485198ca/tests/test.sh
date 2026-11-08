#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import io
import os
import random
import secrets
import subprocess
import tarfile
import tempfile

EXECUTABLE = "/home/user/audio_sanitizer"


def test_audio_transcription():
    secret_path = "/home/user/audio_secret.txt"
    assert os.path.isfile(secret_path), f"Transcription file {secret_path} is missing."

    with open(secret_path, "r") as f:
        content = f.read().strip()

    expected_text = "storage capacity reached"
    assert content == expected_text, f"Expected transcription '{expected_text}', got '{content}'"


def test_audio_sanitizer_validate():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"Executable {EXECUTABLE} is not executable."

    evil_dir = "/app/corpus/evil/"
    clean_dir = "/app/corpus/clean/"
    evil_files = glob.glob(os.path.join(evil_dir, "*.tar"))
    clean_files = glob.glob(os.path.join(clean_dir, "*.tar"))

    assert len(evil_files) > 0, f"No evil corpus files found in {evil_dir}."
    assert len(clean_files) > 0, f"No clean corpus files found in {clean_dir}."

    bypassed_evil = []
    for evil in evil_files:
        result = subprocess.run([EXECUTABLE, "validate", evil], capture_output=True)
        if result.returncode == 0:
            bypassed_evil.append(os.path.basename(evil))

    rejected_clean = []
    for clean in clean_files:
        result = subprocess.run([EXECUTABLE, "validate", clean], capture_output=True)
        if result.returncode != 0:
            rejected_clean.append(os.path.basename(clean))

    error_msgs = []
    if bypassed_evil:
        error_msgs.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_evil)}")
    if rejected_clean:
        error_msgs.append(f"{len(rejected_clean)} of {len(clean_files)} clean modified: {', '.join(rejected_clean)}")
    assert not error_msgs, "; ".join(error_msgs)


def test_audio_sanitizer_validate_generated_archives():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"Executable {EXECUTABLE} is not executable."

    def token():
        return secrets.token_hex(8)

    def regular(name, size=None):
        data = os.urandom(size if size is not None else secrets.randbelow(1400))
        return (name, tarfile.REGTYPE, data, "")

    def directory(name):
        return (name, tarfile.DIRTYPE, b"", "")

    def symlink(name, target):
        return (name, tarfile.SYMTYPE, b"", target)

    with tempfile.TemporaryDirectory() as tmpdir:
        cases = []

        for _ in range(7):
            base = token()
            cases.append((0, [
                directory(base + "/"),
                regular(base + "/" + token() + ".chunk"),
                regular(base + "/nested/" + token() + "..part"),
            ]))

        # Each malicious archive also has ordinary entries, including data spanning
        # tar blocks, so validation must inspect all headers rather than one position.
        for _ in range(3):
            cases.append((1, [regular(token() + ".bin", 900), regular(token() + "/../" + token(), 17)]))
        for _ in range(3):
            cases.append((1, [regular(token(), 33), regular(token() + "..\\" + token(), 700)]))
        for _ in range(3):
            cases.append((1, [regular(token(), 1100), regular("/" + token() + "/" + token(), 9)]))
        for _ in range(3):
            cases.append((1, [regular(token(), 600), symlink(token(), token())]))

        generated = []
        for expected_rc, entries in cases:
            path = os.path.join(tmpdir, token() + ".tar")
            with tarfile.open(path, "w", format=tarfile.USTAR_FORMAT) as archive:
                for name, kind, data, linkname in entries:
                    info = tarfile.TarInfo(name)
                    info.type = kind
                    if kind == tarfile.REGTYPE:
                        info.size = len(data)
                        archive.addfile(info, io.BytesIO(data))
                    elif kind == tarfile.SYMTYPE:
                        info.linkname = linkname
                        archive.addfile(info)
                    else:
                        archive.addfile(info)
            generated.append((path, expected_rc))

        random.SystemRandom().shuffle(generated)
        failures = []
        for path, expected_rc in generated:
            result = subprocess.run([EXECUTABLE, "validate", path], capture_output=True, timeout=10)
            if result.returncode != expected_rc:
                failures.append((os.path.basename(path), expected_rc, result.returncode))
        assert not failures, f"Generated tar validation failures: {failures}"


def test_audio_sanitizer_optimize():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"Executable {EXECUTABLE} is not executable."

    with tempfile.TemporaryDirectory() as tmpdir:
        input_dir = os.path.join(tmpdir, "input")
        output_dir = os.path.join(tmpdir, "output")
        os.mkdir(input_dir)
        os.mkdir(output_dir)

        chunks = {
            "chunk1.chunk": b"\x01\x02\x03",
            "chunk2.chunk": b"\x01\x00\x02",
            "chunk3.chunk": b"\x00" * 255,
            "chunk4.chunk": b"\x00" * 256,
            "chunk5.chunk": b"\x00" * 256,
        }
        for name, data in chunks.items():
            with open(os.path.join(input_dir, name), "wb") as f:
                f.write(data)

        result = subprocess.run([EXECUTABLE, "optimize", input_dir, output_dir], capture_output=True)
        assert result.returncode == 0, f"Optimize command failed with code {result.returncode}. Stderr: {result.stderr.decode()}"

        expected = {
            "chunk1.chunk": b"\x01\x02\x03",
            "chunk2.chunk": b"\x01\x00\x01\x02",
            "chunk3.chunk": b"\x00\xff",
            "chunk4.chunk": b"\x00\xff\x00\x01",
            "chunk5.chunk": b"\x00\xff\x00\x01",
        }
        for name, data in expected.items():
            path = os.path.join(output_dir, name)
            assert os.path.exists(path), f"{name} missing in output directory"
            with open(path, "rb") as f:
                assert f.read() == data, f"{name} was not encoded correctly"

        stat4 = os.stat(os.path.join(output_dir, "chunk4.chunk"))
        stat5 = os.stat(os.path.join(output_dir, "chunk5.chunk"))
        assert stat4.st_ino == stat5.st_ino, "chunk4.chunk and chunk5.chunk should be hardlinked to save disk space"
        assert stat4.st_nlink >= 2, "chunk4.chunk link count should be at least 2 due to hardlinking"


def encode_zero_rle(data):
    out = bytearray()
    i = 0
    while i < len(data):
        if data[i] != 0:
            out.append(data[i])
            i += 1
            continue
        j = i
        while j < len(data) and data[j] == 0:
            j += 1
        count = j - i
        while count:
            block = min(count, 255)
            out.extend((0, block))
            count -= block
        i = j
    return bytes(out)


def test_audio_sanitizer_optimize_generated_inputs():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"Executable {EXECUTABLE} is not executable."

    with tempfile.TemporaryDirectory() as tmpdir:
        input_dir = os.path.join(tmpdir, secrets.token_hex(6))
        output_dir = os.path.join(tmpdir, secrets.token_hex(6))
        os.mkdir(input_dir)
        os.mkdir(output_dir)

        random_blob = os.urandom(347)
        duplicate_a = os.urandom(31) + b"\x00" * (300 + secrets.randbelow(350)) + os.urandom(29)
        duplicate_b = b"\x00" * (510 + secrets.randbelow(300))
        payloads = [
            b"",
            random_blob,
            b"\x00" * 1,
            b"\x00" * 254,
            b"\x00" * 255,
            b"\x00" * 256,
            b"\x00" * 700,
            os.urandom(19) + b"\x00\x00" + os.urandom(23) + b"\x00" * 257,
            duplicate_a,
            duplicate_a,
            duplicate_a,
            duplicate_b,
            duplicate_b,
        ]

        names = [secrets.token_hex(10) + ".chunk" for _ in payloads]
        order = list(range(len(payloads)))
        random.SystemRandom().shuffle(order)
        for i in order:
            with open(os.path.join(input_dir, names[i]), "wb") as f:
                f.write(payloads[i])

        result = subprocess.run([EXECUTABLE, "optimize", input_dir, output_dir], capture_output=True, timeout=20)
        assert result.returncode == 0, f"Generated optimize command failed with code {result.returncode}: {result.stderr.decode(errors='replace')}"

        for name, payload in zip(names, payloads):
            path = os.path.join(output_dir, name)
            assert os.path.isfile(path), f"Generated output {name} is missing"
            with open(path, "rb") as f:
                assert f.read() == encode_zero_rle(payload), f"Generated output {name} has incorrect RLE data"

        for indexes in ((8, 9, 10), (11, 12)):
            stats = [os.stat(os.path.join(output_dir, names[i])) for i in indexes]
            assert len({s.st_ino for s in stats}) == 1, "Identical generated chunks were not hard linked"
            assert stats[0].st_nlink >= len(indexes), "Hard-link count is too small for duplicate chunks"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
