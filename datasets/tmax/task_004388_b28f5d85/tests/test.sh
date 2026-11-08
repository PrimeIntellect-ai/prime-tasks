#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import json
import os
import secrets
import struct
import subprocess
import tempfile
import time
import zipfile

import pytest

REF_SCRIPT = "/home/user/reference_scanner.py"
CPP_BINARY = "/home/user/artifact_scanner"
CPP_SOURCE = "/home/user/artifact_scanner.cpp"
OUTPUT_CSV = "/home/user/scan_results.csv"
CONFIG = "/home/user/repo_config.json"
INSTALL = "/app/vendor/install"


def run_checked(argv, message):
    try:
        return subprocess.run(argv, check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as exc:
        pytest.fail(f"{message}: {exc.stderr or exc.stdout}")


def read_nonempty_lines(path):
    with open(path, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def test_artifact_scanner_correctness_and_speedup():
    # Preserve the original fixed-repository correctness and performance checks.
    assert os.path.isfile(CPP_BINARY), f"Compiled executable not found at {CPP_BINARY}"
    assert os.access(CPP_BINARY, os.X_OK), f"File is not executable: {CPP_BINARY}"

    if os.path.exists(OUTPUT_CSV):
        os.remove(OUTPUT_CSV)

    start_time_ref = time.time()
    run_checked(["python3", REF_SCRIPT], "Reference scanner failed to run")
    ref_time = time.time() - start_time_ref

    assert os.path.isfile(OUTPUT_CSV), f"Reference scanner did not produce {OUTPUT_CSV}"
    ref_results = read_nonempty_lines(OUTPUT_CSV)
    os.remove(OUTPUT_CSV)

    start_time_cpp = time.time()
    run_checked([CPP_BINARY], "C++ scanner failed to run")
    cpp_time = time.time() - start_time_cpp

    assert os.path.isfile(OUTPUT_CSV), f"C++ scanner did not produce {OUTPUT_CSV}"
    cpp_results = read_nonempty_lines(OUTPUT_CSV)

    assert len(ref_results) == 10000, f"Expected 10,000 lines from reference, got {len(ref_results)}"
    assert len(cpp_results) == 10000, f"Expected 10,000 lines from C++ scanner, got {len(cpp_results)}"

    ref_set = set(ref_results)
    cpp_set = set(cpp_results)
    missing_in_cpp = ref_set - cpp_set
    extra_in_cpp = cpp_set - ref_set
    if missing_in_cpp or extra_in_cpp:
        error_msg = "C++ scanner output does not match reference output.\n"
        if missing_in_cpp:
            error_msg += f"Missing entries (sample): {list(missing_in_cpp)[:5]}\n"
        if extra_in_cpp:
            error_msg += f"Extra/incorrect entries (sample): {list(extra_in_cpp)[:5]}\n"
        pytest.fail(error_msg)

    speedup = ref_time / cpp_time
    assert speedup >= 3.0, (
        f"Performance threshold not met! Reference time: {ref_time:.3f}s, "
        f"C++ time: {cpp_time:.3f}s. Speedup: {speedup:.2f}x (Required: >= 3.0x)"
    )


def test_fixed_library_is_installed_and_scanner_is_cpp_using_it():
    library = os.path.join(INSTALL, "lib", "libarchive_custom.a")
    header = os.path.join(INSTALL, "include", "archive_reader.h")

    assert os.path.isfile(CPP_SOURCE), f"C++ source not found at {CPP_SOURCE}"
    assert os.path.isfile(library), f"Installed library not found at {library}"
    assert os.path.isfile(header), f"Installed header not found at {header}"

    with open(CPP_BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "artifact_scanner is not a compiled ELF executable"

    source = open(CPP_SOURCE, "r", encoding="utf-8", errors="replace").read()
    assert "archive_reader.h" in source, "Scanner source does not include the custom library header"
    assert "ArchiveReader" in source, "Scanner source does not use ArchiveReader"

    archive_listing = run_checked(["ar", "t", library], "Installed static library is invalid").stdout
    assert "archive_reader" in archive_listing, "Installed archive lacks the archive reader object"

    symbols = run_checked(["nm", "-C", CPP_BINARY], "Could not inspect scanner symbols").stdout
    assert "ArchiveReader::ArchiveReader" in symbols, "Scanner binary is not linked with ArchiveReader"

    # Compile and run a fresh consumer against the installed package, proving that
    # the repaired installation is usable rather than merely an empty placeholder.
    with tempfile.TemporaryDirectory(prefix="library_probe_") as td:
        probe_cpp = os.path.join(td, "probe.cpp")
        probe_bin = os.path.join(td, "probe")
        with open(probe_cpp, "w", encoding="utf-8") as f:
            f.write(r'''#include <archive_reader.h>
#include <cstdint>
int main() {
    uint8_t data[23] = {};
    data[1]=0x50; data[2]=0x4b; data[3]=0x05; data[4]=0x06;
    ArchiveReader reader(data, sizeof(data));
    return reader.is_valid() ? 0 : 1;
}
''')
        run_checked([
            "g++", "-std=c++17", probe_cpp,
            "-I" + os.path.join(INSTALL, "include"),
            "-L" + os.path.join(INSTALL, "lib"),
            "-larchive_custom", "-lz", "-o", probe_bin,
        ], "Could not compile against installed libarchive_custom")
        run_checked([probe_bin], "Installed libarchive_custom failed at runtime")


def make_zip(payload):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("payload.bin", payload)
    return buf.getvalue()


def test_scanner_handles_fresh_unseen_repository_and_configuration():
    # These inputs and their expected answers are generated only after the agent
    # has finished, so a binary that copies a cached reference CSV cannot pass.
    with open(CONFIG, "rb") as f:
        original_config = f.read()

    magic = secrets.token_bytes(4)
    while magic == bytes.fromhex("41525400"):
        magic = secrets.token_bytes(4)
    good_header = magic + secrets.token_bytes(12)
    bad_header = bytes([magic[0] ^ 0xFF]) + magic[1:] + secrets.token_bytes(12)

    expected = set()
    with tempfile.TemporaryDirectory(prefix="artifact_repo_") as repo:
        count = 27 + secrets.randbelow(14)
        for i in range(count):
            nested = os.path.join(repo, f"level_{i % 5}", f"branch_{i % 3}")
            os.makedirs(nested, exist_ok=True)
            path = os.path.join(nested, f"unseen_{secrets.token_hex(5)}.art")

            kind = i % 5
            valid_zip = make_zip(secrets.token_bytes(20 + secrets.randbelow(200)))
            if kind in (0, 1):
                data = good_header + valid_zip
                status = "VALID"
            elif kind == 2:
                data = bad_header + valid_zip
                status = "BAD_HEADER"
            elif kind == 3:
                data = secrets.token_bytes(secrets.randbelow(16))
                status = "BAD_HEADER"
            else:
                # No ZIP end-of-central-directory record: unambiguously corrupt.
                data = good_header + b"PK\x03\x04" + secrets.token_bytes(11 + secrets.randbelow(30))
                status = "CORRUPT_ARCHIVE"

            with open(path, "wb") as f:
                f.write(data)
            expected.add(f"{path},{status}")

        # Files without the exact .art suffix must not appear in the report.
        with open(os.path.join(repo, "ignored.bin"), "wb") as f:
            f.write(good_header + make_zip(b"ignored"))
        with open(os.path.join(repo, "ignored.ART"), "wb") as f:
            f.write(good_header + make_zip(b"ignored"))

        replacement = {
            "target_dir": repo,
            "expected_magic": "0x" + magic.hex(),
        }

        try:
            with open(CONFIG, "w", encoding="utf-8") as f:
                json.dump(replacement, f)
            if os.path.exists(OUTPUT_CSV):
                os.remove(OUTPUT_CSV)

            run_checked([CPP_BINARY], "Scanner failed on fresh repository")
            assert os.path.isfile(OUTPUT_CSV), "Scanner did not create CSV for fresh repository"
            actual_lines = read_nonempty_lines(OUTPUT_CSV)
            assert len(actual_lines) == len(expected), (
                f"Expected {len(expected)} fresh results, got {len(actual_lines)}"
            )
            assert len(actual_lines) == len(set(actual_lines)), "CSV contains duplicate entries"
            assert set(actual_lines) == expected, "Scanner produced incorrect results for fresh inputs"
        finally:
            with open(CONFIG, "wb") as f:
                f.write(original_config)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
