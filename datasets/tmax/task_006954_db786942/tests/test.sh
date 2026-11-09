#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import builtins
import gzip
import io
import os
import runpy
import shutil
import tempfile
import uuid
from pathlib import Path
from unittest.mock import patch


def test_critical_summary_exists_and_content_correct():
    summary_path = "/home/user/critical_summary.log"
    assert os.path.isfile(summary_path), f"The file {summary_path} does not exist."

    expected_lines = [
        "[CRITICAL] Database connection lost",
        "[CRITICAL] Disk space critically low on /dev/sda1",
        "[CRITICAL] Unhandled exception in worker thread"
    ]

    with open(summary_path, 'r') as f:
        content = f.read().strip().splitlines()

    assert content == expected_lines, "The content of critical_summary.log does not match the expected extracted [CRITICAL] lines."


def test_script_exists():
    script_path = "/home/user/extract_critical.py"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."


def test_script_atomic_write_and_gzip():
    script_path = "/home/user/extract_critical.py"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."

    with open(script_path, 'r') as f:
        code = f.read()

    assert "gzip" in code, "The script does not appear to use the 'gzip' module."

    has_atomic_move = any(func in code for func in ["os.replace", "os.rename", "shutil.move"])
    assert has_atomic_move, "The script does not appear to use an atomic write pattern (os.replace, os.rename, or shutil.move)."


