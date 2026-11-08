#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import struct
import subprocess
import tempfile
import uuid

import pytest

VENDORED = "/app/vendored/pyelftools-0.31"
SCRIPT = "/home/user/elf_filter.py"
REPORT = "/home/user/elf_report.json"

INSTRUMENT_DIR = tempfile.mkdtemp(prefix="elf_instrument_")
with open(os.path.join(INSTRUMENT_DIR, "sitecustomize.py"), "w") as f:
    f.write(r'''
import os
from elftools.elf.elffile import ELFFile

_original_init = ELFFile.__init__

def _traced_init(self, *args, **kwargs):
    trace = os.environ.get("ELF_TRACE_FILE")
    if trace:
        with open(trace, "a") as out:
            out.write("1\n")
    return _original_init(self, *args, **kwargs)

ELFFile.__init__ = _traced_init
''')


def test_perturbation_fixed():
    elffile_path = "/app/vendored/pyelftools-0.31/elftools/elf/elffile.py"
    assert os.path.isfile(elffile_path), f"File {elffile_path} does not exist."

    with open(elffile_path, "rb") as f:
        content = f.read()

    assert b"\\x7fFLE" not in content, "The perturbation (b'\\x7fFLE') is still present in elffile.py."
    assert b"\\x7fELF" in content, "The correct ELF magic (b'\\x7fELF') was not restored in elffile.py."


def files_under(target_dir):
    result = []
    for root, _, names in os.walk(target_dir):
        for name in names:
            result.append(os.path.abspath(os.path.join(root, name)))
    return result


def run_script_and_get_report(target_dir):
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."

    if os.path.exists(REPORT):
        os.remove(REPORT)

    trace_path = os.path.join(tempfile.mkdtemp(prefix="elf_trace_"), "calls.log")
    env = os.environ.copy()
    old_pythonpath = env.get("PYTHONPATH", "")
    env["PYTHONPATH"] = os.pathsep.join(
        p for p in (INSTRUMENT_DIR, VENDORED, old_pythonpath) if p
    )
    env["ELF_TRACE_FILE"] = trace_path

    result = subprocess.run(
        ["python3", SCRIPT, target_dir],
        capture_output=True,
        text=True,
        env=env,
    )

    assert result.returncode == 0, (
        f"Script failed on {target_dir}:\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    )
    assert os.path.isfile(REPORT), f"Script did not produce {REPORT} after running on {target_dir}."

    with open(REPORT, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT} does not contain valid JSON.")

    assert isinstance(report, dict), "The report must contain a JSON dictionary."

    expected_attempts = len(files_under(target_dir))
    try:
        with open(trace_path, "r") as f:
            parser_calls = sum(1 for line in f if line.strip() == "1")
    except FileNotFoundError:
        parser_calls = 0
    assert parser_calls >= expected_attempts, (
        f"ELFFile was initialized only {parser_calls} times for {expected_attempts} files; "
        "every discovered file must be parsed with the vendored ELFFile."
    )

    return report


def assert_exact_report(report, expected):
    assert set(report) == set(expected), (
        f"Report paths differ from recursively discovered files. "
        f"Missing: {sorted(set(expected) - set(report))}; "
        f"extra: {sorted(set(report) - set(expected))}"
    )
    assert report == expected


def test_clean_corpus():
    clean_dir = "/home/user/elf_storage/clean"
    report = run_script_and_get_report(clean_dir)

    expected_files = ["ls_bin", "cat_bin", "echo_bin"]
    failed_files = []

    for fname in expected_files:
        abs_path = os.path.join(clean_dir, fname)
        if abs_path not in report:
            failed_files.append(f"{fname} (missing from report)")
        elif report[abs_path] != "preserve":
            failed_files.append(f"{fname} (mapped to '{report[abs_path]}', expected 'preserve')")

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(expected_files)} clean files modified/rejected: "
            + ", ".join(failed_files)
        )

    expected = {os.path.join(clean_dir, name): "preserve" for name in expected_files}
    assert_exact_report(report, expected)


def test_evil_corpus():
    evil_dir = "/home/user/elf_storage/evil"
    report = run_script_and_get_report(evil_dir)

    expected_files = ["corrupted_magic.elf", "bad_shoff.elf", "bloated.elf"]
    failed_files = []

    for fname in expected_files:
        abs_path = os.path.join(evil_dir, fname)
        if abs_path not in report:
            failed_files.append(f"{fname} (missing from report)")
        elif report[abs_path] != "delete":
            failed_files.append(f"{fname} (mapped to '{report[abs_path]}', expected 'delete')")

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(expected_files)} evil files bypassed: "
            + ", ".join(failed_files)
        )

    expected = {os.path.join(evil_dir, name): "delete" for name in expected_files}
    assert_exact_report(report, expected)


def make_bad_section_offset(source, destination):
    shutil.copy2(source, destination)
    with open(destination, "r+b") as f:
        ident = f.read(16)
        assert ident[:4] == b"\x7fELF"
        elf_class = ident[4]
        data_encoding = ident[5]
        endian = "<" if data_encoding == 1 else ">"
        if elf_class == 2:
            offset, fmt, value = 40, endian + "Q", (1 << 64) - 1
        else:
            offset, fmt, value = 32, endian + "I", (1 << 32) - 1
        f.seek(offset)
        f.write(struct.pack(fmt, value))


def test_unseen_recursive_corpora_and_exact_output():
    base = tempfile.mkdtemp(prefix="unseen_elf_corpus_")
    clean_dir = os.path.join(base, "clean_" + uuid.uuid4().hex)
    evil_dir = os.path.join(base, "evil_" + uuid.uuid4().hex)
    clean_nested = os.path.join(clean_dir, "deep", uuid.uuid4().hex)
    evil_nested = os.path.join(evil_dir, "deep", uuid.uuid4().hex)
    os.makedirs(clean_nested)
    os.makedirs(evil_nested)

    clean_a = os.path.join(clean_dir, "valid_" + uuid.uuid4().hex)
    clean_b = os.path.join(clean_nested, "valid with spaces " + uuid.uuid4().hex)
    shutil.copy2("/bin/true", clean_a)
    shutil.copy2("/bin/echo", clean_b)

    corrupt_magic = os.path.join(evil_dir, "invalid_" + uuid.uuid4().hex)
    with open(corrupt_magic, "wb") as f:
        f.write(os.urandom(37))

    bad_offset = os.path.join(evil_nested, "offset_" + uuid.uuid4().hex)
    make_bad_section_offset("/bin/true", bad_offset)

    bloated = os.path.join(evil_nested, "bloat_" + uuid.uuid4().hex)
    shutil.copy2("/bin/true", bloated)
    payload = os.path.join(base, "payload_" + uuid.uuid4().hex)
    with open(payload, "wb") as f:
        f.write(os.urandom(29))
    subprocess.run(
        ["objcopy", "--add-section", f".storage_bloat={payload}", bloated],
        check=True,
        capture_output=True,
        text=True,
    )

    clean_report = run_script_and_get_report(clean_dir)
    assert_exact_report(clean_report, {
        os.path.abspath(clean_a): "preserve",
        os.path.abspath(clean_b): "preserve",
    })

    evil_report = run_script_and_get_report(evil_dir)
    assert_exact_report(evil_report, {
        os.path.abspath(corrupt_magic): "delete",
        os.path.abspath(bad_offset): "delete",
        os.path.abspath(bloated): "delete",
    })
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
