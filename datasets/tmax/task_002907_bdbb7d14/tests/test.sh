#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import glob
import importlib.util
import os
import secrets
import shutil
import struct
import subprocess
import sys
import zlib

PROJECT_DIR = "/home/user/project"
SRC_DIR = os.path.join(PROJECT_DIR, "src")
SCRIPT_DIR = os.path.join(PROJECT_DIR, "scripts")
DATA_DIR = os.path.join(PROJECT_DIR, "data")
LIB_PATH = os.path.join(PROJECT_DIR, "lib", "libprocessor.so")
LOG_PATH = os.path.join(PROJECT_DIR, "output.log")

EXPECTED_PROCESSOR_C = b'''#include <stdint.h>\n#include <stdio.h>\n#include <string.h>\n\nstruct Record {\n    int32_t id;\n    float value;\n    char name[16];\n};\n\nvoid process_record(struct Record* rec, char* out_buf) {\n    sprintf(out_buf, "ID:%d|VAL:%.2f|NAME:%s", rec->id, rec->value, rec->name);\n}\n'''


def clear_data():
    os.makedirs(DATA_DIR, exist_ok=True)
    for path in glob.glob(os.path.join(DATA_DIR, "*.dat")):
        os.unlink(path)


def write_record(path, ident, value, name, valid=True):
    payload = struct.pack("<if16s", ident, value, name.encode("utf-8"))
    checksum = zlib.crc32(payload) & 0xffffffff
    if not valid:
        checksum = (checksum + 1) & 0xffffffff
    with open(path, "wb") as f:
        f.write(struct.pack("<I", checksum))
        f.write(payload)


def run_script():
    return subprocess.run(
        [sys.executable, "process.py"],
        cwd=SCRIPT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
        check=False,
    )


