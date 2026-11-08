#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import shutil
import struct
import subprocess
import tarfile
import tempfile
import uuid
import pytest

SRC = "/home/user/archiver.c"
BIN = "/home/user/archiver"
WAL = "/home/user/archive_index.wal"
INCOMING = "/home/user/incoming"
BACKUP = "/home/user/backup_parts"


def get_elf_entry(filepath):
    if not os.path.isfile(filepath):
        return None
    with open(filepath, "rb") as f:
        if f.read(4) != b"\x7fELF":
            return None
        e_class = f.read(1)
        e_data = f.read(1)
        if not e_class or not e_data or e_class[0] != 2:
            return None
        if e_data[0] == 1:
            endian = "<"
        elif e_data[0] == 2:
            endian = ">"
        else:
            return None
        f.seek(0x18)
        raw = f.read(8)
        if len(raw) != 8:
            return None
        return struct.unpack(endian + "Q", raw)[0]


def parse_wal(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
    except UnicodeDecodeError:
        pytest.fail(f"{path} is not valid UTF-8.")

    entries = {}
    for line in content.splitlines():
        m = re.fullmatch(r"ELF: (.+) ENTRY: 0x([0-9a-fA-F]+)", line.strip())
        if m:
            entries[m.group(1)] = int(m.group(2), 16)
    return content, entries


def test_c_source_code_constraints():
    assert os.path.exists(SRC), f"{SRC} is missing."
    with open(SRC, "r", encoding="utf-8", errors="ignore") as f:
        code = f.read()

    code_no_spaces = code.replace(" ", "")
    assert "system(" not in code_no_spaces, "Forbidden system() call found in C source code."
    assert "<elf.h>" in code, "<elf.h> not included in C source code."
    assert "<iconv.h>" in code, "<iconv.h> not included in C source code."
    assert "<sys/file.h>" in code or "<fcntl.h>" in code, "File locking header (<sys/file.h> or <fcntl.h>) not included in C source code."

    assert os.path.isfile(BIN), f"{BIN} is missing."
    assert os.access(BIN, os.X_OK), f"{BIN} is not executable."
    assert get_elf_entry(BIN) is not None, f"{BIN} is not a 64-bit ELF executable."


def test_archive_index_wal_contents():
    assert os.path.exists(WAL), f"{WAL} does not exist."
    content, found_entries = parse_wal(WAL)
    expected_text = "Système de sauvegarde prêt. Résumé des opérations."
    assert expected_text in content, f"Expected UTF-8 converted text not found in {WAL}."

    assert os.path.isdir(INCOMING), f"{INCOMING} is missing."
    elf_files_checked = 0
    for filename in os.listdir(INCOMING):
        filepath = os.path.join(INCOMING, filename)
        entry = get_elf_entry(filepath)
        if entry is not None:
            elf_files_checked += 1
            assert filename in found_entries, f"Entry for ELF file '{filename}' not found in {WAL}."
            assert found_entries[filename] == entry, f"Incorrect entry point for '{filename}' in {WAL}. Expected {hex(entry)}."
    assert elf_files_checked > 0, "No 64-bit ELF files found in incoming directory to verify."


def test_split_archives_include_full_input():
    assert os.path.isdir(BACKUP), f"{BACKUP} is missing."
    parts = sorted(glob.glob(os.path.join(BACKUP, "backup.tar.gz.part*")))
    assert len(parts) >= 2, "The compressed archive was not split into multiple parts."

    expected_names = []
    for i in range(len(parts)):
        n = i
        suffix = ""
        while True:
            suffix = chr(ord("a") + (n % 26)) + suffix
            n = n // 26 - 1
            if n < 0:
                break
        suffix = suffix.rjust(2, "a")
        expected_names.append("backup.tar.gz.part" + suffix)
    assert [os.path.basename(p) for p in parts] == expected_names, "Archive parts are not contiguously named partaa, partab, etc."

    for part in parts[:-1]:
        size = os.path.getsize(part)
        assert size == 1024 * 1024, f"Archive part {part} size is {size} bytes, expected exactly 1048576 bytes (1MB)."
    assert 0 < os.path.getsize(parts[-1]) <= 1024 * 1024, "The final archive part has an invalid size."

    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        for part in parts:
            with open(part, "rb") as p:
                shutil.copyfileobj(p, tmp)
        tmp_name = tmp.name

    try:
        assert tarfile.is_tarfile(tmp_name), "Reassembled file is not a valid tar archive."
        with tarfile.open(tmp_name, "r:gz") as tar:
            members = tar.getmembers()
            names = [m.name for m in members]

            assert any(name.endswith("archive_index.wal") for name in names), "archive_index.wal not found in the reassembled tarball."
            assert any(name.endswith("sys_monitor") for name in names), "sys_monitor not found in the reassembled tarball."
            assert any(name.endswith("db_sync") for name in names), "db_sync not found in the reassembled tarball."

            def matching_members(suffix):
                normalized_suffix = suffix.strip("/")
                return [m for m in members if m.name.lstrip("./").strip("/") == normalized_suffix or m.name.lstrip("./").strip("/").endswith("/" + normalized_suffix)]

            wal_members = matching_members("archive_index.wal")
            assert any(m.isfile() and tar.extractfile(m).read() == open(WAL, "rb").read() for m in wal_members), "The archived WAL does not match archive_index.wal."

            for root, dirs, files in os.walk(INCOMING):
                rel_root = os.path.relpath(root, INCOMING)
                rel_root = "" if rel_root == "." else rel_root
                for dirname in dirs:
                    rel = os.path.join("incoming", rel_root, dirname).replace(os.sep, "/")
                    assert any(m.isdir() for m in matching_members(rel)), f"Directory '{rel}' is missing from the archive."
                for filename in files:
                    source = os.path.join(root, filename)
                    rel = os.path.join("incoming", rel_root, filename).replace(os.sep, "/")
                    matches = matching_members(rel)
                    if os.path.islink(source):
                        assert any(m.issym() and m.linkname == os.readlink(source) for m in matches), f"Symlink '{rel}' is missing or incorrect in the archive."
                    else:
                        with open(source, "rb") as f:
                            expected = f.read()
                        assert any(m.isfile() and tar.extractfile(m).read() == expected for m in matches), f"File '{rel}' is missing or has incorrect contents in the archive."
    finally:
        os.remove(tmp_name)


def test_compiled_program_on_unseen_inputs():
    token = uuid.uuid4().hex
    legacy_bytes = ("Vérification dynamique " + token + " : déjà prêt.\n").encode("iso-8859-1")
    expected_text = legacy_bytes.decode("iso-8859-1")
    legacy_path = os.path.join(INCOMING, "legacy_log.iso88591")
    probe_name = "probe_" + token
    probe_path = os.path.join(INCOMING, probe_name)

    with open(legacy_path, "rb") as f:
        old_legacy = f.read()
    old_wal = open(WAL, "rb").read() if os.path.exists(WAL) else None

    try:
        with open(legacy_path, "wb") as f:
            f.write(legacy_bytes)
        shutil.copy2(os.path.join(INCOMING, "sys_monitor"), probe_path)
        if os.path.exists(WAL):
            os.remove(WAL)

        compile_result = subprocess.run(
            ["gcc", SRC, "-o", BIN], stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=30
        )
        assert compile_result.returncode == 0, "archiver.c failed to compile:\n" + compile_result.stderr
        assert get_elf_entry(BIN) is not None, "Compiled archiver is not a 64-bit ELF executable."

        run_result = subprocess.run(
            [BIN], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=30
        )
        assert run_result.returncode == 0, "Compiled archiver failed when run:\n" + run_result.stderr
        assert os.path.isfile(WAL), "Running archiver did not create archive_index.wal."

        content, entries = parse_wal(WAL)
        assert expected_text in content, "The compiled program did not convert the unseen ISO-8859-1 input to UTF-8."

        checked = 0
        for filename in os.listdir(INCOMING):
            entry = get_elf_entry(os.path.join(INCOMING, filename))
            if entry is not None:
                checked += 1
                assert entries.get(filename) == entry, f"The compiled program did not write the correct entry point for '{filename}'."
        assert checked >= 3 and entries.get(probe_name) == get_elf_entry(probe_path), "The compiled program did not discover the unseen ELF file."
    finally:
        if os.path.exists(probe_path):
            os.remove(probe_path)
        with open(legacy_path, "wb") as f:
            f.write(old_legacy)
        if old_wal is None:
            if os.path.exists(WAL):
                os.remove(WAL)
        else:
            with open(WAL, "wb") as f:
                f.write(old_wal)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
