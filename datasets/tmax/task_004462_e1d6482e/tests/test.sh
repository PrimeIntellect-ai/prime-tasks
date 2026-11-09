#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import glob
import json
import os
import re
import struct
import subprocess

import pytest

DATASET = "/home/user/printing_dataset"
SUMMARY = "/home/user/printing_summary.json"
TMP_SUMMARY = SUMMARY + ".tmp"

EXPECTED_CONTENTS = {
    "/home/user/printing_dataset/batch_A/cube_12.4mm.gcode": "G28\nG1 X10 Y10\n; filament_used_mm: 12.4\nG1 E12.4\n",
    "/home/user/printing_dataset/batch_A/sphere_55.0mm.gcode": "G28\n; filament_used_mm: 55.0\nG1 Z5\n",
    "/home/user/printing_dataset/batch_B/cylinder_98.12mm.gcode": "; filament_used_mm: 98.12\nM104 S200\n",
}
PYRAMID_CONTENT = "G28\nG1 X10 Y10\n; some other comment\nG1 E10\n"


def expected_summary():
    return {
        "/home/user/printing_dataset/batch_A/cube_12.4mm.gcode": 12.4,
        "/home/user/printing_dataset/batch_A/sphere_55.0mm.gcode": 55.0,
        "/home/user/printing_dataset/batch_B/cylinder_98.12mm.gcode": 98.12,
    }


def test_symlink_loops_intact():
    symlinks = {
        "/home/user/printing_dataset/batch_A/loop_dir": "/home/user/printing_dataset/batch_A",
        "/home/user/printing_dataset/batch_B/nested/root_loop": "/home/user/printing_dataset"
    }
    for link, target in symlinks.items():
        assert os.path.islink(link), f"Symlink missing or altered: {link}"
        assert os.readlink(link) == target, f"Symlink {link} points to wrong target"


def test_files_renamed_correctly():
    expected_renamed = [
        "/home/user/printing_dataset/batch_A/cube_12.4mm.gcode",
        "/home/user/printing_dataset/batch_A/sphere_55.0mm.gcode",
        "/home/user/printing_dataset/batch_B/cylinder_98.12mm.gcode",
    ]
    for f in expected_renamed:
        assert os.path.isfile(f), f"Expected renamed file missing: {f}"

    unexpected_originals = [
        "/home/user/printing_dataset/batch_A/cube.gcode",
        "/home/user/printing_dataset/batch_A/sphere.gcode",
        "/home/user/printing_dataset/batch_B/cylinder.gcode",
    ]
    for f in unexpected_originals:
        assert not os.path.exists(f), f"Original file should have been renamed but still exists: {f}"


def test_renamed_files_preserve_original_contents():
    for path, expected in EXPECTED_CONTENTS.items():
        with open(path, "r", encoding="utf-8") as f:
            assert f.read() == expected, f"Renamed GCode content was not preserved: {path}"


def test_pyramid_unchanged():
    pyramid_path = "/home/user/printing_dataset/batch_B/nested/pyramid.gcode"
    assert os.path.isfile(pyramid_path), f"File without metadata should be unchanged: {pyramid_path}"
    with open(pyramid_path, "r", encoding="utf-8") as f:
        assert f.read() == PYRAMID_CONTENT, "File without metadata was modified"


def test_json_summary():
    json_path = "/home/user/printing_summary.json"
    assert os.path.isfile(json_path), f"JSON summary missing: {json_path}"

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} is not valid JSON")

    expected_data = expected_summary()
    assert data == expected_data, f"JSON summary content is incorrect. Expected {expected_data}, got {data}"


def test_summary_is_derived_from_gcode_metadata():
    derived = {}
    metadata_re = re.compile(r"^; filament_used_mm: ([+-]?(?:\d+(?:\.\d*)?|\.\d+))$")
    for root, dirs, files in os.walk(DATASET, followlinks=False):
        dirs[:] = [d for d in dirs if not os.path.islink(os.path.join(root, d))]
        for name in files:
            if not name.endswith(".gcode"):
                continue
            path = os.path.abspath(os.path.join(root, name))
            value = None
            with open(path, "r", encoding="utf-8") as f:
                for line in f:
                    match = metadata_re.match(line.rstrip("\r\n"))
                    if match:
                        value = float(match.group(1))
                        break
            if value is not None:
                derived[path] = value

    with open(SUMMARY, "r", encoding="utf-8") as f:
        report = json.load(f)
    assert report == derived, f"Summary does not match metadata parsed from the resulting GCode files: {derived}"


def test_tmp_file_not_present():
    tmp_path = "/home/user/printing_summary.json.tmp"
    assert not os.path.exists(tmp_path), f"Temporary file {tmp_path} should not be present"


def _reset_initial_fixture():
    os.makedirs(f"{DATASET}/batch_A", exist_ok=True)
    os.makedirs(f"{DATASET}/batch_B/nested", exist_ok=True)
    os.makedirs(f"{DATASET}/binaries", exist_ok=True)

    for pattern in (
        f"{DATASET}/batch_A/cube*.gcode",
        f"{DATASET}/batch_A/sphere*.gcode",
        f"{DATASET}/batch_B/cylinder*.gcode",
    ):
        for path in glob.glob(pattern):
            if os.path.isfile(path) or os.path.islink(path):
                os.unlink(path)

    originals = {
        f"{DATASET}/batch_A/cube.gcode": EXPECTED_CONTENTS[f"{DATASET}/batch_A/cube_12.4mm.gcode"],
        f"{DATASET}/batch_A/sphere.gcode": EXPECTED_CONTENTS[f"{DATASET}/batch_A/sphere_55.0mm.gcode"],
        f"{DATASET}/batch_B/cylinder.gcode": EXPECTED_CONTENTS[f"{DATASET}/batch_B/cylinder_98.12mm.gcode"],
        f"{DATASET}/batch_B/nested/pyramid.gcode": PYRAMID_CONTENT,
    }
    for path, content in originals.items():
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)

    links = {
        f"{DATASET}/batch_A/loop_dir": f"{DATASET}/batch_A",
        f"{DATASET}/batch_B/nested/root_loop": DATASET,
    }
    for link, target in links.items():
        if os.path.lexists(link):
            if os.path.isdir(link) and not os.path.islink(link):
                pytest.fail(f"Expected symlink path replaced by directory: {link}")
            os.unlink(link)
        os.symlink(target, link)

    for path in (SUMMARY, TMP_SUMMARY):
        if os.path.lexists(path):
            os.unlink(path)


