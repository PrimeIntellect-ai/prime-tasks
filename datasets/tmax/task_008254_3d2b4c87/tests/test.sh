#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import struct
import subprocess
import tempfile
import uuid
import shutil
import pytest


def test_rejected_paths_log():
    log_file = "/home/user/rejected_paths.log"
    assert os.path.isfile(log_file), f"Expected log file does not exist: {log_file}"

    with open(log_file, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_rejections = [
        "../../../../home/user/hacked.txt",
        "/etc/passwd_fake"
    ]

    for expected in expected_rejections:
        assert expected in lines, f"Log file is missing rejected path: {expected}"

    assert len(lines) == len(expected_rejections), f"Log file contains unexpected entries. Expected exactly {len(expected_rejections)} rejected paths."


def test_zip_slip_prevented():
    hacked_file = "/home/user/hacked.txt"
    fake_passwd = "/etc/passwd_fake"

    assert not os.path.exists(hacked_file), f"Zip slip vulnerability was not prevented! Malicious file found at: {hacked_file}"
    assert not os.path.exists(fake_passwd), f"Zip slip vulnerability was not prevented! Malicious file found at: {fake_passwd}"


def test_hard_links_and_extraction():
    links_dir = "/home/user/cpp_links"
    extract_dir = "/home/user/safe_extract"

    expected_links = {
        "main.cpp": (os.path.join(extract_dir, "src/main.cpp"), b'int main() { return 0; }'),
        "utils.cpp": (os.path.join(extract_dir, "src/utils.cpp"), b'void test() {}'),
        "legit.cpp": (os.path.join(extract_dir, "src/legit.cpp"), b'int legit() {}')
    }

    for link_name, (original_path, expected_content) in expected_links.items():
        link_path = os.path.join(links_dir, link_name)

        assert os.path.isfile(original_path), f"Expected extracted file missing: {original_path}"
        assert os.path.isfile(link_path), f"Expected hard link missing: {link_path}"

        stat_original = os.stat(original_path)
        stat_link = os.stat(link_path)
        assert stat_original.st_ino == stat_link.st_ino and stat_original.st_dev == stat_link.st_dev, \
            f"File {link_path} is not a hard link to {original_path}"

        with open(link_path, "rb") as f:
            content = f.read()
        assert content == expected_content, f"Content mismatch in {link_path}. RLE decompression may be flawed."


def test_ignored_files_not_extracted():
    secret_link = "/home/user/cpp_links/secret.cpp"
    secret_original = "/home/user/safe_extract/src/secret.cpp"

    assert not os.path.exists(secret_link), f"File from non-executable archive was incorrectly processed: {secret_link}"
    assert not os.path.exists(secret_original), f"File from non-executable archive was incorrectly extracted: {secret_original}"


def rle_compress(data):
    if not data:
        return b""
    result = bytearray()
    value = data[0]
    count = 1
    for byte in data[1:]:
        if byte == value and count < 255:
            count += 1
        else:
            result.extend((count, value))
            value = byte
            count = 1
    result.extend((count, value))
    return bytes(result)


def write_archive(path, records):
    with open(path, "wb") as archive:
        archive.write(b"PARC")
        for record_path, content in records:
            encoded_path = record_path.encode("ascii")
            compressed = rle_compress(content)
            archive.write(struct.pack("<H", len(encoded_path)))
            archive.write(encoded_path)
            archive.write(struct.pack("<I", len(compressed)))
            archive.write(compressed)


def test_submitted_extractor_on_generated_archive():
    source = "/home/user/tools/parc_extractor.cpp"
    submitted_binary = "/home/user/tools/parc_extractor"
    log_path = "/home/user/rejected_paths.log"

    assert os.path.isfile(source), f"Extractor source is missing: {source}"
    assert os.path.isfile(submitted_binary), f"Compiled extractor is missing: {submitted_binary}"
    assert os.access(submitted_binary, os.X_OK), f"Extractor is not executable: {submitted_binary}"
    assert stat.S_ISREG(os.stat(submitted_binary).st_mode), "Extractor must be a regular file"
    with open(submitted_binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Extractor is not a compiled ELF executable"

    token = uuid.uuid4().hex
    root = tempfile.mkdtemp(prefix="parc_verify_")
    rebuilt_binary = os.path.join(root, "rebuilt_extractor")
    archive_path = os.path.join(root, "generated.parc")
    absolute_malicious = f"/tmp/parc_abs_{token}.txt"
    traversal_malicious = f"../../../escaped_{token}.txt"
    safe_path = f"nested_{token}/generated.cpp"
    safe_content = b"A" * 255 + b"B" * 19 + token.encode("ascii") + b"CCCD"
    initial_log = open(log_path, "rb").read()

    write_archive(archive_path, [
        (safe_path, safe_content),
        (traversal_malicious, b"TRAVERSAL-" + token.encode("ascii")),
        (absolute_malicious, b"ABSOLUTE-" + token.encode("ascii")),
    ])

    try:
        subprocess.run(
            ["g++", source, "-o", rebuilt_binary],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )

        for label, executable in (("submitted", submitted_binary), ("rebuilt", rebuilt_binary)):
            out_dir = os.path.join(root, label, "a", "b", "out")
            os.makedirs(out_dir, exist_ok=True)
            before_log = open(log_path, "rb").read()

            result = subprocess.run(
                [executable, archive_path, out_dir],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=15,
            )
            assert result.returncode == 0, f"{label} extractor failed on a valid generated archive"

            extracted_safe = os.path.join(out_dir, safe_path)
            assert os.path.isfile(extracted_safe), f"{label} extractor did not extract the generated safe path"
            with open(extracted_safe, "rb") as f:
                assert f.read() == safe_content, f"{label} extractor produced incorrect RLE output"

            traversal_target = os.path.normpath(os.path.join(out_dir, traversal_malicious))
            concatenated_absolute_target = os.path.normpath(out_dir + "/" + absolute_malicious)
            assert not os.path.exists(traversal_target), f"{label} extractor wrote a traversal path"
            assert not os.path.exists(concatenated_absolute_target), f"{label} extractor extracted an absolute path"
            assert not os.path.exists(absolute_malicious), f"{label} extractor wrote outside the output directory"

            after_log = open(log_path, "rb").read()
            expected_append = (traversal_malicious + "\n" + absolute_malicious + "\n").encode("ascii")
            assert after_log == before_log + expected_append, \
                f"{label} extractor did not append the exact rejected paths to the log"
    finally:
        with open(log_path, "wb") as f:
            f.write(initial_log)
        if os.path.exists(absolute_malicious):
            os.remove(absolute_malicious)
        shutil.rmtree(root, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
