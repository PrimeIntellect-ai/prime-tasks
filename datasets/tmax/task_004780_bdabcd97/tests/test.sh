#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/verifier_instrument
cat << 'PY_EOF' > /tmp/verifier_instrument/sitecustomize.py
import builtins
import fcntl
import io
import os

_TRACE = os.environ.get("VERIFIER_FLOCK_TRACE")
_RAW = os.path.realpath("/home/user/artifacts/raw_data.bin")
_orig_open = builtins.open
_orig_io_open = io.open
_orig_os_open = os.open
_orig_os_read = os.read
_orig_os_close = os.close
_orig_flock = fcntl.flock
_fd_paths = {}
_locked = set()

def _event(kind, fd):
    if not _TRACE:
        return
    try:
        out = _orig_os_open(_TRACE, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        try:
            os.write(out, (f"{kind} {fd}\n").encode("ascii"))
        finally:
            _orig_os_close(out)
    except Exception:
        pass

def _remember(fd, path):
    try:
        if os.path.realpath(os.fspath(path)) == _RAW:
            _fd_paths[int(fd)] = _RAW
    except (TypeError, ValueError, OSError):
        pass

def _read_event(fd):
    try:
        fd = int(fd)
    except (TypeError, ValueError):
        return
    if _fd_paths.get(fd) == _RAW:
        _event("READ_LOCKED" if fd in _locked else "READ_UNLOCKED", fd)

class _TrackedFile:
    def __init__(self, wrapped):
        self._wrapped = wrapped
        _remember(wrapped.fileno(), wrapped.name)

    def fileno(self):
        return self._wrapped.fileno()

    def read(self, *args, **kwargs):
        _read_event(self.fileno())
        return self._wrapped.read(*args, **kwargs)

    def read1(self, *args, **kwargs):
        _read_event(self.fileno())
        return self._wrapped.read1(*args, **kwargs)

    def readline(self, *args, **kwargs):
        _read_event(self.fileno())
        return self._wrapped.readline(*args, **kwargs)

    def readlines(self, *args, **kwargs):
        _read_event(self.fileno())
        return self._wrapped.readlines(*args, **kwargs)

    def readinto(self, *args, **kwargs):
        _read_event(self.fileno())
        return self._wrapped.readinto(*args, **kwargs)

    def readinto1(self, *args, **kwargs):
        _read_event(self.fileno())
        return self._wrapped.readinto1(*args, **kwargs)

    def __iter__(self):
        return self

    def __next__(self):
        _read_event(self.fileno())
        return next(self._wrapped)

    def close(self):
        try:
            fd = self.fileno()
            if _fd_paths.get(fd) == _RAW:
                _event("CLOSE", fd)
                _locked.discard(fd)
                _fd_paths.pop(fd, None)
        finally:
            return self._wrapped.close()

    def __enter__(self):
        self._wrapped.__enter__()
        return self

    def __exit__(self, exc_type, exc, tb):
        try:
            return self._wrapped.__exit__(exc_type, exc, tb)
        finally:
            try:
                fd = self.fileno()
            except Exception:
                fd = None
            if fd is not None and _fd_paths.get(fd) == _RAW:
                _event("CLOSE", fd)
                _locked.discard(fd)
                _fd_paths.pop(fd, None)

    def __getattr__(self, name):
        return getattr(self._wrapped, name)

def _wrap_open(original):
    def wrapped(file, *args, **kwargs):
        result = original(file, *args, **kwargs)
        try:
            if os.path.realpath(os.fspath(file)) == _RAW:
                return _TrackedFile(result)
        except (TypeError, ValueError, OSError):
            pass
        return result
    return wrapped

def tracked_os_open(path, flags, *args, **kwargs):
    fd = _orig_os_open(path, flags, *args, **kwargs)
    _remember(fd, path)
    return fd

def tracked_os_read(fd, n):
    _read_event(fd)
    return _orig_os_read(fd, n)

def tracked_os_close(fd):
    try:
        if _fd_paths.get(int(fd)) == _RAW:
            _event("CLOSE", int(fd))
            _locked.discard(int(fd))
            _fd_paths.pop(int(fd), None)
    finally:
        return _orig_os_close(fd)

def tracked_flock(fd_or_object, operation):
    fd = fd_or_object if isinstance(fd_or_object, int) else fd_or_object.fileno()
    result = _orig_flock(fd_or_object, operation)
    if _fd_paths.get(int(fd)) == _RAW:
        if operation & fcntl.LOCK_EX:
            _locked.add(int(fd))
            _event("LOCK_EX", int(fd))
        elif operation & fcntl.LOCK_UN:
            _event("LOCK_UN", int(fd))
            _locked.discard(int(fd))
    return result

builtins.open = _wrap_open(_orig_open)
io.open = _wrap_open(_orig_io_open)
os.open = tracked_os_open
os.read = tracked_os_read
os.close = tracked_os_close
fcntl.flock = tracked_flock
PY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import pytest

ARTIFACTS_DIR = "/home/user/artifacts"
RAW_DATA_FILE = os.path.join(ARTIFACTS_DIR, "raw_data.bin")
METADATA_FILE = os.path.join(ARTIFACTS_DIR, "metadata.txt")
COMPRESSED_FILE = os.path.join(ARTIFACTS_DIR, "compressed.bin")
MANIFEST_FILE = os.path.join(ARTIFACTS_DIR, "final_manifest.json")

def rle_encode(data: bytes) -> bytes:
    """Helper to compute the expected RLE sequence."""
    if not data:
        return b""

    encoded = bytearray()
    current_byte = data[0]
    count = 1

    for byte in data[1:]:
        if byte == current_byte and count < 255:
            count += 1
        else:
            encoded.append(count)
            encoded.append(current_byte)
            current_byte = byte
            count = 1

    encoded.append(count)
    encoded.append(current_byte)
    return bytes(encoded)

def _candidate_scripts():
    skipped = {".cache", ".local", "__pycache__", "site-packages", "dist-packages"}
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d not in skipped]
        for name in files:
            if name.endswith(".py"):
                yield os.path.join(root, name)

