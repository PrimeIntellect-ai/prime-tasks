#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import subprocess
import pytest
import shutil
import secrets

COMMITTED_FILES_TXT = "/home/user/data/committed_files.txt"
SUMMARY_JSON = "/home/user/data/summary.json"
WAL_FILE = "/home/user/data/sync.wal"
GCODE_SYMLINK = "/home/user/latest_configs/latest_cnc.gcode"
ELF_SYMLINK = "/home/user/latest_configs/latest_firmware.elf"
PARSER_DIR = "/home/user/parser"
MAIN_GO = "/home/user/parser/main.go"
GO_MOD = "/home/user/parser/go.mod"

def get_expected_committed_files():
    """Derive expected committed files from the WAL file."""
    committed = []
    if os.path.exists(WAL_FILE):
        with open(WAL_FILE, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) >= 3 and parts[0] == "COMMIT":
                    committed.append(parts[2])
    return committed

def test_committed_files_list():
    assert os.path.exists(COMMITTED_FILES_TXT), f"Missing {COMMITTED_FILES_TXT}"
    with open(COMMITTED_FILES_TXT, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = get_expected_committed_files()
    assert len(expected) > 0, "Expected to find COMMIT lines in WAL file."
    assert set(lines) == set(expected), f"Committed files list does not match WAL COMMIT entries. Expected {expected}, got {lines}"

def test_gcode_encoding_is_utf8():
    expected = get_expected_committed_files()
    gcode_files = [f for f in expected if f.endswith(".gcode")]
    for gcode_file in gcode_files:
        assert os.path.exists(gcode_file), f"GCode file missing: {gcode_file}"
        try:
            with open(gcode_file, "r", encoding="utf-8") as f:
                f.read()
        except UnicodeDecodeError:
            pytest.fail(f"GCode file {gcode_file} is not valid UTF-8.")

def test_go_code_exists():
    assert os.path.exists(MAIN_GO), "Go source file missing at /home/user/parser/main.go"
    assert os.path.exists(GO_MOD), "Go module file missing at /home/user/parser/go.mod"

def get_elf_info(elf_path):
    """Extract entry point and machine type using readelf to mimic Go's debug/elf."""
    out = subprocess.check_output(["readelf", "-h", elf_path], text=True)
    entry_point = None
    machine = None
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("Entry point address:"):
            val = line.split(":", 1)[1].strip()
            entry_point = int(val, 16)
        elif line.startswith("Machine:"):
            val = line.split(":", 1)[1].strip()
            if "X86-64" in val or "x86-64" in val or "Advanced Micro Devices X86-64" in val:
                machine = "EM_X86_64"
            elif "AArch64" in val:
                machine = "EM_AARCH64"
            elif "80386" in val:
                machine = "EM_386"
            elif "ARM" in val:
                machine = "EM_ARM"
            else:
                machine = val
    return entry_point, machine

def get_max_z(gcode_path):
    """Calculate the max Z from G0/G1 commands."""
    max_z = None
    with open(gcode_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.split(";")[0].strip()
            parts = line.split()
            if not parts:
                continue
            if parts[0] in ("G0", "G1"):
                for p in parts[1:]:
                    if p.startswith("Z"):
                        try:
                            z_val = float(p[1:])
                            if max_z is None or z_val > max_z:
                                max_z = z_val
                        except ValueError:
                            pass
    return max_z

def test_summary_json():
    assert os.path.exists(SUMMARY_JSON), f"Missing {SUMMARY_JSON}"
    with open(SUMMARY_JSON, "r", encoding="utf-8") as f:
        try:
            summary = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{SUMMARY_JSON} is not valid JSON.")

    assert isinstance(summary, list), "Summary JSON must be an array of objects."
    expected_files = get_expected_committed_files()
    summary_by_file = {item.get("file"): item for item in summary}

    for fpath in expected_files:
        assert fpath in summary_by_file, f"File {fpath} missing from summary.json"
        item = summary_by_file[fpath]

        if fpath.endswith(".gcode"):
            assert item.get("type") == "gcode", f"Expected type 'gcode' for {fpath}"
            expected_z = get_max_z(fpath)
            assert "max_z" in item, f"Missing 'max_z' for {fpath}"
            assert abs(item["max_z"] - expected_z) < 1e-6, f"Incorrect max_z for {fpath}. Expected {expected_z}, got {item['max_z']}"
        elif fpath.endswith(".elf"):
            assert item.get("type") == "elf", f"Expected type 'elf' for {fpath}"
            expected_entry, expected_machine = get_elf_info(fpath)
            assert "entry_point" in item, f"Missing 'entry_point' for {fpath}"
            assert item["entry_point"] == expected_entry, f"Incorrect entry_point for {fpath}. Expected {expected_entry}, got {item['entry_point']}"
            assert "machine" in item, f"Missing 'machine' for {fpath}"
            assert item["machine"] == expected_machine, f"Incorrect machine for {fpath}. Expected {expected_machine}, got {item['machine']}"

def test_symlinks_created():
    expected_files = get_expected_committed_files()
    gcode_files = [f for f in expected_files if f.endswith(".gcode")]
    elf_files = [f for f in expected_files if f.endswith(".elf")]

    if gcode_files:
        assert os.path.islink(GCODE_SYMLINK), f"Missing or invalid symlink at {GCODE_SYMLINK}"
        target = os.readlink(GCODE_SYMLINK)
        abs_target = os.path.abspath(os.path.join(os.path.dirname(GCODE_SYMLINK), target))
        assert abs_target == gcode_files[0], f"Symlink {GCODE_SYMLINK} points to {abs_target}, expected {gcode_files[0]}"

    if elf_files:
        assert os.path.islink(ELF_SYMLINK), f"Missing or invalid symlink at {ELF_SYMLINK}"
        target = os.readlink(ELF_SYMLINK)
        abs_target = os.path.abspath(os.path.join(os.path.dirname(ELF_SYMLINK), target))
        assert abs_target == elf_files[0], f"Symlink {ELF_SYMLINK} points to {abs_target}, expected {elf_files[0]}"

def test_go_program_executes_on_derived_inputs():
    assert os.path.isfile(MAIN_GO), f"{MAIN_GO} must be a regular file"
    assert os.path.isfile(GO_MOD), f"{GO_MOD} must be a regular file"

    token = secrets.token_hex(8)
    gcode_path = f"/home/user/data/verifier_{token}.gcode"
    elf_path = f"/home/user/data/verifier_{token}.elf"
    executable = f"/tmp/parser_{token}"
    high_z = 1000 + secrets.randbelow(900000) / 1000.0
    low_z = -1 - secrets.randbelow(1000) / 10.0

    committed_backup = open(COMMITTED_FILES_TXT, "rb").read() if os.path.exists(COMMITTED_FILES_TXT) else None
    summary_backup = open(SUMMARY_JSON, "rb").read() if os.path.exists(SUMMARY_JSON) else None
    link_backups = {}
    for link in (GCODE_SYMLINK, ELF_SYMLINK):
        link_backups[link] = os.readlink(link) if os.path.islink(link) else None

    try:
        with open(gcode_path, "w", encoding="utf-8") as f:
            f.write("G21 ; café UTF-8 comment\n")
            f.write(f"G0 X0 Y0 Z{low_z}\n")
            f.write(f"G1 X12 Y7 Z{high_z} F900\n")
            f.write(f"G1 X2 Y3 Z{high_z - 0.125}\n")
            f.write(f"G2 X1 Y1 Z{high_z + 5000}\n")
        shutil.copyfile("/bin/ls", elf_path)
        with open(COMMITTED_FILES_TXT, "w", encoding="utf-8") as f:
            f.write(elf_path + "\n" + gcode_path + "\n")

        if os.path.lexists(SUMMARY_JSON):
            os.unlink(SUMMARY_JSON)
        for link in (GCODE_SYMLINK, ELF_SYMLINK):
            if os.path.lexists(link):
                os.unlink(link)

        subprocess.run(
            ["go", "build", "-o", executable, MAIN_GO],
            cwd=PARSER_DIR,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        subprocess.run(
            [executable],
            cwd=PARSER_DIR,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )

        assert os.path.exists(SUMMARY_JSON), "Executing main.go did not create summary.json"
        with open(SUMMARY_JSON, "r", encoding="utf-8") as f:
            generated = json.load(f)
        assert isinstance(generated, list), "Generated summary must be an array"
        assert len(generated) == 2, f"Generated summary must contain exactly two challenge files: {generated}"
        by_file = {item.get("file"): item for item in generated}
        assert set(by_file) == {gcode_path, elf_path}, f"Program did not process the supplied committed list: {generated}"

        gitem = by_file[gcode_path]
        assert gitem.get("type") == "gcode"
        assert "max_z" in gitem
        assert abs(gitem["max_z"] - get_max_z(gcode_path)) < 1e-6

        expected_entry, expected_machine = get_elf_info(elf_path)
        eitem = by_file[elf_path]
        assert eitem.get("type") == "elf"
        assert eitem.get("entry_point") == expected_entry
        assert eitem.get("machine") == expected_machine

        assert os.path.islink(GCODE_SYMLINK), "Program did not create the GCode symlink"
        assert os.path.realpath(GCODE_SYMLINK) == gcode_path
        assert os.path.islink(ELF_SYMLINK), "Program did not create the ELF symlink"
        assert os.path.realpath(ELF_SYMLINK) == elf_path
    finally:
        if committed_backup is None:
            if os.path.lexists(COMMITTED_FILES_TXT):
                os.unlink(COMMITTED_FILES_TXT)
        else:
            with open(COMMITTED_FILES_TXT, "wb") as f:
                f.write(committed_backup)
        if summary_backup is None:
            if os.path.lexists(SUMMARY_JSON):
                os.unlink(SUMMARY_JSON)
        else:
            with open(SUMMARY_JSON, "wb") as f:
                f.write(summary_backup)
        for link, target in link_backups.items():
            if os.path.lexists(link):
                os.unlink(link)
            if target is not None:
                os.symlink(target, link)
        for path in (gcode_path, elf_path, executable):
            if os.path.lexists(path):
                os.unlink(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
