#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'RUNNER_EOF' > /tmp/run_agent_script.py
import builtins
import io
import os
import runpy
import sys
import zipfile

_real_open = builtins.open
_real_io_open = io.open

class GuardedLogFile:
    def __init__(self, wrapped):
        self._wrapped = wrapped

    def read(self, size=-1):
        if size is None or size < 0:
            raise MemoryError("application.log must not be read into memory all at once")
        return self._wrapped.read(size)

    def read1(self, size=-1):
        if size is None or size < 0:
            raise MemoryError("application.log must not be read into memory all at once")
        return self._wrapped.read1(size)

    def readall(self):
        raise MemoryError("application.log must not be read into memory all at once")

    def __iter__(self):
        return self

    def __next__(self):
        return next(self._wrapped)

    def __enter__(self):
        self._wrapped.__enter__()
        return self

    def __exit__(self, *args):
        return self._wrapped.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._wrapped, name)


def should_guard(file, mode):
    try:
        path = os.fspath(file)
    except TypeError:
        return False
    if isinstance(path, bytes):
        path = os.fsdecode(path)
    return "r" in mode and os.path.basename(path) == "application.log"


def guarded_open(file, mode="r", *args, **kwargs):
    result = _real_open(file, mode, *args, **kwargs)
    return GuardedLogFile(result) if should_guard(file, mode) else result


def guarded_io_open(file, mode="r", *args, **kwargs):
    result = _real_io_open(file, mode, *args, **kwargs)
    return GuardedLogFile(result) if should_guard(file, mode) else result

builtins.open = guarded_open
io.open = guarded_io_open

_zip_read = zipfile.ZipExtFile.read
_zip_read1 = zipfile.ZipExtFile.read1

def is_application_member(obj):
    name = getattr(obj, "name", getattr(obj, "orig_filename", ""))
    return os.path.basename(str(name)) == "application.log"


def guarded_zip_read(self, n=-1):
    if is_application_member(self) and (n is None or n < 0):
        raise MemoryError("application.log must not be read into memory all at once")
    return _zip_read(self, n)


def guarded_zip_read1(self, n):
    if is_application_member(self) and (n is None or n < 0):
        raise MemoryError("application.log must not be read into memory all at once")
    return _zip_read1(self, n)

zipfile.ZipExtFile.read = guarded_zip_read
zipfile.ZipExtFile.read1 = guarded_zip_read1

script = os.path.abspath(sys.argv[1])
sys.argv = [script]
runpy.run_path(script, run_name="__main__")
RUNNER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pathlib
import resource
import subprocess
import tarfile
import tempfile
import uuid
import zipfile

EXPECTED_CONTENT = """[ERROR] 2023-01-01 10:00:10 Failed to load config
  Line 1: missing semicolon
  Line 2: invalid syntax
  File "config.xml", line 42
[ERROR] 2023-01-02 11:30:00 NullPointerException
  at module.main(Main.java:42)
  at system.run(System.java:10)
"""

OUTPUT = pathlib.Path("/home/user/extracted_errors.log")
ARCHIVE = pathlib.Path("/home/user/legacy_project_logs.tar.gz")


def test_extracted_errors_file_exists():
    path = "/home/user/extracted_errors.log"
    assert os.path.isfile(path), f"File {path} does not exist. Make sure you extracted the errors to the correct location."


def test_extracted_errors_content():
    path = "/home/user/extracted_errors.log"
    if not os.path.isfile(path):
        return  # Handled by previous test

    try:
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
    except UnicodeDecodeError:
        assert False, f"File {path} is not valid UTF-8. Ensure you converted the encoding from UTF-16LE to UTF-8."

    assert content == EXPECTED_CONTENT, "The extracted errors do not match the expected content exactly. Ensure multi-line records are handled correctly."


def discover_python_scripts():
    scripts = []
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d != "__pycache__"]
        for name in files:
            path = pathlib.Path(root, name)
            if name.endswith(".py") and path.is_file():
                scripts.append(path)
                continue
            try:
                with path.open("rb") as f:
                    first = f.readline(256)
                if first.startswith(b"#!") and b"python" in first.lower():
                    scripts.append(path)
            except OSError:
                pass
    return sorted(set(scripts))


def build_dynamic_archive(destination, token):
    first = (
        f"[ERROR] dynamic-{token} first failure\n"
        f"  detail {token}-a\n"
        f"    indented {token}-b\n"
    )
    second = (
        f"[ERROR] dynamic-{token} second failure\n"
        f"  traceback {token}-c\n"
    )
    expected = first + second

    with tempfile.TemporaryDirectory() as td:
        td = pathlib.Path(td)
        log_path = td / "application.log"
        zip_path = td / "logs.zip"

        with log_path.open("wb") as log:
            log.write(first.encode("utf-16le"))
            noise = (f"[INFO] {token} " + "x" * 4096 + "\n").encode("utf-16le")
            repetitions = (120 * 1024 * 1024) // len(noise) + 1
            for _ in range(repetitions):
                log.write(noise)
            log.write((f"[WARN] dynamic-{token} warning\n").encode("utf-16le"))
            log.write(second.encode("utf-16le"))
            log.write((f"[INFO] dynamic-{token} complete\n").encode("utf-16le"))

        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
            zf.write(log_path, "application.log")
        with tarfile.open(destination, "w:gz") as tf:
            tf.add(zip_path, arcname="logs.zip")

    return expected


def memory_limit():
    limit = 176 * 1024 * 1024
    resource.setrlimit(resource.RLIMIT_AS, (limit, limit))


def test_python_script_runs_streamingly_on_derived_archive():
    scripts = discover_python_scripts()
    assert scripts, "No Python script was created under /home/user."

    original_archive = ARCHIVE.read_bytes()
    original_output = OUTPUT.read_bytes()
    token = uuid.uuid4().hex

    with tempfile.TemporaryDirectory() as td:
        dynamic_archive = pathlib.Path(td) / "legacy_project_logs.tar.gz"
        expected = build_dynamic_archive(dynamic_archive, token)
        dynamic_bytes = dynamic_archive.read_bytes()
        successes = []

        try:
            for script in scripts:
                ARCHIVE.write_bytes(dynamic_bytes)
                try:
                    OUTPUT.unlink()
                except FileNotFoundError:
                    pass

                try:
                    result = subprocess.run(
                        ["python3", "/tmp/run_agent_script.py", str(script)],
                        cwd="/home/user",
                        stdin=subprocess.DEVNULL,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        timeout=60,
                        preexec_fn=memory_limit,
                    )
                except (subprocess.TimeoutExpired, OSError):
                    continue

                if result.returncode != 0 or not OUTPUT.is_file():
                    continue
                try:
                    produced = OUTPUT.read_text(encoding="utf-8")
                except (UnicodeDecodeError, OSError):
                    continue
                if produced == expected:
                    successes.append(str(script))
                    break

            assert successes, (
                "No submitted Python script correctly processed a derived nested archive "
                "using bounded-memory streaming or mmap I/O."
            )
        finally:
            ARCHIVE.write_bytes(original_archive)
            OUTPUT.write_bytes(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