def _valid_lock_trace(lines):
    events = []
    for line in lines:
        parts = line.strip().split()
        if len(parts) == 2:
            try:
                events.append((parts[0], int(parts[1])))
            except ValueError:
                pass

    if any(kind == "READ_UNLOCKED" for kind, _ in events):
        return False

    for index, (kind, fd) in enumerate(events):
        if kind != "LOCK_EX":
            continue
        read_index = next((i for i in range(index + 1, len(events))
                           if events[i] == ("READ_LOCKED", fd)), None)
        if read_index is None:
            continue
        if any(events[i] in (("LOCK_UN", fd), ("CLOSE", fd))
               for i in range(read_index + 1, len(events))):
            return True
    return False

def test_python_script_executes_with_exclusive_lock_before_reading():
    scripts = list(_candidate_scripts())
    assert scripts, "No Python script was created under /home/user."

    failures = []
    for script in scripts:
        for output in (COMPRESSED_FILE, MANIFEST_FILE):
            try:
                os.remove(output)
            except FileNotFoundError:
                pass

        trace_fd, trace_path = tempfile.mkstemp(prefix="flock-trace-")
        os.close(trace_fd)
        env = os.environ.copy()
        env["VERIFIER_FLOCK_TRACE"] = trace_path
        env["PYTHONPATH"] = "/tmp/verifier_instrument" + (
            os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else ""
        )
        try:
            result = subprocess.run(
                [sys.executable, script], cwd=os.path.dirname(script) or "/home/user",
                env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, timeout=15
            )
            with open(trace_path, "r", encoding="ascii", errors="replace") as f:
                trace = f.readlines()
        except subprocess.TimeoutExpired:
            failures.append(f"{script}: timed out")
            continue
        finally:
            try:
                os.remove(trace_path)
            except FileNotFoundError:
                pass

        if (result.returncode == 0 and os.path.isfile(COMPRESSED_FILE)
                and os.path.isfile(MANIFEST_FILE) and _valid_lock_trace(trace)):
            return
        failures.append(f"{script}: exit={result.returncode}, trace={trace!r}, stderr={result.stderr[-300:]!r}")

    pytest.fail("No submitted Python script produced both outputs while reading raw_data.bin under an exclusive flock and then releasing/closing it. " + " | ".join(failures))

def test_compressed_bin_exists_and_correct():
    """Test that compressed.bin exists and contains the correctly encoded RLE data."""
    assert os.path.isfile(COMPRESSED_FILE), f"File {COMPRESSED_FILE} does not exist."
    assert os.path.isfile(RAW_DATA_FILE), f"Source file {RAW_DATA_FILE} is missing."

    with open(RAW_DATA_FILE, 'rb') as f:
        raw_data = f.read()

    expected_compressed_data = rle_encode(raw_data)

    with open(COMPRESSED_FILE, 'rb') as f:
        actual_compressed_data = f.read()

    assert actual_compressed_data == expected_compressed_data, \
        f"Content of {COMPRESSED_FILE} does not match the expected RLE encoded data."

def test_final_manifest_exists_and_correct():
    """Test that final_manifest.json exists, is valid JSON, and contains the correct metadata and checksum."""
    assert os.path.isfile(MANIFEST_FILE), f"File {MANIFEST_FILE} does not exist."
    assert os.path.isfile(METADATA_FILE), f"Source file {METADATA_FILE} is missing."
    assert os.path.isfile(COMPRESSED_FILE), f"Source file {COMPRESSED_FILE} is missing."

    with open(METADATA_FILE, 'rb') as f:
        raw_metadata = f.read()
    expected_metadata_text = raw_metadata.decode('utf-16le')

    with open(COMPRESSED_FILE, 'rb') as f:
        compressed_data = f.read()
    expected_checksum = hashlib.sha256(compressed_data).hexdigest()

    with open(MANIFEST_FILE, 'r', encoding='utf-8') as f:
        try:
            manifest_data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse {MANIFEST_FILE} as JSON: {e}")

    assert "metadata" in manifest_data, "Manifest is missing the 'metadata' key."
    assert "checksum" in manifest_data, "Manifest is missing the 'checksum' key."
    assert manifest_data["metadata"] == expected_metadata_text, \
        f"Manifest metadata does not match the decoded content of {METADATA_FILE}."
    assert manifest_data["checksum"] == expected_checksum, \
        f"Manifest checksum does not match the SHA-256 hash of {COMPRESSED_FILE}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
