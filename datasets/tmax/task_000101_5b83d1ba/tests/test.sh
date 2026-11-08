#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import resource
import signal
import struct
import subprocess
import tempfile
import time

import pytest

CONVERTER_GO = "/home/user/converter.go"
LEGACY_PARSER = "/app/legacy_parser"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
COMPILED_BIN = "/tmp/converter_bin"
MAGIC = b"BKP\x01"


def blob(entries, magic=MAGIC, declared_count=None, trailing=b""):
    count = len(entries) if declared_count is None else declared_count
    data = bytearray(magic)
    data.append(count)
    for name, payload, declared_size in entries:
        name_bytes = name.encode("ascii")
        data.append(len(name_bytes))
        data.extend(name_bytes)
        size = len(payload) if declared_size is None else declared_size
        data.extend(struct.pack("<I", size))
        data.extend(payload)
    data.extend(trailing)
    return bytes(data)


def expected(entries):
    return [{"name": name, "size": len(payload) if size is None else size}
            for name, payload, size in entries]


def run_converter(input_path, output_path, **kwargs):
    return subprocess.run(
        [COMPILED_BIN, input_path, output_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        **kwargs,
    )


@pytest.fixture(scope="session", autouse=True)
def compile_go_program():
    assert os.path.isfile(CONVERTER_GO), f"Missing required file: {CONVERTER_GO}"
    result = subprocess.run(
        ["go", "build", "-o", COMPILED_BIN, CONVERTER_GO],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr
    yield
    if os.path.exists(COMPILED_BIN):
        os.remove(COMPILED_BIN)


def test_clean_corpus_original_assertions(tmp_path):
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, name)
                   for name in os.listdir(CLEAN_CORPUS_DIR)
                   if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, name))]
    assert clean_files
    for index, input_path in enumerate(clean_files):
        output_path = tmp_path / f"clean-{index}.json"
        result = run_converter(input_path, str(output_path))
        assert result.returncode == 0, os.path.basename(input_path)
        assert output_path.exists(), os.path.basename(input_path)
        legacy = subprocess.run([LEGACY_PARSER, input_path], capture_output=True, text=True)
        assert legacy.returncode == 0
        with output_path.open() as f:
            actual = json.load(f)
        assert actual == json.loads(legacy.stdout)


def test_evil_corpus_original_assertions(tmp_path):
    evil_files = [os.path.join(EVIL_CORPUS_DIR, name)
                  for name in os.listdir(EVIL_CORPUS_DIR)
                  if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, name))]
    assert evil_files
    for index, input_path in enumerate(evil_files):
        output_path = tmp_path / f"evil-{index}.json"
        result = run_converter(input_path, str(output_path))
        assert result.returncode != 0, os.path.basename(input_path)
        assert not output_path.exists(), os.path.basename(input_path)


def test_random_valid_inputs_and_unpredictable_paths(tmp_path):
    rng = random.SystemRandom()
    for case in range(12):
        entries = []
        for item in range(rng.randrange(0, 12)):
            name = "n%08x_%d.dat" % (rng.getrandbits(32), item)
            payload = os.urandom(rng.randrange(0, 300))
            entries.append((name, payload, None))
        input_path = tmp_path / ("input_%016x.data" % rng.getrandbits(64))
        output_path = tmp_path / ("result_%016x.json" % rng.getrandbits(64))
        input_path.write_bytes(blob(entries))
        result = run_converter(str(input_path), str(output_path))
        assert result.returncode == 0
        assert output_path.exists()
        with output_path.open() as f:
            assert json.load(f) == expected(entries)


