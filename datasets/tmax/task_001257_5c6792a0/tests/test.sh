#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import select
import struct
import subprocess
import uuid
from pathlib import Path


def assert_original_fixture():
    go_file = "/home/user/doc_builder.go"
    assert os.path.isfile(go_file), f"Go source file {go_file} is missing."

    with open(go_file, "r") as f:
        content = f.read()
    assert "os.Rename" in content, "The Go program does not appear to use os.Rename for atomic writes."

    dist_dir = "/home/user/dist"
    assert os.path.isdir(dist_dir), f"Output directory {dist_dir} is missing."

    expected_files = {
        "getting_started_part1.md": 50,
        "getting_started_part2.md": 20,
        "networking_part1.md": 50,
        "networking_part2.md": 50,
        "networking_part3.md": 20,
        "api_ref.md": 30,
    }
    actual_files = set(os.listdir(dist_dir))

    for filename, expected_lines in expected_files.items():
        filepath = os.path.join(dist_dir, filename)
        assert os.path.isfile(filepath), f"Expected output file {filename} is missing."
        with open(filepath, "r") as f:
            lines = f.readlines()
        assert len(lines) == expected_lines, (
            f"File {filename} should have {expected_lines} lines, but has {len(lines)}."
        )

    unexpected = actual_files - set(expected_files)
    assert not unexpected, f"Unexpected files found in {dist_dir}: {unexpected}"

    def check_sequence(filename, start, end):
        filepath = os.path.join(dist_dir, filename)
        with open(filepath, "r") as f:
            lines = [line.strip() for line in f.readlines()]
        expected = [str(i) for i in range(start, end + 1)]
        assert lines == expected, (
            f"Content of {filename} does not match expected sequence from {start} to {end}."
        )

    check_sequence("getting_started_part1.md", 1, 50)
    check_sequence("getting_started_part2.md", 51, 70)
    check_sequence("networking_part1.md", 1, 50)
    check_sequence("networking_part2.md", 51, 100)
    check_sequence("networking_part3.md", 101, 120)
    check_sequence("api_ref.md", 1, 30)


def line_bytes(prefix, count):
    return [f"{prefix}:{i}:value-{uuid.uuid4().hex}\n".encode() for i in range(count)]


def chunked_outputs(name, lines, limit):
    if len(lines) <= limit:
        return {name: b"".join(lines)}
    stem = name[:-3] if name.endswith(".md") else name
    result = {}
    for offset in range(0, len(lines), limit):
        part = offset // limit + 1
        result[f"{stem}_part{part}.md"] = b"".join(lines[offset:offset + limit])
    return result


def start_inotify(directory):
    libc = ctypes.CDLL(None, use_errno=True)
    libc.inotify_init1.argtypes = [ctypes.c_int]
    libc.inotify_init1.restype = ctypes.c_int
    libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    libc.inotify_add_watch.restype = ctypes.c_int

    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    assert fd >= 0, f"inotify_init1 failed: errno {ctypes.get_errno()}"
    IN_MOVED_TO = 0x00000080
    wd = libc.inotify_add_watch(fd, os.fsencode(directory), IN_MOVED_TO)
    assert wd >= 0, f"inotify_add_watch failed: errno {ctypes.get_errno()}"
    return fd


def read_moved_to(fd):
    names = set()
    while True:
        ready, _, _ = select.select([fd], [], [], 0)
        if not ready:
            break
        try:
            data = os.read(fd, 65536)
        except BlockingIOError:
            break
        if not data:
            break
        offset = 0
        while offset + 16 <= len(data):
            _, mask, _, name_len = struct.unpack_from("iIII", data, offset)
            offset += 16
            raw_name = data[offset:offset + name_len]
            offset += name_len
            if mask & 0x00000080:
                names.add(os.fsdecode(raw_name.split(b"\0", 1)[0]))
    return names


