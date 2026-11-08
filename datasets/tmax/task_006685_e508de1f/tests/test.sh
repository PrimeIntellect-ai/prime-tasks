#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import os
import pathlib
import random
import re
import secrets
import subprocess
import tempfile
import time


def test_extrusion_report():
    """Test that the extrusion_report.txt exists and contains the correct sum."""
    report_path = "/home/user/extrusion_report.txt"
    assert os.path.exists(report_path), f"File {report_path} is missing."
    assert os.path.isfile(report_path), f"{report_path} is not a file."

    with open(report_path, "r") as f:
        content = f.read().strip()

    assert content == "4.25", f"Expected extrusion_report.txt to contain '4.25', but got '{content}'."


def test_analyzer_c_code():
    """Test that analyzer.c exists and contains required flock calls."""
    source_path = "/home/user/analyzer.c"
    assert os.path.exists(source_path), f"File {source_path} is missing."
    assert os.path.isfile(source_path), f"{source_path} is not a file."

    with open(source_path, "r") as f:
        content = f.read()

    assert "flock" in content, "The source code does not contain a call to 'flock'."
    assert "LOCK_SH" in content, "The source code does not use 'LOCK_SH' for shared locking."
    assert re.search(r"#\s*include\s*[<\"]sys/file\.h[>\"]", content), \
        "The source code does not include <sys/file.h>."


