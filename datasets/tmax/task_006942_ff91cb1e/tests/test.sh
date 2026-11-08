#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import ctypes
import json
import os
import secrets
import shutil
import struct
import subprocess
from pathlib import Path

import pytest

DOCS_OUTPUT_DIR = "/home/user/docs_output"
INPUT_CSV = "/home/user/input_docs.csv"

IN_MODIFY = 0x00000002
IN_CLOSE_WRITE = 0x00000008
IN_MOVED_FROM = 0x00000040
IN_MOVED_TO = 0x00000080
IN_CREATE = 0x00000100
IN_DELETE = 0x00000200
WATCH_MASK = IN_MODIFY | IN_CLOSE_WRITE | IN_MOVED_FROM | IN_MOVED_TO | IN_CREATE | IN_DELETE

ORIGINAL_CSV = b"""file_path,chunk_index,content_base64
../../../../../home/user/malicious.txt,1,d29ybGQh
../../../../../home/user/malicious.txt,0,SGVsbG8g
guides/setup.md,0,IyBTZXR1cAoK
guides/setup.md,1,UnVuIHRoZSBzY3JpcHQu
../api_ref.csv,2,MixCb2IK
../api_ref.csv,0,SUQsTkFNRQo=
../api_ref.csv,1,MSxBbGljZQo=
"""


def find_scripts():
    candidates = []
    excluded = {Path(INPUT_CSV).resolve(), Path(__file__).resolve()}
    roots = [Path("/home/user"), Path("/tmp"), Path("/root")]

    for root in roots:
        if not root.exists():
            continue
        for path in root.rglob("*"):
            try:
                resolved = path.resolve()
                if not path.is_file() or resolved in excluded:
                    continue
                if DOCS_OUTPUT_DIR in str(resolved) or path.stat().st_size > 2_000_000:
                    continue
                data = path.read_bytes()
            except (OSError, UnicodeError):
                continue

            first = data.splitlines()[0] if data else b""
            script_like = path.suffix in {".sh", ".bash", ".py"} or first.startswith(b"#!")
            if not script_like:
                continue

            # A script implementing this fixed-path task must identify both the
            # supplied CSV and the requested output directory.
            if b"input_docs.csv" not in data or b"docs_output" not in data:
                continue
            candidates.append(path)

    # Prefer the agent's most recently written artifact.
    candidates.sort(key=lambda p: p.stat().st_mtime_ns, reverse=True)
    return candidates


def command_for(path):
    data = path.read_bytes()[:256]
    first = data.splitlines()[0].decode("utf-8", "ignore") if data else ""
    if path.suffix == ".py" or "python" in first:
        return ["python3", str(path)]
    if path.suffix in {".sh", ".bash"} or any(x in first for x in ("/sh", "/bash")):
        return ["bash", str(path)]
    if os.access(path, os.X_OK):
        return [str(path)]
    return ["bash", str(path)]


def create_watch(directory):
    libc = ctypes.CDLL(None, use_errno=True)
    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    if fd < 0:
        raise OSError(ctypes.get_errno(), "inotify_init1 failed")
    wd = libc.inotify_add_watch(fd, os.fsencode(directory), WATCH_MASK)
    if wd < 0:
        err = ctypes.get_errno()
        os.close(fd)
        raise OSError(err, "inotify_add_watch failed")
    return fd


def read_events(fd):
    events = []
    while True:
        try:
            block = os.read(fd, 65536)
        except BlockingIOError:
            break
        if not block:
            break
        offset = 0
        while offset < len(block):
            wd, mask, cookie, name_len = struct.unpack_from("iIII", block, offset)
            offset += 16
            raw_name = block[offset:offset + name_len]
            offset += name_len
            name = raw_name.split(b"\0", 1)[0].decode("utf-8", "surrogateescape")
            events.append((mask, cookie, name))
    return events


def assert_atomic_moves(events, filenames):
    for filename in filenames:
        moved = [e for e in events if e[2] == filename and e[0] & IN_MOVED_TO]
        assert moved, f"{filename} was not atomically moved into place"

        valid_move = False
        for _, cookie, _ in moved:
            if cookie and any(
                other_cookie == cookie and other_name != filename and mask & IN_MOVED_FROM
                for mask, other_cookie, other_name in events
            ):
                valid_move = True
                break
        assert valid_move, f"{filename} was not renamed from a temporary file in docs_output"

        direct_writes = [
            e for e in events
            if e[2] == filename and e[0] & (IN_CREATE | IN_MODIFY | IN_CLOSE_WRITE)
        ]
        assert not direct_writes, f"{filename} was also written directly instead of only by atomic rename"