def run_generated_case(binary, source_dir, output_dir, limit, files, merge_groups,
                       expected, precreate_output, require_atomic_events):
    source = Path(source_dir)
    output = Path(output_dir)
    source.mkdir(parents=True)
    if precreate_output:
        output.mkdir(parents=True)
    else:
        assert not output.exists()

    for relpath, lines in files.items():
        path = source / relpath
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"".join(lines))

    ignored = source / "nested" / f"ignored_{uuid.uuid4().hex}.txt"
    ignored.parent.mkdir(parents=True, exist_ok=True)
    ignored.write_text("this is not markdown\n", encoding="utf-8")

    config = {
        "merge_groups": merge_groups,
        "max_lines_per_chunk": limit,
        "output_dir": str(output),
        "source_dir": str(source),
    }
    with open("/home/user/config.json", "w", encoding="utf-8") as f:
        json.dump(config, f, indent=3, sort_keys=True)

    notify_fd = start_inotify(str(output)) if require_atomic_events else None
    try:
        proc = subprocess.run(
            [binary], cwd="/home/user", stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=20
        )
        assert proc.returncode == 0, (
            f"Generated-case execution failed with {proc.returncode}.\n"
            f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
        )
        moved_to = read_moved_to(notify_fd) if notify_fd is not None else set()
    finally:
        if notify_fd is not None:
            os.close(notify_fd)

    assert output.is_dir(), "The configured output directory was not created."
    actual_names = set(os.listdir(output))
    assert actual_names == set(expected), (
        f"Generated case produced the wrong files: expected {set(expected)}, got {actual_names}"
    )
    for name, wanted in expected.items():
        path = output / name
        assert path.is_file(), f"Generated output {name} is not a regular file."
        assert path.read_bytes() == wanted, f"Generated output {name} has incorrect content."

    if require_atomic_events:
        missing_moves = set(expected) - moved_to
        assert not missing_moves, (
            "These final files were not atomically published by rename: "
            f"{sorted(missing_moves)}; observed rename destinations: {sorted(moved_to)}"
        )


def test_complete_submission():
    assert_original_fixture()

    binary = f"/tmp/doc_builder_{uuid.uuid4().hex}"
    build = subprocess.run(
        ["go", "build", "-o", binary, "/home/user/doc_builder.go"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert build.returncode == 0, f"Go program did not compile:\n{build.stderr}"

    token = uuid.uuid4().hex
    first = line_bytes(f"first-{token}", 5)
    second = line_bytes(f"second-{token}", 4)
    exact = line_bytes(f"exact-{token}", 4)
    long_standalone = line_bytes(f"long-{token}", 6)
    merge_target = f"assembled_{token}.md"
    exact_name = f"exact_{token}.md"
    long_name = f"long_{token}.md"
    files = {
        f"z/deeper/first_{token}.md": first,
        f"a/second_{token}.md": second,
        f"nested/{exact_name}": exact,
        f"other/deep/{long_name}": long_standalone,
    }
    groups = {
        merge_target: [f"z/deeper/first_{token}.md", f"a/second_{token}.md"]
    }
    expected = {}
    expected.update(chunked_outputs(merge_target, first + second, 4))
    expected.update(chunked_outputs(exact_name, exact, 4))
    expected.update(chunked_outputs(long_name, long_standalone, 4))
    run_generated_case(
        binary,
        f"/tmp/source_{token}",
        f"/tmp/output_{token}",
        4,
        files,
        groups,
        expected,
        precreate_output=True,
        require_atomic_events=True,
    )

    token2 = uuid.uuid4().hex
    left = line_bytes(f"left-{token2}", 2)
    right = line_bytes(f"right-{token2}", 3)
    solo = line_bytes(f"solo-{token2}", 8)
    target2 = f"small_merge_{token2}.md"
    solo_name = f"solo_{token2}.md"
    files2 = {
        f"deep/right_{token2}.md": right,
        f"left_{token2}.md": left,
        f"more/depth/{solo_name}": solo,
    }
    groups2 = {
        target2: [f"left_{token2}.md", f"deep/right_{token2}.md"]
    }
    expected2 = {}
    expected2.update(chunked_outputs(target2, left + right, 7))
    expected2.update(chunked_outputs(solo_name, solo, 7))
    run_generated_case(
        binary,
        f"/tmp/source_{token2}",
        f"/tmp/missing_parent_{token2}/output",
        7,
        files2,
        groups2,
        expected2,
        precreate_output=False,
        require_atomic_events=False,
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
