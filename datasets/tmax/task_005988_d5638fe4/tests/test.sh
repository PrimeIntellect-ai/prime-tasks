#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import subprocess
import sys


def get_expected_size(base_dir):
    total_size = 0

    for root, _, files in os.walk(base_dir):
        for file in files:
            filepath = os.path.join(root, file)
            if file.endswith(".log"):
                with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
                    content = f.read()
                # Check for [CRITICAL] on one line and [END CRITICAL] on a subsequent line
                if re.search(r"\[CRITICAL\].*?\[END CRITICAL\]", content, re.DOTALL):
                    total_size += os.path.getsize(filepath)
            elif file.endswith(".dat"):
                size = os.path.getsize(filepath)
                if size >= 1028:
                    with open(filepath, "rb") as f:
                        f.seek(1024)
                        signature = f.read(4)
                        if signature == b'\xde\xad\xbe\xef':
                            total_size += size
    return total_size


def test_script_exists_and_uses_required_modules():
    script_path = "/home/user/find_waste.py"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

    with open(script_path, "r", encoding="utf-8") as f:
        content = f.read()

    assert "mmap" in content, "The script does not seem to use 'mmap' as required."

    # Check for atomic rename (os.rename, os.replace, shutil.move, Path.rename)
    atomic_keywords = ["rename", "replace", "move"]
    has_atomic = any(kw in content for kw in atomic_keywords)
    assert has_atomic, "The script does not seem to perform an atomic write operation (e.g., using os.rename)."


def test_output_file_content():
    output_path = "/home/user/reclaimable_space.txt"
    assert os.path.isfile(output_path), f"Output file {output_path} was not created."

    base_dir = "/home/user/storage_dumps"
    expected_size = get_expected_size(base_dir)
    expected_content = f"Total bytes: {expected_size}"

    with open(output_path, "r", encoding="utf-8") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"Content of {output_path} is incorrect. "
        f"Expected '{expected_content}', but got '{actual_content}'."
    )


def _write(path, data, binary=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb" if binary else "w") as f:
        f.write(data)


def test_z_script_executes_on_changed_inputs_with_mmap_and_atomic_write(tmp_path):
    base_dir = "/home/user/storage_dumps"
    output_path = "/home/user/reclaimable_space.txt"

    # Replace the fixed fixture with values not available when the submission was written.
    for root, dirs, files in os.walk(base_dir, topdown=False):
        for name in files:
            os.unlink(os.path.join(root, name))
        for name in dirs:
            os.rmdir(os.path.join(root, name))

    _write(
        f"{base_dir}/new/deep/critical.log",
        "prefix\n[CRITICAL]\nnew unpredictable error text\n[END CRITICAL]\nsuffix\n",
    )
    _write(f"{base_dir}/new/plain.log", "[CRITICAL]\nmissing terminator\n")
    _write(
        f"{base_dir}/other/second.log",
        "header\n[CRITICAL]\nline one\nline two\n[END CRITICAL]\n",
    )

    marked = bytearray(1733)
    marked[1024:1028] = b"\xde\xad\xbe\xef"
    _write(f"{base_dir}/new/deep/marked.dat", marked, binary=True)

    clean = bytearray(1291)
    clean[1019:1023] = b"\xde\xad\xbe\xef"
    _write(f"{base_dir}/other/clean.dat", clean, binary=True)

    short = bytearray(777)
    short[100:104] = b"\xde\xad\xbe\xef"
    _write(f"{base_dir}/short.dat", short, binary=True)

    expected_content = f"Total bytes: {get_expected_size(base_dir)}"
    if os.path.exists(output_path):
        os.unlink(output_path)

    hook_dir = tmp_path / "hook"
    hook_dir.mkdir()
    event_path = tmp_path / "events.jsonl"
    sitecustomize = hook_dir / "sitecustomize.py"
    sitecustomize.write_text(r'''
import json
import mmap as _mmap_module
import os

_event_path = os.environ["WASTE_EVENT_FILE"]
_output_path = os.path.realpath("/home/user/reclaimable_space.txt")
_base_path = os.path.realpath("/home/user/storage_dumps")
_real_mmap = _mmap_module.mmap
_real_rename = os.rename
_real_replace = os.replace


def _record(value):
    with open(_event_path, "a", encoding="utf-8") as stream:
        stream.write(json.dumps(value) + "\\n")


def _fd_path(fd):
    try:
        return os.path.realpath(os.readlink(f"/proc/self/fd/{fd}"))
    except Exception:
        return None


def _tracked_mmap(fileno, *args, **kwargs):
    path = _fd_path(fileno)
    if path and (path == _base_path or path.startswith(_base_path + os.sep)):
        _record({"kind": "mmap", "path": path})
    return _real_mmap(fileno, *args, **kwargs)


def _resolved(path, dir_fd=None):
    value = os.fsdecode(os.fspath(path))
    if os.path.isabs(value):
        return os.path.realpath(value)
    if dir_fd is not None:
        parent = _fd_path(dir_fd)
        if parent:
            return os.path.realpath(os.path.join(parent, value))
    return os.path.realpath(value)


def _wrap_atomic(real_function, operation):
    def wrapped(src, dst, *args, **kwargs):
        src_path = _resolved(src, kwargs.get("src_dir_fd"))
        dst_path = _resolved(dst, kwargs.get("dst_dir_fd"))
        source_existed = os.path.isfile(src_path)
        result = real_function(src, dst, *args, **kwargs)
        if dst_path == _output_path:
            try:
                with open(dst_path, "r", encoding="utf-8") as stream:
                    content = stream.read().strip()
            except Exception:
                content = None
            _record({
                "kind": "atomic",
                "operation": operation,
                "src": src_path,
                "dst": dst_path,
                "source_existed": source_existed,
                "content": content,
            })
        return result
    return wrapped


_mmap_module.mmap = _tracked_mmap
os.rename = _wrap_atomic(_real_rename, "rename")
os.replace = _wrap_atomic(_real_replace, "replace")
''', encoding="utf-8")

    env = os.environ.copy()
    env["PYTHONPATH"] = str(hook_dir) + os.pathsep + env.get("PYTHONPATH", "")
    env["WASTE_EVENT_FILE"] = str(event_path)
    result = subprocess.run(
        [sys.executable, "/home/user/find_waste.py"],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"find_waste.py failed with exit code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(output_path), "Running find_waste.py did not create the output file."
    with open(output_path, "r", encoding="utf-8") as f:
        actual_content = f.read().strip()
    assert actual_content == expected_content, (
        f"Script produced {actual_content!r} on changed inputs; expected {expected_content!r}."
    )

    events = []
    if event_path.exists():
        for line in event_path.read_text(encoding="utf-8").splitlines():
            events.append(json.loads(line))

    mapped_paths = {
        os.path.realpath(event["path"])
        for event in events
        if event.get("kind") == "mmap"
    }
    required_mapped_paths = {
        os.path.realpath(f"{base_dir}/new/deep/marked.dat"),
        os.path.realpath(f"{base_dir}/other/clean.dat"),
    }
    assert required_mapped_paths <= mapped_paths, (
        "The script did not memory-map every .dat file large enough to inspect."
    )

    atomic_events = [
        event for event in events
        if event.get("kind") == "atomic"
        and event.get("dst") == os.path.realpath(output_path)
        and event.get("src") != event.get("dst")
        and event.get("source_existed")
        and event.get("content") == expected_content
    ]
    assert atomic_events, (
        "The correct output was not installed from an existing temporary file using "
        "an atomic rename/replace operation."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