def test_script_processes_changed_gzip_files_streamingly_and_atomically():
    script_path = "/home/user/extract_critical.py"
    raw_path = Path("/home/user/raw_logs")
    summary_path = Path("/home/user/critical_summary.log")
    backup_root = Path(tempfile.mkdtemp(prefix="critical-verifier-"))
    backup_raw = backup_root / "raw_logs"
    original_summary = summary_path.read_bytes() if summary_path.exists() else None
    token = uuid.uuid4().hex

    os.rename(raw_path, backup_raw)
    raw_path.mkdir()

    fixtures = {
        "z_last.log.gz": [
            "ordinary z line\n",
            f"prefix [CRITICAL] z-{token}\n",
        ],
        "a_first.log.gz": [
            f"[CRITICAL] a-{token}\n",
            f"[critical] wrong-case-{token}\n",
            f"CRITICAL without brackets {token}\n",
        ],
        "m_middle.log.gz": [
            f"before [CRITICAL] middle-{token} after\n",
            "ordinary middle line\n",
        ],
        "ignored.txt.gz": [
            f"[CRITICAL] must-not-appear-{token}\n",
        ],
    }

    for name, lines in fixtures.items():
        with gzip.open(raw_path / name, "wt", encoding="utf-8") as handle:
            handle.writelines(lines)

    expected = (
        f"[CRITICAL] a-{token}\n"
        f"before [CRITICAL] middle-{token} after\n"
        f"prefix [CRITICAL] z-{token}\n"
    ).encode("utf-8")
    sentinel = f"old-complete-output-{token}\n".encode("utf-8")
    summary_path.write_bytes(sentinel)

    original_gzip_open = gzip.open
    original_gzip_file = gzip.GzipFile
    original_open = builtins.open
    original_io_open = io.open
    original_os_open = os.open
    original_replace = os.replace
    original_rename = os.rename
    original_move = shutil.move
    gzip_activity = []
    atomic_events = []
    final_abs = os.path.abspath(os.fspath(summary_path))

    class TrackingGzipFile(original_gzip_file):
        def __init__(self, *args, **kwargs):
            gzip_activity.append("GzipFile")
            super().__init__(*args, **kwargs)

        def read(self, size=-1):
            assert size is not None and size >= 0, "gzip input was read into memory in one unbounded read"
            return super().read(size)

        def readlines(self, *args, **kwargs):
            raise AssertionError("gzip input must be processed line-by-line, not with readlines()")

    class StreamGuard:
        def __init__(self, wrapped):
            self._wrapped = wrapped

        def __enter__(self):
            self._wrapped.__enter__()
            return self

        def __exit__(self, *args):
            return self._wrapped.__exit__(*args)

        def __iter__(self):
            return self

        def __next__(self):
            return next(self._wrapped)

        def readline(self, *args, **kwargs):
            return self._wrapped.readline(*args, **kwargs)

        def read(self, size=-1):
            assert size is not None and size >= 0, "gzip input was read into memory in one unbounded read"
            return self._wrapped.read(size)

        def readlines(self, *args, **kwargs):
            raise AssertionError("gzip input must be processed line-by-line, not with readlines()")

        def __getattr__(self, name):
            return getattr(self._wrapped, name)

    def tracking_gzip_open(*args, **kwargs):
        gzip_activity.append("open")
        return StreamGuard(original_gzip_open(*args, **kwargs))

    def is_final(path):
        if isinstance(path, int):
            return False
        try:
            return os.path.abspath(os.fsdecode(os.fspath(path))) == final_abs
        except (TypeError, ValueError):
            return False

    def mode_writes(mode):
        return any(flag in str(mode) for flag in ("w", "a", "x", "+"))

    def guarded_open(file, mode="r", *args, **kwargs):
        assert not (is_final(file) and mode_writes(mode)), "final output was opened directly for writing"
        return original_open(file, mode, *args, **kwargs)

    def guarded_io_open(file, mode="r", *args, **kwargs):
        assert not (is_final(file) and mode_writes(mode)), "final output was opened directly for writing"
        return original_io_open(file, mode, *args, **kwargs)

    def guarded_os_open(path, flags, *args, **kwargs):
        write_flags = os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_TRUNC | os.O_APPEND
        assert not (is_final(path) and flags & write_flags), "final output was opened directly for writing"
        return original_os_open(path, flags, *args, **kwargs)

    def validate_atomic_source(src, dst):
        if not is_final(dst):
            return False
        src_abs = os.path.abspath(os.fsdecode(os.fspath(src)))
        assert src_abs != final_abs, "atomic replacement must use a separate temporary file"
        assert summary_path.read_bytes() == sentinel, "final output changed before the atomic replacement"
        assert os.path.isfile(src_abs), "atomic replacement source is not a temporary file"
        with original_open(src_abs, "rb") as handle:
            assert handle.read() == expected, "temporary file did not contain the complete expected output"
        src_real = os.path.realpath(src_abs)
        for fd in os.listdir("/proc/self/fd"):
            try:
                if os.path.realpath(os.readlink(f"/proc/self/fd/{fd}")) == src_real:
                    raise AssertionError("temporary output file was not closed before atomic replacement")
            except (FileNotFoundError, OSError):
                pass
        atomic_events.append((src_abs, final_abs))
        return True

    def tracking_replace(src, dst, *args, **kwargs):
        validate_atomic_source(src, dst)
        return original_replace(src, dst, *args, **kwargs)

    def tracking_rename(src, dst, *args, **kwargs):
        validate_atomic_source(src, dst)
        return original_rename(src, dst, *args, **kwargs)

    def tracking_move(src, dst, *args, **kwargs):
        validate_atomic_source(src, dst)
        return original_move(src, dst, *args, **kwargs)

    try:
        with patch.object(gzip, "GzipFile", TrackingGzipFile), \
             patch.object(gzip, "open", tracking_gzip_open), \
             patch.object(builtins, "open", guarded_open), \
             patch.object(io, "open", guarded_io_open), \
             patch.object(os, "open", guarded_os_open), \
             patch.object(os, "replace", tracking_replace), \
             patch.object(os, "rename", tracking_rename), \
             patch.object(shutil, "move", tracking_move):
            try:
                runpy.run_path(script_path, run_name="__main__")
            except SystemExit as exc:
                assert exc.code in (None, 0), f"script exited unsuccessfully with status {exc.code}"

        assert gzip_activity, "the submitted script did not open the gzip inputs through Python's gzip module"
        assert atomic_events, "the submitted script did not atomically rename/replace a temporary file onto the destination"
        assert summary_path.read_bytes() == expected, "script output was incorrect for changed gzip inputs"
    finally:
        if raw_path.exists():
            shutil.rmtree(raw_path)
        os.rename(backup_raw, raw_path)
        if original_summary is None:
            summary_path.unlink(missing_ok=True)
        else:
            summary_path.write_bytes(original_summary)
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