def run_case(script, csv_bytes, expected, escaped_paths):
    shutil.rmtree(DOCS_OUTPUT_DIR, ignore_errors=True)
    os.makedirs(DOCS_OUTPUT_DIR, exist_ok=True)
    Path(INPUT_CSV).write_bytes(csv_bytes)
    for escaped in escaped_paths:
        try:
            Path(escaped).unlink()
        except FileNotFoundError:
            pass

    fd = create_watch(DOCS_OUTPUT_DIR)
    try:
        result = subprocess.run(
            command_for(script),
            cwd=str(script.parent),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
            check=False,
        )
        events = read_events(fd)
    finally:
        os.close(fd)

    assert result.returncode == 0, (
        f"script exited with {result.returncode}: "
        f"{result.stderr.decode('utf-8', 'replace')}"
    )

    assert os.path.isdir(DOCS_OUTPUT_DIR)
    for filename, content in expected.items():
        path = Path(DOCS_OUTPUT_DIR) / filename
        assert path.is_file(), f"missing generated file {filename}"
        assert path.read_bytes() == content, f"incorrect generated content for {filename}"

    manifest_path = Path(DOCS_OUTPUT_DIR) / "manifest.json"
    assert manifest_path.is_file(), "manifest.json is missing"
    with manifest_path.open("r", encoding="utf-8") as stream:
        manifest = json.load(stream)
    assert manifest == {name: len(content) for name, content in expected.items()}

    assert_atomic_moves(events, expected.keys())
    assert not any(p.name.endswith(".tmp") for p in Path(DOCS_OUTPUT_DIR).iterdir())
    for escaped in escaped_paths:
        assert not Path(escaped).exists(), f"unsafe path was written: {escaped}"


def randomized_case():
    token = secrets.token_hex(8)
    names = [f"alpha_{token}.txt", f"beta_{token}.md", f"gamma_{token}.json"]
    expected = {
        names[0]: (f"random value {secrets.token_hex(24)}\n" * 7).encode(),
        names[1]: (f"# {secrets.token_hex(10)}\n\nGenerated documentation.\n" * 5).encode(),
        names[2]: json.dumps({"token": secrets.token_hex(32), "ok": True}).encode(),
    }
    paths = [
        f"/home/user/{names[0]}",
        f"manual/sections/{names[1]}",
        f"../../unsafe/tree/{names[2]}",
    ]
    escaped = [f"/home/user/{names[0]}"]

    rows = []
    for source_path, name in zip(paths, names):
        encoded = base64.b64encode(expected[name]).decode("ascii")
        cuts = [0, 5, len(encoded) // 2 + 1, len(encoded)]
        chunks = [encoded[cuts[i]:cuts[i + 1]] for i in range(3)]
        for index, chunk in enumerate(chunks):
            rows.append((source_path, index, chunk))
    secrets.SystemRandom().shuffle(rows)
    csv_text = "file_path,chunk_index,content_base64\n" + "".join(
        f"{path},{index},{chunk}\n" for path, index, chunk in rows
    )
    return csv_text.encode(), expected, escaped


def test_script_exists_executes_and_uses_atomic_writes():
    candidates = find_scripts()
    assert candidates, "No CSV-processing script was found"

    random_csv, random_expected, escaped = randomized_case()
    failures = []
    selected = None
    for script in candidates:
        try:
            run_case(script, random_csv, random_expected, escaped)
            selected = script
            break
        except Exception as exc:
            failures.append(f"{script}: {exc}")

    assert selected is not None, "No submitted script passed execution tests:\n" + "\n".join(failures)

    original_expected = {
        "malicious.txt": b"Hello world!",
        "setup.md": b"# Setup\n\nRun the script.",
        "api_ref.csv": b"ID,NAME\n1,Alice\n2,Bob\n",
    }
    run_case(selected, ORIGINAL_CSV, original_expected, [])


def test_output_directory_exists():
    """Verify that the docs_output directory was created."""
    assert os.path.isdir(DOCS_OUTPUT_DIR), f"Directory {DOCS_OUTPUT_DIR} does not exist."


def test_decoded_files_content():
    """Verify that the decoded files exist with the correct content."""
    expected_files = {
        "malicious.txt": b"Hello world!",
        "setup.md": b"# Setup\n\nRun the script.",
        "api_ref.csv": b"ID,NAME\n1,Alice\n2,Bob\n"
    }

    for filename, expected_content in expected_files.items():
        filepath = os.path.join(DOCS_OUTPUT_DIR, filename)
        assert os.path.isfile(filepath), f"Expected file {filepath} is missing."
        with open(filepath, "rb") as f:
            content = f.read()
        assert content == expected_content, f"Content of {filepath} is incorrect."


def test_manifest_json():
    """Verify that manifest.json exists and contains correct file lengths."""
    manifest_path = os.path.join(DOCS_OUTPUT_DIR, "manifest.json")
    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} is missing."

    with open(manifest_path, "r") as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{manifest_path} is not a valid JSON file.")

    expected_manifest = {
        "malicious.txt": 12,
        "setup.md": 24,
        "api_ref.csv": 22
    }
    assert manifest == expected_manifest, f"Manifest content {manifest} does not match expected {expected_manifest}."


def test_no_tmp_files():
    """Verify that no temporary files were left behind in the output directory."""
    if not os.path.isdir(DOCS_OUTPUT_DIR):
        pytest.skip("Output directory missing.")
    for filename in os.listdir(DOCS_OUTPUT_DIR):
        assert not filename.endswith(".tmp"), f"Temporary file left behind: {filename}"


def test_no_directory_traversal():
    """Verify that the script did not write files outside the intended directory."""
    traversal_path = "/home/user/malicious.txt"
    assert not os.path.isfile(traversal_path), f"Directory traversal vulnerability exploited! File found at {traversal_path}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
