#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import io
import json
import os
import random
import re
import shutil
import stat
import string
import subprocess
import tarfile
import tempfile
import zipfile

import pytest

FILE_PATH = "/home/user/compiled_docs.md"
ARCHIVE_PATH = "/home/user/docs_archive.tar"

EXPECTED_ORIGINAL = (
    "# api.md\n"
    "This is the API documentation.\n"
    "# architecture.md\n"
    "Architecture diagrams and notes.\n"
    "# deployment.md\n"
    "Miscellaneous deployment notes.\n"
    "# setup.md\n"
    "Setup instructions.\n"
)


def test_compiled_docs_exists():
    """Verify that the compiled documentation file exists."""
    assert os.path.exists(FILE_PATH), f"File {FILE_PATH} does not exist. Did you create it?"
    assert os.path.isfile(FILE_PATH), f"Path {FILE_PATH} is not a regular file."


def test_compiled_docs_content():
    """Verify that the compiled documentation file has the correct content."""
    assert os.path.exists(FILE_PATH), f"File {FILE_PATH} does not exist."
    with open(FILE_PATH, "r", encoding="utf-8") as f:
        actual_content = f.read()
    assert actual_content == EXPECTED_ORIGINAL, (
        f"Content of {FILE_PATH} does not match the expected output.\n"
        f"Expected:\n{EXPECTED_ORIGINAL}\nActual:\n{actual_content}"
    )


def _tar_bytes(files, gz=False):
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w:gz" if gz else "w") as tf:
        for name, data in files:
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = 0o644
            tf.addfile(info, io.BytesIO(data))
    return output.getvalue()


def _zip_bytes(files, compression=zipfile.ZIP_DEFLATED):
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", compression=compression) as zf:
        for name, data in files:
            zf.writestr(name, data)
    return output.getvalue()


def _build_challenge():
    token = "".join(random.SystemRandom().choice(string.ascii_lowercase) for _ in range(12))
    records = []

    zip_files = [
        (f"zeta/{token}_same.md", f"zip-zeta-{token}".encode()),
        (f"alpha/{token}_same.md", f"zip-alpha-{token}".encode()),
        (f"docs/{token}_guide.md", f"zip-guide-{token}".encode()),
        ("docs/ignored.txt", b"not markdown"),
    ]
    valid_zip = _zip_bytes(zip_files)
    for path, data in zip_files:
        if path.endswith(".md"):
            records.append((os.path.basename(path), path, data.decode()))

    tar_files = [
        (f"manuals/{token}_architecture.md", f"tar-architecture-{token}".encode()),
        (f"deep/path/{token}_reference.md", f"tar-reference-{token}".encode()),
    ]
    valid_targz = _tar_bytes(tar_files, gz=True)
    for path, data in tar_files:
        records.append((os.path.basename(path), path, data.decode()))

    stream_name = f"{token}_deployment.md.gz"
    stream_text = f"gzip-stream-{token}"
    stream_data = gzip.compress(stream_text.encode())
    records.append((stream_name[:-3], stream_name[:-3], stream_text))

    # The first member is valid and the second has a CRC error. The whole nested
    # archive must be rejected, rather than retaining the first member.
    bad_first = f"corrupt-first-{token}".encode()
    bad_marker = f"corrupt-second-{token}".encode()
    corrupt_zip = _zip_bytes(
        [(f"bad/{token}_leak.md", bad_first), (f"bad/{token}_broken.md", bad_marker)],
        compression=zipfile.ZIP_STORED,
    )
    replacement = bytes([bad_marker[0] ^ 1]) + bad_marker[1:]
    assert bad_marker in corrupt_zip
    corrupt_zip = corrupt_zip.replace(bad_marker, replacement, 1)
    with zipfile.ZipFile(io.BytesIO(corrupt_zip)) as zf:
        assert zf.testzip() is not None

    master = _tar_bytes([
        (f"inputs/{token}_valid.zip", valid_zip),
        (f"inputs/{token}_valid.tar.gz", valid_targz),
        (f"inputs/{token}_corrupt.zip", corrupt_zip),
        (stream_name, stream_data),
    ])

    expected = "".join(
        f"# {base}\n{text}\n"
        for base, path, text in sorted(records, key=lambda item: (item[0], item[1]))
    )
    return master, expected


def _candidate_scripts():
    candidates = []
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d not in {"__pycache__", ".cache", ".git"}]
        for name in files:
            path = os.path.join(root, name)
            if path in {FILE_PATH, ARCHIVE_PATH} or os.path.islink(path):
                continue
            try:
                st = os.stat(path)
                if not stat.S_ISREG(st.st_mode) or st.st_size > 1024 * 1024:
                    continue
                with open(path, "rb") as f:
                    first = f.readline(256).lower()
            except OSError:
                continue
            if name.endswith(".py") or (first.startswith(b"#!") and b"python" in first):
                candidates.append(path)
    return sorted(candidates)


