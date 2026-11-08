#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import secrets
import stat
import subprocess
import time
import zlib


def run_checked(command):
    return subprocess.run(command, capture_output=True, text=True, check=True)


def crc_from_library(path, symbol, payload):
    library = ctypes.CDLL(path)
    function = getattr(library, symbol)
    function.argtypes = [ctypes.c_void_p, ctypes.c_int]
    function.restype = ctypes.c_uint
    buffer = ctypes.create_string_buffer(payload)
    return function(ctypes.cast(buffer, ctypes.c_void_p), len(payload))


def test_libraries_built():
    """Verify that the static C library and the shared Go library have been built and are usable."""
    archive = "/app/fastcrc-1.0/libfastcrc.a"
    shared = "/app/gocrc/libgocrc.so"

    assert os.path.isfile(archive), "The static library /app/fastcrc-1.0/libfastcrc.a was not built."
    assert os.path.isfile(shared), "The shared library /app/gocrc/libgocrc.so was not built."
    assert os.path.getsize(archive) > 0, "The static C library is empty."
    assert os.path.getsize(shared) > 0, "The Go shared library is empty."

    members = run_checked(["ar", "t", archive]).stdout.splitlines()
    assert members, "The static C library contains no object files."
    archive_symbols = run_checked(["nm", "-g", archive]).stdout
    assert "fastcrc32" in archive_symbols, "The static C library does not define fastcrc32."

    # Actually link the submitted archive into a shared object. This also verifies
    # that its object code is suitable for inclusion in a shared library.
    with open("/tmp/archive_probe.c", "w") as source:
        source.write(
            '#include "/app/fastcrc-1.0/fastcrc.h"\n'
            'unsigned int probe_crc(char *data, int length) {\n'
            '    return fastcrc32(data, length);\n'
            '}\n'
        )
    run_checked([
        "gcc", "-shared", "-fPIC", "-Wl,--no-undefined",
        "/tmp/archive_probe.c", archive, "-o", "/tmp/archive_probe.so"
    ])

    elf_header = run_checked(["readelf", "-h", shared]).stdout
    assert "DYN (Shared object file)" in elf_header, "libgocrc.so is not an ELF shared object."
    dynamic_symbols = run_checked(["nm", "-D", shared]).stdout
    assert "CalculateCRC" in dynamic_symbols, "libgocrc.so does not export CalculateCRC."
    all_symbols = run_checked(["nm", shared]).stdout
    assert "fastcrc32" in all_symbols, "libgocrc.so does not contain the fastcrc implementation from the static library."

    # Exercise both submitted libraries on verifier-selected data and derive the
    # expected answers independently.
    payloads = [b"", b"abc\x00def", secrets.token_bytes(257), secrets.token_bytes(8193)]
    for payload in payloads:
        expected = zlib.crc32(payload) & 0xFFFFFFFF
        assert crc_from_library("/tmp/archive_probe.so", "probe_crc", payload) == expected
        assert crc_from_library(shared, "CalculateCRC", payload) == expected


def test_process_uploads_exists():
    """Verify that the Python integration script exists and is executable."""
    script = "/home/user/process_uploads.py"
    assert os.path.isfile(script), "/home/user/process_uploads.py does not exist."
    mode = os.stat(script).st_mode
    assert mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH), "/home/user/process_uploads.py is not executable."


def test_correctness_and_performance():
    """Verify the output matches baseline and the speedup is >= 1.5."""
    t0 = time.monotonic()
    result_base = subprocess.run(
        ["python3", "/app/baseline.py"],
        capture_output=True,
        text=True,
        check=True
    )
    t_base = time.monotonic() - t0
    baseline_output = result_base.stdout.strip()

    t0 = time.monotonic()
    result_agent = subprocess.run(
        ["python3", "/home/user/process_uploads.py"],
        capture_output=True,
        text=True,
        check=True
    )
    t_agent = time.monotonic() - t0
    agent_output = result_agent.stdout.strip()

    assert agent_output == baseline_output, f"Agent output '{agent_output}' does not match baseline output '{baseline_output}'."
    assert result_agent.stdout == agent_output + "\n", "The integration script must print only the checksum integer."

    speedup = t_base / t_agent
    assert speedup >= 1.5, f"Speedup is {speedup:.2f}x, which is below the 1.5x threshold. (Agent time: {t_agent:.2f}s, Baseline time: {t_base:.2f}s)"


def test_python_uses_calculate_crc():
    """Prove the Python script loads libgocrc.so, passes the payload, and prints CalculateCRC's return value."""
    shared = "/app/gocrc/libgocrc.so"
    backup = "/tmp/libgocrc.submitted.so"
    probe = "/tmp/libgocrc.probe.so"
    marker = "/tmp/gocrc_probe_called"

    expected_length = os.path.getsize("/app/test_payload.bin")
    expected_hash = 1469598103934665603
    with open("/app/test_payload.bin", "rb") as payload_file:
        while True:
            chunk = payload_file.read(1024 * 1024)
            if not chunk:
                break
            for byte in chunk:
                expected_hash ^= byte
                expected_hash = (expected_hash * 1099511628211) & 0xFFFFFFFFFFFFFFFF

    sentinel = 1 + secrets.randbelow(0x3FFFFFFF)
    probe_source = r'''
#include <stdint.h>
#include <stdio.h>

unsigned int CalculateCRC(char *data, int length) {
    uint64_t hash = 1469598103934665603ULL;
    for (int i = 0; i < length; ++i) {
        hash ^= (unsigned char)data[i];
        hash *= 1099511628211ULL;
    }
    int valid = length == %d && hash == 0x%016xULL;
    FILE *marker = fopen("%s", "w");
    if (marker) {
        fprintf(marker, "%%d %%016llx %%d\n", length, (unsigned long long)hash, valid);
        fclose(marker);
    }
    return valid ? %dU : 0U;
}
''' % (expected_length, expected_hash, marker, sentinel)

    with open("/tmp/gocrc_probe.c", "w") as source:
        source.write(probe_source)
    run_checked(["gcc", "-O2", "-shared", "-fPIC", "/tmp/gocrc_probe.c", "-o", probe])

    if os.path.exists(marker):
        os.unlink(marker)
    os.replace(shared, backup)
    try:
        os.replace(probe, shared)
        result = subprocess.run(
            ["python3", "/home/user/process_uploads.py"],
            capture_output=True,
            text=True,
            check=True,
            timeout=30
        )
        assert result.stdout == f"{sentinel}\n", "The Python script did not print the value returned by CalculateCRC."
        assert os.path.isfile(marker), "CalculateCRC in /app/gocrc/libgocrc.so was not called."
        fields = open(marker).read().strip().split()
        assert len(fields) == 3 and fields[2] == "1", "The script did not pass the complete /app/test_payload.bin data to CalculateCRC."
    finally:
        if os.path.exists(shared):
            os.unlink(shared)
        os.replace(backup, shared)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
