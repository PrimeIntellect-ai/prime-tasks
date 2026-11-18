#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import os
import pathlib
import secrets
import subprocess
import tempfile

import pytest

EXE = "/home/user/log_processor"
SOURCE = "/home/user/log_processor.cpp"
CSV = pathlib.Path("/home/user/critical_events.csv")


def test_cpp_file_exists():
    """Test that the C++ source file exists."""
    assert os.path.isfile(SOURCE), "The file /home/user/log_processor.cpp does not exist."


def test_executable_exists():
    """Test that the compiled executable exists and is executable."""
    assert os.path.isfile(EXE), f"The executable {EXE} does not exist."
    assert os.access(EXE, os.X_OK), f"The file {EXE} is not executable."
    with open(EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"The file {EXE} is not a compiled ELF executable."


def test_cpp_source_requirements():
    """Test that the C++ source code uses zlib and flock."""
    with open(SOURCE, "r", encoding="utf-8") as f:
        content = f.read()

    assert "gzopen" in content or "zlib.h" in content, "The source code does not appear to use zlib directly."
    assert "flock" in content, "The source code does not appear to use POSIX flock for file locking."


def test_csv_output_exists_and_correct():
    """Test that the requested archive runs produced exactly the expected events."""
    assert CSV.is_file(), f"The output file {CSV} does not exist."

    expected_lines = {
        "2023-10-25T08:05:12,CRITICAL,RAID array degraded.",
        "2023-10-26T02:45:55,CRITICAL,Kernel panic - not syncing: VFS: Unable to mount root fs."
    }

    with CSV.open("r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    actual_lines_set = set(lines)
    for expected in expected_lines:
        assert expected in actual_lines_set, f"Expected line '{expected}' not found in {CSV}."
    for line in lines:
        assert line in expected_lines, f"Unexpected line found in {CSV}: '{line}'"
    assert len(lines) == len(expected_lines), f"Expected exactly {len(expected_lines)} lines, but found {len(lines)}."


def _write_archive(path, blocks):
    text = "".join(
        "===LOG===\n"
        f"Time: {time}\n"
        f"Status: {status}\n"
        f"Details: {details}\n"
        "===END===\n"
        for time, status, details in blocks
    )
    with gzip.open(path, "wt", encoding="utf-8", newline="\n") as f:
        f.write(text)


def _read_lines():
    if not CSV.exists():
        return []
    return [line.strip() for line in CSV.read_text(encoding="utf-8").splitlines() if line.strip()]


def _build_flock_monitor(directory):
    source = pathlib.Path(directory) / "flock_monitor.c"
    library = pathlib.Path(directory) / "flock_monitor.so"
    source.write_text(r'''
#define _GNU_SOURCE
#include <sys/file.h>
#include <sys/syscall.h>
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>

int flock(int fd, int operation) {
    const char *trace = getenv("FLOCK_TRACE");
    if (trace && (operation & LOCK_EX)) {
        int out = open(trace, O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (out >= 0) {
            char marker = 'E';
            write(out, &marker, 1);
            close(out);
        }
    }
    return (int)syscall(SYS_flock, fd, operation);
}
''', encoding="utf-8")
    subprocess.run(
        ["gcc", "-shared", "-fPIC", "-O2", "-o", str(library), str(source)],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return library


def _run(archive, monitor, trace, timeout=10):
    env = os.environ.copy()
    env["LD_PRELOAD"] = str(monitor)
    env["FLOCK_TRACE"] = str(trace)
    result = subprocess.run(
        [EXE, str(archive)], env=env, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=timeout
    )
    assert result.returncode == 0, (
        f"log_processor failed for a valid gzip archive: {result.stderr}"
    )
    assert pathlib.Path(trace).exists() and "E" in pathlib.Path(trace).read_text(), (
        "The executable did not acquire an exclusive flock while processing an archive."
    )


def test_executable_parses_generated_archives_appends_and_locks():
    """Execute the submitted artifact on unpredictable gzip data and under concurrency."""
    token = secrets.token_hex(8)
    with tempfile.TemporaryDirectory(prefix="log-verifier-") as tmp:
        tmp_path = pathlib.Path(tmp)
        monitor = _build_flock_monitor(tmp)

        first_time = f"2091-01-01T00:00:{secrets.randbelow(50):02d}"
        first_detail = f"Storage controller {token} failed."
        first_expected = f"{first_time},CRITICAL,{first_detail}"
        first = tmp_path / f"first-{token}.log.gz"
        _write_archive(first, [
            ("2091-01-01T00:01:00", "INFO", f"ignore-{token}"),
            (first_time, "CRITICAL", first_detail),
            ("2091-01-01T00:02:00", "CRITICAL ", f"not-exact-{token}"),
            ("2091-01-01T00:03:00", "WARNING", f"warning-{token}"),
        ])

        second_time = f"2091-01-02T00:00:{secrets.randbelow(50):02d}"
        second_detail = f"Filesystem {secrets.token_hex(6)} is unavailable."
        second_expected = f"{second_time},CRITICAL,{second_detail}"
        second = tmp_path / f"second-{token}.log.gz"
        _write_archive(second, [(second_time, "CRITICAL", second_detail)])

        CSV.unlink(missing_ok=True)
        _run(first, monitor, tmp_path / "trace-first")
        assert _read_lines() == [first_expected]

        _run(second, monitor, tmp_path / "trace-second")
        assert _read_lines() == [first_expected, second_expected], (
            "The program must append rather than replace prior output."
        )

        CSV.unlink(missing_ok=True)
        expected = []
        processes = []
        traces = []
        for i in range(24):
            unique = secrets.token_hex(10)
            time = f"2092-02-{i + 1:02d}T12:{i:02d}:00"
            detail = f"Concurrent disk event {unique}."
            expected.append(f"{time},CRITICAL,{detail}")
            archive = tmp_path / f"concurrent-{unique}.gz"
            _write_archive(archive, [
                (time, "CRITICAL", detail),
                (time, "INFO", f"ignored-{unique}"),
            ])
            trace = tmp_path / f"trace-{i}"
            traces.append(trace)
            env = os.environ.copy()
            env["LD_PRELOAD"] = str(monitor)
            env["FLOCK_TRACE"] = str(trace)
            processes.append(subprocess.Popen(
                [EXE, str(archive)], env=env,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
            ))

        for process in processes:
            stdout, stderr = process.communicate(timeout=15)
            assert process.returncode == 0, f"Concurrent invocation failed: {stderr}"
        for trace in traces:
            assert trace.exists() and "E" in trace.read_text(), (
                "Every archive-processing invocation must acquire an exclusive flock."
            )

        actual = _read_lines()
        assert len(actual) == len(expected), "Concurrent appends lost or corrupted CSV records."
        assert set(actual) == set(expected), "Concurrent output did not match generated CRITICAL records."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
