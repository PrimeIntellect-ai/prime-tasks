#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import gzip
import os
import secrets
import shutil
import subprocess
import tarfile


def test_extracted_valid_sets():
    """Verify that only valid sets are extracted."""
    assert os.path.exists("/home/user/extracted/set1"), "set1 was not extracted"
    assert os.path.exists("/home/user/extracted/set2"), "set2 was not extracted"

    assert os.path.exists("/home/user/extracted/set1/sample_alpha.txt"), "sample_alpha.txt missing"
    assert os.path.exists("/home/user/extracted/set1/sample_alpha.dat"), "sample_alpha.dat missing"
    assert os.path.exists("/home/user/extracted/set2/sample_beta.txt"), "sample_beta.txt missing"
    assert os.path.exists("/home/user/extracted/set2/sample_beta.dat"), "sample_beta.dat missing"


def test_extracted_invalid_sets():
    """Verify that corrupted sets are not extracted."""
    assert not os.path.exists("/home/user/extracted/set3"), "set3 (corrupted) should not be extracted"


def test_merged_archives_and_extracted_provenance():
    """Check that each merged archive is exactly its chunks and only valid data was extracted."""
    raw = "/home/user/dataset_raw"
    for set_name in ("set1", "set2", "set3"):
        merged_path = os.path.join(raw, set_name + ".tar.gz")
        chunk_paths = sorted(glob.glob(merged_path + ".*"))
        assert chunk_paths, f"No chunks found for {set_name}"
        assert os.path.isfile(merged_path), f"Merged archive missing for {set_name}"
        expected = b"".join(open(path, "rb").read() for path in chunk_paths)
        with open(merged_path, "rb") as f:
            assert f.read() == expected, f"{merged_path} is not the exact merge of its chunks"

    for set_name, txt_name, dat_name in (
        ("set1", "sample_alpha.txt", "sample_alpha.dat"),
        ("set2", "sample_beta.txt", "sample_beta.dat"),
    ):
        archive = os.path.join(raw, set_name + ".tar.gz")
        with gzip.open(archive, "rb") as f:
            while f.read(1024 * 1024):
                pass
        with tarfile.open(archive, "r:gz") as tf:
            for name in (txt_name, dat_name):
                member_name = f"{set_name}/{name}"
                archived = tf.extractfile(member_name)
                assert archived is not None, f"{member_name} absent from {archive}"
                with open(f"/home/user/extracted/{member_name}", "rb") as f:
                    assert f.read() == archived.read(), f"Extracted {member_name} differs from archive"

    result = subprocess.run(
        ["gzip", "-t", os.path.join(raw, "set3.tar.gz")],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert result.returncode != 0, "set3 should be corrupt"


def test_metadata_format_and_values():
    expected = {
        "/home/user/extracted/set1/sample_alpha.txt": ["ID: X99", "Category: RNA"],
        "/home/user/extracted/set2/sample_beta.txt": ["ID: M01", "Category: DNA"],
    }
    for path, wanted in expected.items():
        with open(path, encoding="utf-8") as f:
            assert f.read().splitlines() == wanted, f"Incorrect metadata in {path}"


def test_symlinks_created():
    """Verify that the symlinks are correctly created in the organized directory."""
    symlink_rna = "/home/user/organized/RNA/X99.dat"
    symlink_dna = "/home/user/organized/DNA/M01.dat"

    assert os.path.islink(symlink_rna), f"{symlink_rna} is not a symlink or does not exist"
    assert os.path.islink(symlink_dna), f"{symlink_dna} is not a symlink or does not exist"

    target_rna = os.readlink(symlink_rna)
    target_dna = os.readlink(symlink_dna)

    assert target_rna.endswith("/home/user/extracted/set1/sample_alpha.dat") or target_rna == "../../extracted/set1/sample_alpha.dat", \
        f"{symlink_rna} points to wrong target: {target_rna}"
    assert target_dna.endswith("/home/user/extracted/set2/sample_beta.dat") or target_dna == "../../extracted/set2/sample_beta.dat", \
        f"{symlink_dna} points to wrong target: {target_dna}"


def test_success_log():
    """Verify the contents of the success log."""
    log_path = "/home/user/success.log"
    assert os.path.exists(log_path), f"{log_path} does not exist"

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = ["DNA:M01", "RNA:X99"]
    assert lines == expected_lines, f"Log contents are incorrect. Expected {expected_lines}, got {lines}"


def test_go_organizer_behavior_on_fresh_inputs():
    """Compile and execute the submitted Go program against verifier-generated metadata."""
    source = "/home/user/organizer.go"
    assert os.path.isfile(source) and not os.path.islink(source), "organizer.go is missing or not a regular source file"

    binary = "/tmp/organizer-under-test"
    build = subprocess.run(
        ["go", "build", "-o", binary, source],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert build.returncode == 0, f"organizer.go did not compile: {build.stderr}"

    shutil.rmtree("/home/user/extracted")
    shutil.rmtree("/home/user/organized")
    os.makedirs("/home/user/extracted/nested_a")
    os.makedirs("/home/user/extracted/nested_b/deeper")
    os.makedirs("/home/user/organized")
    if os.path.lexists("/home/user/success.log"):
        os.remove("/home/user/success.log")

    records = []
    for directory in ("nested_a", "nested_b/deeper"):
        ident = secrets.token_hex(6).upper()
        category = "Category" + secrets.token_hex(5)
        base = "sample_" + secrets.token_hex(4)
        data = secrets.token_bytes(193)
        root = os.path.join("/home/user/extracted", directory, base)
        with open(root + ".txt", "w", encoding="utf-8") as f:
            f.write(f"ID: {ident}\nCategory: {category}\n")
        with open(root + ".dat", "wb") as f:
            f.write(data)
        records.append((category, ident, root + ".dat"))

    run = subprocess.run(
        [binary],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert run.returncode == 0, f"organizer failed on fresh inputs: {run.stderr}"

    for category, ident, source_dat in records:
        link = f"/home/user/organized/{category}/{ident}.dat"
        assert os.path.islink(link), f"Fresh-input link was not created: {link}"
        assert os.path.samefile(link, source_dat), f"{link} does not point to its corresponding data file"

    with open("/home/user/success.log", encoding="utf-8") as f:
        actual = [line.rstrip("\n") for line in f]
    expected = [f"{category}:{ident}" for category, ident, _ in sorted(records)]
    assert actual == expected, f"Fresh-input log is incorrect: expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
