#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import io
import os
import stat
import tarfile
import zipfile

EXPECTED_CONTENTS = {
    "dataset.ini": b"[Mappings]\nSENS1042=Subject_Xenon\nSENS9921=Subject_Argon\nSENS0018=Subject_Krypton\nSENS4444=Subject_Radon\n",
    "file_a.dat": b"SENS1042\x00\x01\x02\x03\x04",
    "file_b.dat": b"SENS9921\xff\xff\x00\x00\x11",
    "file_c.dat": b"SENS0018\x0a\x0b\x0c\x0d\x0e",
    "file_d.dat": b"CORR9999\x00\x00\x00\x00\x00",
    "file_e.dat": b"SENS4444\x12\x34\x56\x78\x90",
}


def test_extraction_completed():
    raw_data_dir = "/home/user/raw_data"
    assert os.path.isdir(raw_data_dir), f"Directory {raw_data_dir} does not exist. Did you extract the archive?"
    assert os.path.isfile(os.path.join(raw_data_dir, "dataset.ini")), "dataset.ini is missing from raw_data."

    expected_files = ["file_a.dat", "file_b.dat", "file_c.dat", "file_d.dat", "file_e.dat"]
    for f in expected_files:
        assert os.path.isfile(os.path.join(raw_data_dir, f)), f"Expected file {f} is missing from raw_data."


def test_extracted_files_match_nested_archive_and_original_data():
    archive_path = "/home/user/incoming_data.zip"
    assert os.path.isfile(archive_path), "The original incoming_data.zip archive is missing."

    with zipfile.ZipFile(archive_path, "r") as outer:
        assert "inner.tar.gz" in outer.namelist(), "inner.tar.gz is missing from incoming_data.zip."
        inner_bytes = outer.read("inner.tar.gz")

    archived_contents = {}
    with tarfile.open(fileobj=io.BytesIO(inner_bytes), mode="r:gz") as inner:
        for name in EXPECTED_CONTENTS:
            member_name = "raw_data/" + name
            member = inner.getmember(member_name)
            assert member.isfile(), f"{member_name} is not a regular file in inner.tar.gz."
            archived_contents[name] = inner.extractfile(member).read()

    assert archived_contents == EXPECTED_CONTENTS, "The nested archive does not contain the original dataset contents."

    for name, expected_bytes in EXPECTED_CONTENTS.items():
        path = os.path.join("/home/user/raw_data", name)
        mode = os.lstat(path).st_mode
        assert stat.S_ISREG(mode), f"Extracted path {path} is not a regular file."
        with open(path, "rb") as f:
            actual_bytes = f.read()
        assert actual_bytes == expected_bytes, f"Extracted contents of {name} do not match the archived dataset."
        assert actual_bytes == archived_contents[name], f"{name} was not extracted faithfully from inner.tar.gz."


def test_symlinks_created_correctly():
    organized_dir = "/home/user/organized_dataset"
    assert os.path.isdir(organized_dir), f"Directory {organized_dir} does not exist."

    expected_symlinks = {
        "Subject_Argon.dat": "/home/user/raw_data/file_b.dat",
        "Subject_Krypton.dat": "/home/user/raw_data/file_c.dat",
        "Subject_Radon.dat": "/home/user/raw_data/file_e.dat",
        "Subject_Xenon.dat": "/home/user/raw_data/file_a.dat"
    }

    # Check that only the expected symlinks exist
    actual_files = set(os.listdir(organized_dir))
    expected_files = set(expected_symlinks.keys())
    assert actual_files == expected_files, f"Expected symlinks {expected_files}, but found {actual_files}"

    for symlink_name, target_path in expected_symlinks.items():
        symlink_path = os.path.join(organized_dir, symlink_name)
        assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink."

        actual_target = os.readlink(symlink_path)
        assert actual_target == target_path, f"Symlink {symlink_name} points to {actual_target}, expected {target_path}. Note: target must be absolute."


def test_outputs_are_derived_from_ini_and_binary_headers():
    config = configparser.ConfigParser(interpolation=None)
    config.optionxform = str
    with open("/home/user/raw_data/dataset.ini", "r", encoding="ascii") as f:
        config.read_file(f)
    assert config.sections() == ["Mappings"]
    mappings = dict(config.items("Mappings"))
    assert mappings == {
        "SENS1042": "Subject_Xenon",
        "SENS9921": "Subject_Argon",
        "SENS0018": "Subject_Krypton",
        "SENS4444": "Subject_Radon",
    }

    derived = {}
    for filename in sorted(name for name in EXPECTED_CONTENTS if name.endswith(".dat")):
        path = os.path.join("/home/user/raw_data", filename)
        with open(path, "rb") as f:
            header_bytes = f.read(8)
        assert len(header_bytes) == 8
        header = header_bytes.decode("ascii")
        if header in mappings:
            derived[mappings[header] + ".dat"] = path

    actual_links = {
        name: os.readlink(os.path.join("/home/user/organized_dataset", name))
        for name in os.listdir("/home/user/organized_dataset")
    }
    assert actual_links == derived, "Organized symlinks do not match the mappings derived from dataset.ini and the 8-byte headers."

    derived_report = [f"{name[:-4]},{derived[name]}" for name in sorted(derived)]
    with open("/home/user/report.csv", "r", encoding="utf-8") as f:
        actual_report = [line.strip() for line in f if line.strip()]
    assert actual_report == derived_report, "report.csv is not the sorted report derived from dataset.ini and the binary headers."


def test_report_csv_correct():
    report_path = "/home/user/report.csv"
    assert os.path.isfile(report_path), f"Report file {report_path} does not exist."

    expected_lines = [
        "Subject_Argon,/home/user/raw_data/file_b.dat",
        "Subject_Krypton,/home/user/raw_data/file_c.dat",
        "Subject_Radon,/home/user/raw_data/file_e.dat",
        "Subject_Xenon,/home/user/raw_data/file_a.dat"
    ]

    with open(report_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, f"Report content is incorrect. Expected:\n{expected_lines}\nGot:\n{actual_lines}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