def test_analyzer_executable():
    """Test that the analyzer executable was compiled."""
    exec_path = "/home/user/analyzer"
    assert os.path.exists(exec_path), f"Executable {exec_path} is missing. Did you compile the C program?"
    assert os.path.isfile(exec_path), f"{exec_path} is not a file."
    assert os.access(exec_path, os.X_OK), f"File {exec_path} is not executable."
    with open(exec_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{exec_path} is not a compiled ELF executable."


def rle_encode(text):
    data = text.encode("ascii")
    encoded = bytearray()
    i = 0
    while i < len(data):
        count = 1
        while i + count < len(data) and data[i + count] == data[i] and count < 255:
            count += 1
        encoded.extend((count, data[i]))
        i += count
    return bytes(encoded)


def make_case(rng):
    values = [rng.randint(1, 900) for _ in range(4)]
    lines = [
        f"G1 X{rng.randint(1, 80)} Y{rng.randint(1, 80)} E{values[0] / 100:.2f}",
        "G0 X20 Y20 E99.99",
        f"G1 E{values[1] / 100:.2f}",
        "G10 E88.88",
        f"G1\tX5\tE{values[2] / 100:.2f}\tY7",
        "G1 X15 Y15",
        f"  G1 Y9 E{values[3] / 100:.2f}",
    ]
    # The long newline run also verifies that adjacent RLE pairs are handled
    # correctly when a run exceeds the one-byte count limit.
    text = "\n".join(lines[:4]) + "\n" + ("\n" * 300) + "\n".join(lines[4:]) + "\n"
    return rle_encode(text), f"{sum(values) / 100:.2f}"


def read_report(expected):
    report = pathlib.Path("/home/user/extrusion_report.txt")
    assert report.is_file(), "The analyzer did not create extrusion_report.txt."
    raw = report.read_text()
    assert re.fullmatch(r"-?\d+\.\d{2}\s*", raw), \
        f"Report is not a single floating-point value with two decimal places: {raw!r}"
    assert raw.strip() == expected, f"Expected {expected}, got {raw!r}."


def run_case(executable, archive, expected, env=None):
    pathlib.Path("/home/user/docs_archive.bin").write_bytes(archive)
    report = pathlib.Path("/home/user/extrusion_report.txt")
    if report.exists():
        report.unlink()
    result = subprocess.run(
        [executable], cwd="/home/user", env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
    )
    assert result.returncode == 0, \
        f"Analyzer exited with {result.returncode}: {result.stderr.decode(errors='replace')}"
    read_report(expected)


def test_compiled_program_decompresses_parses_and_locks():
    archive_path = pathlib.Path("/home/user/docs_archive.bin")
    report_path = pathlib.Path("/home/user/extrusion_report.txt")
    original_archive = archive_path.read_bytes()
    original_report = report_path.read_bytes() if report_path.exists() else None
    work = pathlib.Path(tempfile.mkdtemp(prefix="analyzer_verify_"))
    rebuilt = work / "analyzer"
    audit_so = work / "flock_audit.so"
    audit_log = work / "flock.log"

    wrapper_source = work / "flock_audit.c"
    wrapper_source.write_text(r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/file.h>
#include <unistd.h>

int flock(int fd, int operation) {
    static int (*real_flock)(int, int) = NULL;
    if (!real_flock)
        real_flock = (int (*)(int, int))dlsym(RTLD_NEXT, "flock");
    int result = real_flock(fd, operation);
    const char *log_path = getenv("FLOCK_AUDIT");
    if (log_path) {
        char link_name[64], target[PATH_MAX];
        snprintf(link_name, sizeof(link_name), "/proc/self/fd/%d", fd);
        ssize_t n = readlink(link_name, target, sizeof(target) - 1);
        if (n >= 0) target[n] = '\0'; else target[0] = '\0';
        int out = open(log_path, O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (out >= 0) {
            dprintf(out, "%d\t%s\n", operation, target);
            close(out);
        }
    }
    return result;
}
''')

    try:
        subprocess.run(
            ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra",
             "/home/user/analyzer.c", "-o", str(rebuilt)],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        subprocess.run(
            ["gcc", "-shared", "-fPIC", str(wrapper_source), "-o", str(audit_so), "-ldl"],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )

        rng = random.Random(secrets.randbits(128))
        env = os.environ.copy()
        env["LD_PRELOAD"] = str(audit_so)
        env["FLOCK_AUDIT"] = str(audit_log)

        # Execute the submitted binary on an unpredictable archive.
        archive, expected = make_case(rng)
        run_case("/home/user/analyzer", archive, expected, env)

        # Execute a fresh build of the submitted C source on another archive.
        archive, expected = make_case(rng)
        run_case(str(rebuilt), archive, expected, env)

        records = []
        if audit_log.exists():
            for line in audit_log.read_text().splitlines():
                op, _, path = line.partition("\t")
                if op.isdigit():
                    records.append((int(op), path))
        assert any((op & fcntl.LOCK_SH) and not (op & fcntl.LOCK_EX) and
                   path == "/home/user/docs_archive.bin" for op, path in records), \
            "The running analyzer did not call flock(fd, LOCK_SH) on docs_archive.bin."

        # Hold an exclusive lock, start the analyzer, and update the same inode.
        # A correct analyzer blocks before reading and therefore sees the update.
        old_archive, _ = make_case(rng)
        new_archive, new_expected = make_case(rng)
        archive_path.write_bytes(old_archive)
        if report_path.exists():
            report_path.unlink()

        with open(archive_path, "r+b", buffering=0) as locked_file:
            fcntl.flock(locked_file.fileno(), fcntl.LOCK_EX)
            proc = subprocess.Popen(
                [str(rebuilt)], cwd="/home/user", env=env,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE
            )
            time.sleep(0.5)
            assert proc.poll() is None, \
                "Analyzer did not wait while docs_archive.bin was exclusively locked."
            locked_file.seek(0)
            locked_file.truncate()
            locked_file.write(new_archive)
            os.fsync(locked_file.fileno())
            fcntl.flock(locked_file.fileno(), fcntl.LOCK_UN)

        stdout, stderr = proc.communicate(timeout=5)
        assert proc.returncode == 0, \
            f"Analyzer failed after lock release: {stderr.decode(errors='replace')}"
        read_report(new_expected)
    finally:
        archive_path.write_bytes(original_archive)
        if original_report is None:
            if report_path.exists():
                report_path.unlink()
        else:
            report_path.write_bytes(original_report)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