def _install_instrumentation(directory, event_log):
    code = r'''
import json
import os
import tarfile

_LOG = os.environ.get("DOCS_EVENT_LOG")


def _record(event):
    try:
        with open(_LOG, "a", encoding="utf-8") as f:
            f.write(json.dumps(event) + "\n")
    except Exception:
        pass


def _wrap_move(original, operation):
    def wrapped(src, dst, *args, **kwargs):
        src_path = os.path.abspath(os.fspath(src))
        dst_path = os.path.abspath(os.fspath(dst))
        existed = os.path.isfile(src_path)
        result = original(src, dst, *args, **kwargs)
        _record({"kind": "atomic_move", "operation": operation,
                 "src": src_path, "dst": dst_path, "src_existed": existed})
        return result
    return wrapped

os.rename = _wrap_move(os.rename, "rename")
os.replace = _wrap_move(os.replace, "replace")

_original_extract = tarfile.TarFile.extract
_original_extractall = tarfile.TarFile.extractall


def _is_master(tf):
    try:
        return os.path.realpath(os.fspath(tf.name)) == "/home/user/docs_archive.tar"
    except Exception:
        return False


def _extract(self, *args, **kwargs):
    if _is_master(self):
        _record({"kind": "master_extraction", "operation": "extract"})
    return _original_extract(self, *args, **kwargs)


def _extractall(self, *args, **kwargs):
    if _is_master(self):
        _record({"kind": "master_extraction", "operation": "extractall"})
    return _original_extractall(self, *args, **kwargs)

tarfile.TarFile.extract = _extract
tarfile.TarFile.extractall = _extractall
'''
    with open(os.path.join(directory, "sitecustomize.py"), "w", encoding="utf-8") as f:
        f.write(code)


def test_script_executes_workflow_on_derived_archive():
    candidates = _candidate_scripts()
    assert candidates, "No Python script was created under /home/user."

    original_archive = open(ARCHIVE_PATH, "rb").read()
    original_output = open(FILE_PATH, "rb").read()
    challenge, expected = _build_challenge()
    failures = []

    with tempfile.TemporaryDirectory(prefix="verifier_python_") as instrument_dir:
        event_log = os.path.join(instrument_dir, "events.jsonl")
        _install_instrumentation(instrument_dir, event_log)

        try:
            for script in candidates:
                with open(ARCHIVE_PATH, "wb") as f:
                    f.write(challenge)
                with open(FILE_PATH, "w", encoding="utf-8") as f:
                    f.write("verifier sentinel: output was not regenerated\n")
                open(event_log, "w").close()

                env = os.environ.copy()
                old_pythonpath = env.get("PYTHONPATH")
                env["PYTHONPATH"] = instrument_dir + (os.pathsep + old_pythonpath if old_pythonpath else "")
                env["DOCS_EVENT_LOG"] = event_log

                try:
                    result = subprocess.run(
                        ["python3", script], cwd="/home/user", env=env,
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                        text=True, timeout=20,
                    )
                except Exception as exc:
                    failures.append(f"{script}: execution failed: {exc}")
                    continue

                combined = result.stdout + "\n" + result.stderr
                try:
                    with open(FILE_PATH, "r", encoding="utf-8") as f:
                        actual = f.read()
                except Exception as exc:
                    failures.append(f"{script}: output unreadable: {exc}")
                    continue

                events = []
                try:
                    with open(event_log, encoding="utf-8") as f:
                        events = [json.loads(line) for line in f if line.strip()]
                except Exception as exc:
                    failures.append(f"{script}: instrumentation log unreadable: {exc}")
                    continue

                moved_atomically = any(
                    event.get("kind") == "atomic_move"
                    and event.get("dst") == FILE_PATH
                    and event.get("src") != FILE_PATH
                    and event.get("src_existed") is True
                    for event in events
                )
                extracted_master = any(event.get("kind") == "master_extraction" for event in events)

                problems = []
                if result.returncode != 0:
                    problems.append(f"exit status {result.returncode}")
                if actual != expected:
                    problems.append("incorrect output for verifier-derived archive")
                if not re.search(r"\bwarning\b", combined, flags=re.IGNORECASE):
                    problems.append("no printed warning for corrupt archive")
                if not moved_atomically:
                    problems.append("no atomic rename/replace of a completed temporary file")
                if extracted_master:
                    problems.append("master archive was extracted to disk")

                if not problems:
                    return
                failures.append(f"{script}: " + "; ".join(problems))
        finally:
            with open(ARCHIVE_PATH, "wb") as f:
                f.write(original_archive)
            with open(FILE_PATH, "wb") as f:
                f.write(original_output)

    pytest.fail("No created Python script performed the required workflow:\n" + "\n".join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
