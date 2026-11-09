#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import struct
import subprocess
import tarfile
from pathlib import Path

import pytest


def get_elf64_entry_point(filepath):
    """Parse an ELF64 header and return its entry point."""
    with open(filepath, "rb") as f:
        e_ident = f.read(16)
        if len(e_ident) != 16 or e_ident[:4] != b"\x7fELF":
            raise ValueError(f"{filepath} is not an ELF file")
        if e_ident[4] != 2:
            raise ValueError(f"{filepath} is not a 64-bit ELF")
        f.seek(24)
        entry_bytes = f.read(8)
        if len(entry_bytes) != 8:
            raise ValueError(f"{filepath} has a truncated ELF header")
        endian = "<" if e_ident[5] == 1 else ">" if e_ident[5] == 2 else None
        if endian is None:
            raise ValueError(f"{filepath} has an invalid ELF byte order")
        return struct.unpack(endian + "Q", entry_bytes)[0]


def test_recovered_archive_exists():
    assert os.path.exists("/home/user/recovered.tar.gz"), "/home/user/recovered.tar.gz is missing"

    parts = sorted(
        Path("/home/user/artifact_store").rglob("archive_part_*"),
        key=lambda p: p.name,
    )
    assert parts, "No archive parts were found"
    expected = b"".join(p.read_bytes() for p in parts if p.is_file())
    assert Path("/home/user/recovered.tar.gz").read_bytes() == expected, (
        "recovered.tar.gz is not the exact alphabetical concatenation of the archive parts"
    )


def test_binaries_extracted():
    binaries_dir = "/home/user/binaries"
    assert os.path.isdir(binaries_dir), f"{binaries_dir} directory is missing"
    for app in ["app_a", "app_b", "app_c"]:
        app_path = os.path.join(binaries_dir, app)
        assert os.path.isfile(app_path), f"Extracted binary {app} is missing in {binaries_dir}"

    with tarfile.open("/home/user/recovered.tar.gz", "r:gz") as archive:
        for app in ["app_a", "app_b", "app_c"]:
            member = archive.getmember(app)
            extracted = archive.extractfile(member)
            assert extracted is not None
            assert Path(binaries_dir, app).read_bytes() == extracted.read(), (
                f"Extracted binary {app} does not match the recovered archive"
            )


def test_c_program_exists():
    source = Path("/home/user/analyze_elf.c")
    executable = Path("/home/user/analyze_elf")
    assert source.is_file(), "/home/user/analyze_elf.c is missing"
    assert executable.is_file(), "Compiled executable /home/user/analyze_elf is missing"
    assert os.access(executable, os.X_OK), "/home/user/analyze_elf is not executable"
    assert executable.read_bytes()[:4] == b"\x7fELF", "/home/user/analyze_elf is not an ELF executable"

    source_text = source.read_text(errors="replace")
    assert "elf.h" in source_text, "C source does not include <elf.h>"
    assert "Elf64_Ehdr" in source_text, "C source does not use the standard Elf64_Ehdr structure"


def test_report_csv_correctness():
    report_path = "/home/user/report.csv"
    assert os.path.isfile(report_path), f"{report_path} is missing"

    expected_entries = []
    for app in ["app_a", "app_b", "app_c"]:
        src_path = f"/tmp/src/{app}"
        assert os.path.isfile(src_path), f"Original source binary {src_path} missing for ground truth"
        entry_point = get_elf64_entry_point(src_path)
        expected_entries.append(f"{app},{hex(entry_point)}")

    expected_entries.sort()
    with open(report_path, "r") as f:
        actual_entries = [line.strip() for line in f if line.strip()]

    assert actual_entries == expected_entries, (
        f"CSV contents mismatch.\nExpected:\n{expected_entries}\nGot:\n{actual_entries}"
    )


def _make_dynamic_fixture(directory, cases):
    shutil.rmtree(directory, ignore_errors=True)
    directory.mkdir()
    templates = [Path("/tmp/src/app_a"), Path("/tmp/src/app_b"), Path("/tmp/src/app_c")]
    for (name, entry), template in zip(cases, templates):
        data = bytearray(template.read_bytes())
        assert data[:5] == b"\x7fELF\x02"
        endian = "little" if data[5] == 1 else "big"
        data[24:32] = entry.to_bytes(8, endian)
        (directory / name).write_bytes(data)

    (directory / ("not_elf_" + secrets.token_hex(4))).write_bytes(b"not an elf file\n")
    nested = directory / ("directory_" + secrets.token_hex(4))
    nested.mkdir()
    shutil.copy2(templates[0], nested / "nested_elf_must_be_ignored")


def _run_and_check(program, report, expected):
    report.unlink(missing_ok=True)
    result = subprocess.run(
        [str(program)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
        check=False,
    )
    assert result.returncode == 0, (
        f"{program} failed on dynamic ELF inputs with status {result.returncode}:\n"
        + result.stderr.decode(errors="replace")
    )
    assert report.is_file(), f"{program} did not create /home/user/report.csv"
    actual = [line.strip() for line in report.read_text().splitlines() if line.strip()]
    assert actual == expected, f"Dynamic CSV mismatch for {program}. Expected {expected}, got {actual}"


def test_analyzer_executes_and_parses_dynamic_elf64_inputs():
    source = Path("/home/user/analyze_elf.c")
    installed = Path("/home/user/analyze_elf")
    fresh = Path("/tmp/analyze_elf_from_source_" + secrets.token_hex(8))
    subprocess.run(
        ["gcc", str(source), "-o", str(fresh)],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )

    binaries = Path("/home/user/binaries")
    report = Path("/home/user/report.csv")
    backup_dir = Path("/home/user/.binaries_verifier_backup_" + secrets.token_hex(8))
    backup_report = Path("/home/user/.report_verifier_backup_" + secrets.token_hex(8))

    token = secrets.token_hex(5)
    cases = [
        (f"zeta_{token}", secrets.randbits(47) | 0x1000),
        (f"alpha_{token}", secrets.randbits(47) | 0x2000),
        (f"middle_{token}", secrets.randbits(47) | 0x3000),
    ]
    expected = sorted(f"{name},{hex(entry)}" for name, entry in cases)

    os.replace(binaries, backup_dir)
    if report.exists():
        os.replace(report, backup_report)
    try:
        _make_dynamic_fixture(binaries, cases)
        _run_and_check(installed, report, expected)

        _make_dynamic_fixture(binaries, cases)
        _run_and_check(fresh, report, expected)
    finally:
        shutil.rmtree(binaries, ignore_errors=True)
        os.replace(backup_dir, binaries)
        report.unlink(missing_ok=True)
        if backup_report.exists():
            os.replace(backup_report, report)
        fresh.unlink(missing_ok=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
