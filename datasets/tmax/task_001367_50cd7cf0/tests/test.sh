#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import pathlib
import secrets
import struct
import subprocess
import tempfile

import pytest

ORGANIZER_PATH = "/home/user/organizer"
ORGANIZER_SOURCE = "/home/user/organizer.cpp"
LIB_DIR = "/app/zres_lib-1.2.0"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"


def run(cmd, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 20)
    return subprocess.run(cmd, **kwargs)


def make_zres(path, files):
    with open(path, "wb") as f:
        f.write(struct.pack("<I", len(files)))
        for name, data in files:
            name_bytes = name.encode("utf-8")
            f.write(struct.pack("<I", len(name_bytes)))
            f.write(name_bytes)
            f.write(struct.pack("<I", len(data)))
            f.write(data)


def output_files(root):
    found = {}
    for current, dirs, files in os.walk(root):
        for name in files:
            path = os.path.join(current, name)
            rel = os.path.relpath(path, root)
            with open(path, "rb") as f:
                found[rel] = f.read()
    return found


def assert_clean_result(executable, archive, expected):
    with tempfile.TemporaryDirectory() as outdir:
        result = run([executable, archive, outdir])
        assert result.returncode == 0, (
            f"clean archive failed with {result.returncode}: "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        assert not os.path.exists(os.path.join(outdir, "metadata.log")), \
            "metadata.log was not deleted"
        assert output_files(outdir) == expected


def assert_evil_result(executable, archive, outdir, forbidden_paths):
    result = run([executable, archive, outdir])
    assert result.returncode == 1, (
        f"evil archive returned {result.returncode}: "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert "MALICIOUS ARCHIVE REJECTED" in result.stdout
    for path in forbidden_paths:
        assert not os.path.exists(path), f"archive escaped extraction directory to {path}"
    assert output_files(outdir) == {}, "extraction did not abort immediately"


def test_organizer_executable_exists():
    assert os.path.isfile(ORGANIZER_PATH), f"Executable not found at {ORGANIZER_PATH}"
    assert os.access(ORGANIZER_PATH, os.X_OK), f"File at {ORGANIZER_PATH} is not executable"
    with open(ORGANIZER_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "organizer is not a compiled executable"
    assert os.path.isfile(ORGANIZER_SOURCE), "organizer.cpp is missing"


def test_original_corpora_and_exact_clean_output():
    clean_archives = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.zres"))
    evil_archives = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.zres"))
    assert clean_archives, "No clean archives found to test."
    assert evil_archives, "No evil archives found to test."

    for archive in evil_archives:
        with tempfile.TemporaryDirectory() as tmpdir:
            result = run([ORGANIZER_PATH, archive, tmpdir])
            assert result.returncode == 1, f"{os.path.basename(archive)} was not rejected"
            assert "MALICIOUS ARCHIVE REJECTED" in result.stdout

    expected = {
        "sensor_alpha_01.bin": b"AAA",
        "sensor_beta_02.bin": b"BBB",
    }
    for archive in clean_archives:
        with tempfile.TemporaryDirectory() as tmpdir:
            result = run([ORGANIZER_PATH, archive, tmpdir])
            assert result.returncode == 0, f"{os.path.basename(archive)} failed"
            assert not os.path.exists(os.path.join(tmpdir, "metadata.log"))
            assert os.listdir(tmpdir), "no files extracted"
            if os.path.basename(archive) == "dataset1.zres":
                assert output_files(tmpdir) == expected


def test_makefile_library_and_source_build(tmp_path):
    clean = run(["make", "clean"], cwd=LIB_DIR)
    assert clean.returncode == 0, clean.stdout + clean.stderr
    built = run(["make"], cwd=LIB_DIR)
    assert built.returncode == 0, built.stdout + built.stderr
    library = os.path.join(LIB_DIR, "libzres.a")
    assert os.path.isfile(library) and os.path.getsize(library) > 0

    rebuilt = tmp_path / "organizer_rebuilt"
    compiled = run([
        "g++", "-std=c++17", "-O2", ORGANIZER_SOURCE,
        "-I", LIB_DIR, library, "-o", str(rebuilt)
    ])
    assert compiled.returncode == 0, compiled.stdout + compiled.stderr
    assert rebuilt.is_file() and os.access(rebuilt, os.X_OK)

    symbols = run(["nm", "-C", str(rebuilt)])
    assert symbols.returncode == 0
    assert "extract_archive(" in symbols.stdout, \
        "rebuilt organizer does not link the required extraction function"

    token = secrets.token_hex(8)
    archive = tmp_path / "rebuilt-clean.zres"
    metadata = (
        f"OriginalName: old_{token}_a.bin\n"
        f"NewName: renamed_{token}_a.bin\n---\n"
        f"OriginalName: old_{token}_b.bin\n"
        f"NewName: renamed_{token}_b.bin\n---\n"
    ).encode()
    make_zres(archive, [
        (f"old_{token}_a.bin", b"dynamic-A-" + token.encode()),
        (f"old_{token}_b.bin", b"\x00\x01dynamic-B"),
        (f"unchanged_{token}.dat", b"leave-me"),
        ("metadata.log", metadata),
    ])
    assert_clean_result(str(rebuilt), str(archive), {
        f"renamed_{token}_a.bin": b"dynamic-A-" + token.encode(),
        f"renamed_{token}_b.bin": b"\x00\x01dynamic-B",
        f"unchanged_{token}.dat": b"leave-me",
    })


def test_dynamic_clean_archives():
    for _ in range(2):
        token = secrets.token_hex(8)
        with tempfile.TemporaryDirectory() as work:
            archive = os.path.join(work, "clean.zres")
            metadata = (
                f"OriginalName: source_{token}_1.bin\n"
                f"NewName: result_{token}_alpha.bin\n---\n"
                f"OriginalName: source_{token}_2.bin\n"
                f"NewName: result_{token}_beta.bin\n---\n"
            ).encode()
            data1 = secrets.token_bytes(31)
            data2 = secrets.token_bytes(47)
            extra = secrets.token_bytes(13)
            make_zres(archive, [
                (f"source_{token}_1.bin", data1),
                (f"source_{token}_2.bin", data2),
                (f"unmapped_{token}.bin", extra),
                ("metadata.log", metadata),
            ])
            assert_clean_result(ORGANIZER_PATH, archive, {
                f"result_{token}_alpha.bin": data1,
                f"result_{token}_beta.bin": data2,
                f"unmapped_{token}.bin": extra,
            })


def test_dynamic_traversal_archives():
    token = secrets.token_hex(10)
    with tempfile.TemporaryDirectory() as work:
        outdir = os.path.join(work, "output")
        os.mkdir(outdir)
        escaped = os.path.join(work, f"escaped_{token}.bin")
        archive = os.path.join(work, "relative-evil.zres")
        make_zres(archive, [
            (f"../escaped_{token}.bin", b"EVIL-RELATIVE"),
            ("metadata.log", b"OriginalName: x\nNewName: y\n---\n"),
        ])
        assert_evil_result(ORGANIZER_PATH, archive, outdir, [escaped])

    token = secrets.token_hex(10)
    with tempfile.TemporaryDirectory() as work:
        outdir = os.path.join(work, "output")
        os.mkdir(outdir)
        absolute = os.path.join("/tmp", f"zres_absolute_{token}.bin")
        assert not os.path.exists(absolute)
        archive = os.path.join(work, "absolute-evil.zres")
        make_zres(archive, [
            (absolute, b"EVIL-ABSOLUTE"),
            ("metadata.log", b"OriginalName: x\nNewName: y\n---\n"),
        ])
        try:
            assert_evil_result(ORGANIZER_PATH, archive, outdir, [absolute])
        finally:
            if os.path.exists(absolute):
                os.unlink(absolute)


def test_library_directly_rejects_dynamic_traversal(tmp_path):
    harness = tmp_path / "library_harness.cpp"
    harness.write_text(r'''#include "zres.h"
#include <iostream>
#include <stdexcept>
int main(int argc, char **argv) {
    if (argc != 3) return 9;
    try {
        extract_archive(argv[1], argv[2]);
    } catch (const std::runtime_error& e) {
        if (std::string(e.what()) == "Path traversal detected") return 0;
        std::cerr << e.what();
        return 7;
    } catch (...) {
        return 8;
    }
    return 6;
}
''')
    harness_bin = tmp_path / "library_harness"
    compiled = run([
        "g++", "-std=c++17", str(harness), "-I", LIB_DIR,
        os.path.join(LIB_DIR, "libzres.a"), "-o", str(harness_bin)
    ])
    assert compiled.returncode == 0, compiled.stdout + compiled.stderr

    token = secrets.token_hex(10)
    outdir = tmp_path / "direct-output"
    outdir.mkdir()
    escaped = tmp_path / f"direct_escape_{token}.bin"
    archive = tmp_path / "direct-evil.zres"
    make_zres(archive, [
        (f"../direct_escape_{token}.bin", b"DIRECT-EVIL"),
        ("must_not_be_written.bin", b"LATE-DATA"),
    ])
    result = run([str(harness_bin), str(archive), str(outdir)])
    assert result.returncode == 0, (
        f"library did not throw runtime_error with the required message; "
        f"code={result.returncode}, stderr={result.stderr!r}"
    )
    assert not escaped.exists()
    assert output_files(outdir) == {}, "library failed to abort immediately"


def test_library_patched_source_assertions():
    zres_cpp_path = os.path.join(LIB_DIR, "zres.cpp")
    assert os.path.isfile(zres_cpp_path), "zres.cpp is missing"
    with open(zres_cpp_path, "r") as f:
        content = f.read()
    assert "Path traversal detected" in content, \
        "The library zres.cpp does not contain the required exception message 'Path traversal detected'."
    assert "throw" in content, \
        "The library zres.cpp does not appear to throw an exception for path traversal."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