def read_nonempty_lines():
    with open(LOG_PATH, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def test_01_makefile_builds_real_shared_processor_library():
    processor_path = os.path.join(SRC_DIR, "processor.c")
    with open(processor_path, "rb") as f:
        assert f.read() == EXPECTED_PROCESSOR_C, "src/processor.c was modified"

    # The Makefile itself must create the missing output directory and build there.
    shutil.rmtree(os.path.join(PROJECT_DIR, "lib"), ignore_errors=True)
    result = subprocess.run(
        ["make", "-B"], cwd=SRC_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30,
    )
    assert result.returncode == 0, f"Makefile build failed:\n{result.stdout}"

    # Preserve the original existence and ELF assertions.
    assert os.path.isfile(LIB_PATH), f"Shared library {LIB_PATH} does not exist. Did you compile it?"
    with open(LIB_PATH, "rb") as f:
        magic = f.read(4)
        assert magic == b"\x7fELF", f"File {LIB_PATH} is not a valid ELF binary."

    elf_header = subprocess.check_output(["readelf", "-h", LIB_PATH], text=True)
    assert "DYN (Shared object file)" in elf_header, "libprocessor.so is not an ELF shared object"

    # Exercise the exported function rather than trusting the filename or ELF magic.
    lib = ctypes.CDLL(LIB_PATH)

    class Record(ctypes.Structure):
        _fields_ = [
            ("id", ctypes.c_int32),
            ("value", ctypes.c_float),
            ("name", ctypes.c_char * 16),
        ]

    fn = lib.process_record
    fn.argtypes = [ctypes.POINTER(Record), ctypes.c_char_p]
    fn.restype = None
    ident = secrets.randbelow(1000000) + 1000
    rec = Record(ident, 17.25, b"elfcheck")
    out = ctypes.create_string_buffer(256)
    fn(ctypes.byref(rec), out)
    assert out.value.decode() == f"ID:{ident}|VAL:17.25|NAME:elfcheck"


def test_02_python_declares_the_required_ctypes_abi():
    old_cwd = os.getcwd()
    try:
        os.chdir(SCRIPT_DIR)
        spec = importlib.util.spec_from_file_location("submitted_process", os.path.join(SCRIPT_DIR, "process.py"))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
    finally:
        os.chdir(old_cwd)

    structures = []
    for value in vars(module).values():
        if isinstance(value, type) and issubclass(value, ctypes.Structure) and value is not ctypes.Structure:
            fields = getattr(value, "_fields_", None)
            if fields == [
                ("id", ctypes.c_int32),
                ("value", ctypes.c_float),
                ("name", ctypes.c_char * 16),
            ]:
                structures.append(value)
    assert structures, "process.py does not define the required ctypes Record structure"
    record_type = structures[0]
    assert ctypes.sizeof(record_type) == 24
    assert record_type.id.offset == 0 and record_type.value.offset == 4 and record_type.name.offset == 8

    assert isinstance(getattr(module, "lib", None), ctypes.CDLL), "process.py must load the shared library with ctypes"
    fn = module.lib.process_record
    assert fn.restype is None, "process_record.restype must be set to None"
    assert fn.argtypes is not None and len(fn.argtypes) == 2, "process_record.argtypes must be declared"
    assert fn.argtypes[0] == ctypes.POINTER(record_type), "First process_record argument must point to Record"
    assert fn.argtypes[1] in (ctypes.c_char_p, ctypes.POINTER(ctypes.c_char)), \
        "Second process_record argument must be a C character buffer pointer"


def test_03_original_records_and_output_assertions():
    clear_data()
    write_record(os.path.join(DATA_DIR, "record_1.dat"), 1, 3.14, "alpha", True)
    write_record(os.path.join(DATA_DIR, "record_2.dat"), 2, 2.71, "beta", True)
    write_record(os.path.join(DATA_DIR, "record_3.dat"), 3, 1.41, "gamma", False)
    if os.path.exists(LOG_PATH):
        os.unlink(LOG_PATH)

    result = run_script()
    assert result.returncode == 0, f"process.py failed:\nstdout={result.stdout}\nstderr={result.stderr}"

    # Preserve all original output assertions.
    assert os.path.isfile(LOG_PATH), f"Output log {LOG_PATH} does not exist. Did you run process.py?"
    lines = read_nonempty_lines()
    assert len(lines) == 2, f"Expected exactly 2 lines in output.log, but found {len(lines)}."
    expected_lines = {
        "ID:1|VAL:3.14|NAME:alpha",
        "ID:2|VAL:2.71|NAME:beta",
    }
    actual_lines = set(lines)
    missing = expected_lines - actual_lines
    assert not missing, f"Missing expected lines in output.log: {missing}"
    unexpected = actual_lines - expected_lines
    assert not unexpected, f"Found unexpected lines in output.log (perhaps invalid files were processed?): {unexpected}"
    for line in lines:
        assert "ID:3" not in line, "Found data from invalid file (record_3.dat) in output.log."


def test_04_random_crc_inputs_are_unpacked_and_passed_to_c():
    # Swap in a verifier-generated implementation of the same ABI. Its unpredictable
    # prefix proves process.py actually calls process_record rather than formatting in Python.
    backup = "/tmp/original_libprocessor.so"
    shutil.copy2(LIB_PATH, backup)
    token = secrets.token_hex(8)
    probe_c = "/tmp/probe_processor.c"
    with open(probe_c, "w", encoding="utf-8") as f:
        f.write(f'''#include <stdint.h>\n#include <stdio.h>\nstruct Record {{ int32_t id; float value; char name[16]; }};\nvoid process_record(struct Record *rec, char *out_buf) {{\n    sprintf(out_buf, "{token}|ID:%d|VAL:%.2f|NAME:%s", rec->id, rec->value, rec->name);\n}}\n''')

    try:
        subprocess.run(["gcc", "-shared", "-fPIC", probe_c, "-o", LIB_PATH], check=True, timeout=30)
        clear_data()

        valid = []
        for index in range(3):
            ident = secrets.randbelow(900000) + 10000 + index
            value = float(secrets.randbelow(80) + 1) + (0.25 if index % 2 == 0 else 0.75)
            name = "n" + secrets.token_hex(4)
            filename = os.path.join(DATA_DIR, f"random_{secrets.token_hex(4)}.dat")
            write_record(filename, ident, value, name, True)
            valid.append(f"{token}|ID:{ident}|VAL:{value:.2f}|NAME:{name}")

        for index in range(2):
            ident = secrets.randbelow(900000) + 1000000
            filename = os.path.join(DATA_DIR, f"corrupt_{secrets.token_hex(4)}.dat")
            write_record(filename, ident, 41.25 + index, "bad" + str(index), False)

        sentinel = "existing-line-" + secrets.token_hex(5)
        with open(LOG_PATH, "w", encoding="utf-8") as f:
            f.write(sentinel + "\n")

        result = run_script()
        assert result.returncode == 0, f"process.py failed on generated data:\nstdout={result.stdout}\nstderr={result.stderr}"
        lines = read_nonempty_lines()
        assert lines.count(sentinel) == 1, "process.py did not append to the existing output.log"
        produced = [line for line in lines if line != sentinel]
        assert len(produced) == len(valid), "Invalid-CRC files were processed or valid files were skipped"
        assert sorted(produced) == sorted(valid), "Generated records were not correctly unpacked and passed to the C function"
    finally:
        shutil.copy2(backup, LIB_PATH)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