def _find_solution_scripts():
    candidates = []
    this_file = os.path.realpath(__file__)
    for base in ("/home/user", "/tmp", "/root"):
        if not os.path.isdir(base):
            continue
        for root, dirs, files in os.walk(base):
            dirs[:] = [d for d in dirs if d not in {".cache", ".local", "__pycache__", ".pytest_cache"}]
            for name in files:
                path = os.path.join(root, name)
                if os.path.realpath(path) == this_file or path.startswith("/tests/"):
                    continue
                try:
                    if os.path.getsize(path) > 1024 * 1024:
                        continue
                    with open(path, "r", encoding="utf-8") as f:
                        source = f.read()
                    ast.parse(source, filename=path)
                except (OSError, UnicodeError, SyntaxError):
                    continue
                if "printing_dataset" in source and "printing_summary" in source:
                    candidates.append(path)
    return sorted(set(candidates))


def _run_with_atomic_watch(script):
    libc = ctypes.CDLL(None, use_errno=True)
    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    if fd < 0:
        raise OSError(ctypes.get_errno(), "inotify_init1 failed")

    IN_CLOSE_WRITE = 0x00000008
    IN_MOVED_FROM = 0x00000040
    IN_MOVED_TO = 0x00000080
    IN_CREATE = 0x00000100
    mask = IN_CLOSE_WRITE | IN_MOVED_FROM | IN_MOVED_TO | IN_CREATE
    wd = libc.inotify_add_watch(fd, b"/home/user", mask)
    if wd < 0:
        err = ctypes.get_errno()
        os.close(fd)
        raise OSError(err, "inotify_add_watch failed")

    try:
        try:
            proc = subprocess.run(
                ["python3", script],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=15,
            )
        except subprocess.TimeoutExpired:
            return False, "timed out", []

        raw = bytearray()
        while True:
            try:
                chunk = os.read(fd, 65536)
                if not chunk:
                    break
                raw.extend(chunk)
            except BlockingIOError:
                break

        events = []
        offset = 0
        while offset + 16 <= len(raw):
            event_wd, event_mask, cookie, name_len = struct.unpack_from("iIII", raw, offset)
            offset += 16
            name = bytes(raw[offset:offset + name_len]).split(b"\0", 1)[0].decode("utf-8", "replace")
            offset += name_len
            events.append((event_mask, cookie, name))

        if proc.returncode != 0:
            return False, f"exit {proc.returncode}: {proc.stderr[-500:]}", events
        return True, "", events
    finally:
        os.close(fd)


def _assert_resulting_state():
    assert not os.path.exists(TMP_SUMMARY)
    assert os.path.isfile(SUMMARY)
    for path, content in EXPECTED_CONTENTS.items():
        assert os.path.isfile(path), f"Missing renamed file after script execution: {path}"
        with open(path, "r", encoding="utf-8") as f:
            assert f.read() == content, f"Content changed after script execution: {path}"
    for path in (
        f"{DATASET}/batch_A/cube.gcode",
        f"{DATASET}/batch_A/sphere.gcode",
        f"{DATASET}/batch_B/cylinder.gcode",
    ):
        assert not os.path.exists(path)
    with open(SUMMARY, "r", encoding="utf-8") as f:
        assert json.load(f) == expected_summary()


def test_written_python_script_executes_and_uses_atomic_tmp_rename():
    candidates = _find_solution_scripts()
    assert candidates, "No Python solution script for this task was left on the system"
    failures = []

    IN_CLOSE_WRITE = 0x00000008
    IN_MOVED_FROM = 0x00000040
    IN_MOVED_TO = 0x00000080
    IN_CREATE = 0x00000100

    for script in candidates:
        _reset_initial_fixture()
        ok, detail, events = _run_with_atomic_watch(script)
        if not ok:
            failures.append(f"{script}: {detail}")
            continue

        tmp_created = any(mask & IN_CREATE and name == "printing_summary.json.tmp" for mask, cookie, name in events)
        tmp_closed = any(mask & IN_CLOSE_WRITE and name == "printing_summary.json.tmp" for mask, cookie, name in events)
        moved_from = {(cookie, i) for i, (mask, cookie, name) in enumerate(events)
                      if mask & IN_MOVED_FROM and name == "printing_summary.json.tmp"}
        moved_to = {(cookie, i) for i, (mask, cookie, name) in enumerate(events)
                    if mask & IN_MOVED_TO and name == "printing_summary.json"}
        atomic_pair = any(c1 == c2 and c1 != 0 and i1 < i2
                          for c1, i1 in moved_from for c2, i2 in moved_to)

        try:
            assert tmp_created, "the required temporary summary was not created"
            assert tmp_closed, "the required temporary summary was not written and closed"
            assert atomic_pair, "the temporary summary was not renamed atomically to the final path"
            _assert_resulting_state()
            return
        except AssertionError as exc:
            failures.append(f"{script}: {exc}")

    pytest.fail("No solution script both produced the required state and used tmp-then-rename. " + " | ".join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