def test_generated_malformed_and_traversal_inputs(tmp_path):
    good = blob([("safe.txt", b"payload", None)])
    malformed = [
        b"",
        b"B",
        b"BKP\x01",
        blob([("safe.txt", b"x", None)], magic=b"BKP\x00"),
        blob([("safe.txt", b"x", None)], magic=b"NOPE"),
        blob([("safe.txt", b"x", None)], declared_count=2),
        blob([("safe.txt", b"x", 5000)]),
        good[:-1],
        good + b"unexpected-trailing-data",
        blob([("../secret", b"x", None)]),
        blob([("a..b", b"x", None)]),
        blob([("dir/file", b"x", None)]),
        blob([("dir\\file", b"x", None)]),
    ]
    # Exercise every truncation boundary using randomized, unknown path names.
    malformed.extend(good[:cut] for cut in range(len(good)))
    for index, contents in enumerate(malformed):
        input_path = tmp_path / ("bad_%d_%016x.bin" % (index, random.getrandbits(64)))
        output_path = tmp_path / ("must_not_exist_%016x.json" % random.getrandbits(64))
        input_path.write_bytes(contents)
        result = run_converter(str(input_path), str(output_path))
        assert result.returncode != 0, f"accepted malformed case {index}"
        assert not output_path.exists(), f"created output for malformed case {index}"


def test_exact_two_argument_interface(tmp_path):
    input_path = tmp_path / "valid.bin"
    input_path.write_bytes(blob([("ok", b"x", None)]))

    invocations = [
        [COMPILED_BIN],
        [COMPILED_BIN, str(input_path)],
        [COMPILED_BIN, str(input_path), str(tmp_path / "three.json"), "extra"],
    ]
    for command in invocations:
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert result.returncode != 0
    assert not (tmp_path / "three.json").exists()


def test_successful_write_uses_same_directory_temp_and_rename(tmp_path):
    entries = [("entry_%03d_%s" % (i, "x" * 80), b"z" * 8, None) for i in range(200)]
    input_path = tmp_path / "atomic-input.bin"
    output_path = tmp_path / "atomic-output.json"
    input_path.write_bytes(blob(entries))
    output_path.write_text("old contents")

    libc = ctypes.CDLL(None, use_errno=True)
    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    assert fd >= 0
    IN_CREATE = 0x00000100
    IN_MOVED_TO = 0x00000080
    wd = libc.inotify_add_watch(fd, os.fsencode(tmp_path), IN_CREATE | IN_MOVED_TO)
    assert wd >= 0
    try:
        result = run_converter(str(input_path), str(output_path))
        assert result.returncode == 0
        time.sleep(0.02)
        raw = b""
        while True:
            try:
                raw += os.read(fd, 65536)
            except BlockingIOError:
                break
    finally:
        os.close(fd)

    events = []
    offset = 0
    while offset + 16 <= len(raw):
        _, mask, _, name_len = struct.unpack_from("iIII", raw, offset)
        offset += 16
        name = raw[offset:offset + name_len].split(b"\0", 1)[0].decode(errors="replace")
        offset += name_len
        events.append((mask, name))

    assert any(mask & IN_MOVED_TO and name == output_path.name for mask, name in events), \
        "output was not installed by rename"
    assert any(mask & IN_CREATE and name != output_path.name for mask, name in events), \
        "no temporary file was created in the output directory"
    with output_path.open() as f:
        assert json.load(f) == expected(entries)


def test_failed_atomic_write_preserves_existing_output(tmp_path):
    entries = [("long_%03d_%s" % (i, "q" * 120), b"", None) for i in range(255)]
    input_path = tmp_path / "large.bin"
    output_path = tmp_path / "existing.json"
    input_path.write_bytes(blob(entries))
    sentinel = b"PREEXISTING-DATA-MUST-SURVIVE"
    output_path.write_bytes(sentinel)

    def limit_output_size():
        signal.signal(signal.SIGXFSZ, signal.SIG_IGN)
        resource.setrlimit(resource.RLIMIT_FSIZE, (1024, 1024))

    result = run_converter(str(input_path), str(output_path), preexec_fn=limit_output_size)
    assert result.returncode != 0
    assert output_path.read_bytes() == sentinel
PYTEST

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
