#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import fcntl
import hashlib
import os
import subprocess
import sys
import tempfile
import time

PACKAGE_ROOT = "/app/py-archiver-1.0.0"
CORE_PY = os.path.join(PACKAGE_ROOT, "pyarchiver", "core.py")


def output_files(root):
    files = []
    for current, _, names in os.walk(root):
        for name in names:
            path = os.path.join(current, name)
            if os.path.isfile(path):
                files.append(path)
    return files


def chunk_fingerprints(payloads, chunk_size):
    result = collections.Counter()
    for payload in payloads:
        for offset in range(0, len(payload), chunk_size):
            chunk = payload[offset:offset + chunk_size]
            result[(len(chunk), hashlib.sha256(chunk).hexdigest())] += 1
    return result


def archive_command(source, destination):
    return [
        sys.executable, "-m", "pyarchiver.cli",
        "--source", source,
        "--dest", destination,
        "--chunk-size", "5MB",
    ]


def archive_environment():
    env = os.environ.copy()
    env["PYTHONPATH"] = PACKAGE_ROOT
    return env


def test_archiver_fixes():
    # Preserve the original source assertions.
    assert os.path.isfile(CORE_PY), f"Core module {CORE_PY} is missing."
    with open(CORE_PY, "r") as source:
        content = source.read()
    assert "fcntl" in content, "The 'fcntl' module is not imported or used in core.py."
    assert "flock" in content, "The 'fcntl.flock' method is not used in core.py for file locking."

    # Verify that a source file protected by an exclusive lock cannot be read
    # until that lock is released. A real shared lock on the source conflicts
    # with this lock; merely mentioning flock in the source does not.
    with tempfile.TemporaryDirectory() as src_dir, tempfile.TemporaryDirectory() as dest_dir:
        locked_path = os.path.join(src_dir, "locked.dat")
        locked_payload = os.urandom(2 * 1024 * 1024)
        with open(locked_path, "wb") as source:
            source.write(locked_payload)

        with open(locked_path, "rb") as lock_handle:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX)
            process = subprocess.Popen(
                archive_command(src_dir, dest_dir),
                env=archive_environment(),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            time.sleep(0.75)
            assert process.poll() is None, (
                "The archiver completed while the source was exclusively locked; "
                "it did not take a conflicting shared source-file lock during processing."
            )
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)

        stdout, stderr = process.communicate(timeout=10)
        assert process.returncode == 0, f"Archiver execution failed:\n{stderr}"
        locked_outputs = output_files(dest_dir)
        assert locked_outputs, "No archive output was produced for the locked source file."
        assert any(open(path, "rb").read() == locked_payload for path in locked_outputs), (
            "The archive did not preserve the contents of the locked source file."
        )

    # Preserve the original 50 MB throughput test while checking every output
    # byte. All inputs are nested, and varied sizes force actual splitting.
    with tempfile.TemporaryDirectory() as src_dir, tempfile.TemporaryDirectory() as dest_dir:
        mib = 1024 * 1024
        sizes_mib = [11, 7] + [4] * 8  # Exactly 50 MiB across ten files.
        payloads = []

        for index, size_mib in enumerate(sizes_mib):
            subdir = os.path.join(src_dir, f"level_{index % 5}", f"nested_{index}")
            os.makedirs(subdir, exist_ok=True)
            payload = os.urandom(size_mib * mib)
            payloads.append(payload)
            with open(os.path.join(subdir, f"unique_file_{index}.dat"), "wb") as source:
                source.write(payload)

        start = time.time()
        result = subprocess.run(
            archive_command(src_dir, dest_dir),
            env=archive_environment(),
            capture_output=True,
            text=True,
            timeout=15,
        )
        duration = time.time() - start

        assert result.returncode == 0, f"Archiver execution failed with error:\n{result.stderr}"

        dest_files = output_files(dest_dir)
        assert len(dest_files) > 0, (
            "No files were created in the destination directory. Recursive traversal may be failing."
        )

        actual = collections.Counter()
        for path in dest_files:
            with open(path, "rb") as archived:
                data = archived.read()
            assert data, f"Archive artifact {path} is empty."
            assert len(data) <= 5 * mib, f"Archive artifact {path} exceeds the requested chunk size."
            actual[(len(data), hashlib.sha256(data).hexdigest())] += 1

        # Accept the two conventional interpretations of MB. In either case,
        # every produced chunk must exactly match the corresponding source data.
        expected_binary = chunk_fingerprints(payloads, 5 * 1024 * 1024)
        expected_decimal = chunk_fingerprints(payloads, 5 * 1000 * 1000)
        assert actual in (expected_binary, expected_decimal), (
            "Archive chunks do not exactly reconstruct all recursively discovered source files."
        )

        assert duration > 0, "Execution time was zero, cannot calculate throughput."
        throughput = 50.0 / duration
        assert throughput >= 20.0, (
            f"Throughput is too low: {throughput:.2f} MB/s. "
            "Expected at least 20.0 MB/s. Buffer size may not be optimized."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
