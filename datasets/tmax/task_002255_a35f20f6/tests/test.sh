#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess
import sys
import tokenize
import uuid

import pytest

SCRIPT = "/home/user/process_datasets.py"
INCOMING = "/home/user/incoming"
ORGANIZED = "/home/user/organized"
EXPECTED = {}


def decode_legacy(raw):
    odd = raw[1::2]
    if odd and sum(byte == 0 for byte in odd) / len(odd) > 0.30:
        return raw.decode("utf-16le")
    return raw.decode("iso-8859-1")


def setup_module(module):
    assert os.path.exists(SCRIPT), f"Missing required script: {SCRIPT}"
    assert not os.path.islink(SCRIPT), f"Script must not be a symbolic link: {SCRIPT}"
    assert stat.S_ISREG(os.stat(SCRIPT).st_mode), f"Script is not a regular file: {SCRIPT}"

    try:
        with tokenize.open(SCRIPT) as source_file:
            source = source_file.read()
        compile(source, SCRIPT, "exec")
    except Exception as exc:
        pytest.fail(f"{SCRIPT} is not valid Python source: {exc}")

    token = uuid.uuid4().hex[:12].upper()
    probes = {
        f"probe_{token}_utf16.bin": (
            f"ProjectID: RANDOM-{token}-U\nMeasurement,Value\nCity,東京\nNote,Ω and café\n",
            "utf-16le",
        ),
        f"probe_{token}_latin1.txt": (
            f"ProjectID: RANDOM-{token}-L\nMeasurement,Value\nCity,München\nNote,crème brûlée\n",
            "iso-8859-1",
        ),
    }
    for name, (content, encoding) in probes.items():
        with open(os.path.join(INCOMING, name), "w", encoding=encoding, newline="") as f:
            f.write(content)

    for name in os.listdir(INCOMING):
        path = os.path.join(INCOMING, name)
        assert os.path.isfile(path), f"Incoming entry is not a file: {path}"
        with open(path, "rb") as f:
            raw = f.read()
        content = decode_legacy(raw)
        first_line = content.splitlines()[0]
        assert first_line.startswith("ProjectID: "), f"Invalid fixture first line: {path}"
        project_id = first_line[len("ProjectID: "):]
        EXPECTED[project_id] = {
            "source": path,
            "raw": raw,
            "content": content,
            "inode": os.stat(path).st_ino,
            "device": os.stat(path).st_dev,
        }

    shutil.rmtree(ORGANIZED, ignore_errors=True)
    result = subprocess.run(
        [sys.executable, SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Script execution failed with status {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_utf8_files_created_and_content():
    omega_path = "/home/user/organized/utf8/OMEGA-77.txt"
    delta_path = "/home/user/organized/utf8/DELTA-04.txt"

    assert os.path.isfile(omega_path), f"Missing UTF-8 file: {omega_path}"
    assert os.path.isfile(delta_path), f"Missing UTF-8 file: {delta_path}"

    with open(omega_path, "r", encoding="utf-8") as f:
        omega_content = f.read()
    assert "ProjectID: OMEGA-77" in omega_content, f"Incorrect content in {omega_path}"

    with open(delta_path, "r", encoding="utf-8") as f:
        delta_content = f.read()
    assert "ProjectID: DELTA-04" in delta_content, f"Incorrect content in {delta_path}"


def test_hard_links_created():
    omega_bak = "/home/user/organized/archive/OMEGA-77_raw.bak"
    delta_bak = "/home/user/organized/archive/DELTA-04_raw.bak"

    dataset_a = "/home/user/incoming/dataset_a.csv"
    dataset_b = "/home/user/incoming/dataset_b.dat"

    assert os.path.isfile(omega_bak), f"Missing hard link: {omega_bak}"
    assert os.path.isfile(delta_bak), f"Missing hard link: {delta_bak}"

    assert os.stat(omega_bak).st_ino == os.stat(dataset_a).st_ino, f"{omega_bak} is not a hard link to {dataset_a}"
    assert os.stat(delta_bak).st_ino == os.stat(dataset_b).st_ino, f"{delta_bak} is not a hard link to {dataset_b}"


def test_symlinks_created():
    omega_symlink = "/home/user/organized/symlinks/OMEGA-77_active"
    delta_symlink = "/home/user/organized/symlinks/DELTA-04_active"

    omega_target = "/home/user/organized/utf8/OMEGA-77.txt"
    delta_target = "/home/user/organized/utf8/DELTA-04.txt"

    assert os.path.islink(omega_symlink), f"Missing symlink: {omega_symlink}"
    assert os.path.islink(delta_symlink), f"Missing symlink: {delta_symlink}"

    assert os.readlink(omega_symlink) == omega_target, f"{omega_symlink} points to incorrect target"
    assert os.readlink(delta_symlink) == delta_target, f"{delta_symlink} points to incorrect target"


def test_every_incoming_file_is_fully_processed():
    for project_id, expected in EXPECTED.items():
        source = expected["source"]
        utf8_path = f"/home/user/organized/utf8/{project_id}.txt"
        archive_path = f"/home/user/organized/archive/{project_id}_raw.bak"
        symlink_path = f"/home/user/organized/symlinks/{project_id}_active"

        assert os.path.isfile(source), f"Original file was removed: {source}"
        with open(source, "rb") as f:
            assert f.read() == expected["raw"], f"Original file was modified: {source}"

        assert os.path.isfile(utf8_path), f"Missing UTF-8 file: {utf8_path}"
        with open(utf8_path, "rb") as f:
            assert f.read() == expected["content"].encode("utf-8"), (
                f"UTF-8 output does not preserve the entire decoded content: {utf8_path}"
            )

        assert os.path.isfile(archive_path), f"Missing hard link: {archive_path}"
        source_stat = os.stat(source)
        archive_stat = os.stat(archive_path)
        assert source_stat.st_ino == expected["inode"]
        assert source_stat.st_dev == expected["device"]
        assert archive_stat.st_ino == source_stat.st_ino, f"Not a hard link: {archive_path}"
        assert archive_stat.st_dev == source_stat.st_dev, f"Not a hard link: {archive_path}"

        assert os.path.islink(symlink_path), f"Missing symlink: {symlink_path}"
        assert os.readlink(symlink_path) == os.path.abspath(utf8_path), (
            f"Symlink has incorrect target: {symlink_path}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
