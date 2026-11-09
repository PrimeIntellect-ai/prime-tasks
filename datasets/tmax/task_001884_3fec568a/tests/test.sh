#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import secrets
import struct
import subprocess
import tempfile
import pytest

PROGRAM = "/home/user/filter.go"
MAGIC = b"KONF"
EVIL = b"badconf"


def run_filter(input_dir, output_dir):
    return subprocess.run(
        ["go", "run", PROGRAM, input_dir, output_dir],
        capture_output=True,
        text=True,
        timeout=60,
    )


def test_filter_go_exists():
    assert os.path.isfile(PROGRAM), "The Go program /home/user/filter.go was not found."


def test_clean_corpus_processing():
    clean_dir = "/home/user/corpus/clean"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing at {clean_dir}"

    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    with tempfile.TemporaryDirectory() as output_dir:
        result = run_filter(clean_dir, output_dir)
        assert result.returncode == 0, f"Go program failed on clean corpus. Error: {result.stderr}"

        output_files = set(os.listdir(output_dir))
        failed_clean = []
        for cf in clean_files:
            expected_out = f"{cf}.json"
            if expected_out not in output_files:
                failed_clean.append(cf)
                continue

            try:
                with open(os.path.join(clean_dir, cf), "rb") as f:
                    source = f.read()
                assert source.startswith(MAGIC)
                expected_payload = source[len(MAGIC):].decode("utf-8")
                with open(os.path.join(output_dir, expected_out), "r", encoding="utf-8") as f:
                    data = json.load(f)
                if "config_data" not in data or data != {"config_data": expected_payload}:
                    failed_clean.append(cf)
            except Exception:
                failed_clean.append(cf)

        if failed_clean:
            pytest.fail(f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected. Offending files: {', '.join(failed_clean)}")


def test_evil_corpus_processing():
    evil_dir = "/home/user/corpus/evil"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing at {evil_dir}"

    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    with tempfile.TemporaryDirectory() as output_dir:
        result = run_filter(evil_dir, output_dir)
        assert result.returncode == 0, f"Go program failed on evil corpus. Error: {result.stderr}"

        output_files = set(os.listdir(output_dir))
        bypassed_evil = []
        for ef in evil_files:
            expected_out = f"{ef}.json"
            if expected_out in output_files:
                bypassed_evil.append(ef)

        if bypassed_evil:
            pytest.fail(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed. Offending files: {', '.join(bypassed_evil)}")


def test_randomized_conversion_and_filtering():
    token = secrets.token_hex(16)
    clean_payloads = {
        f"empty-{token}.bin": "",
        f"plain-{token}.bin": f"user={token};mode=production",
        f"unicode-{token}.bin": f"region=東京;token={token};enabled=true",
    }
    rejected = {
        f"bad-magic-{token}.bin": b"NOPE" + f"value={token}".encode(),
        f"evil-middle-{token}.bin": MAGIC + f"before-{token}-badconf-after".encode(),
        f"evil-start-{token}.bin": MAGIC + EVIL + token.encode(),
        f"evil-end-{token}.bin": MAGIC + token.encode() + EVIL,
    }

    with tempfile.TemporaryDirectory() as input_dir, tempfile.TemporaryDirectory() as output_dir:
        for name, payload in clean_payloads.items():
            with open(os.path.join(input_dir, name), "wb") as f:
                f.write(MAGIC + payload.encode("utf-8"))
        for name, contents in rejected.items():
            with open(os.path.join(input_dir, name), "wb") as f:
                f.write(contents)

        result = run_filter(input_dir, output_dir)
        assert result.returncode == 0, f"Go program failed on generated corpus: {result.stderr}"

        expected_names = {name + ".json" for name in clean_payloads}
        assert set(os.listdir(output_dir)) == expected_names, "Generated corpus was not filtered correctly"

        for name, expected_payload in clean_payloads.items():
            path = os.path.join(output_dir, name + ".json")
            with open(path, "r", encoding="utf-8") as f:
                value = json.load(f)
            assert value == {"config_data": expected_payload}, f"Incorrect converted payload for {name}"


def test_output_is_installed_by_atomic_rename():
    libc = ctypes.CDLL(None, use_errno=True)
    inotify_init1 = libc.inotify_init1
    inotify_init1.argtypes = [ctypes.c_int]
    inotify_init1.restype = ctypes.c_int
    inotify_add_watch = libc.inotify_add_watch
    inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    inotify_add_watch.restype = ctypes.c_int

    IN_MODIFY = 0x00000002
    IN_CLOSE_WRITE = 0x00000008
    IN_MOVED_TO = 0x00000080
    IN_CREATE = 0x00000100
    watch_mask = IN_MODIFY | IN_CLOSE_WRITE | IN_MOVED_TO | IN_CREATE

    token = secrets.token_hex(12)
    input_name = f"atomic-{token}.bin"
    output_name = input_name + ".json"
    payload = f"atomic-check-{token}"

    with tempfile.TemporaryDirectory() as input_dir, tempfile.TemporaryDirectory() as output_dir:
        with open(os.path.join(input_dir, input_name), "wb") as f:
            f.write(MAGIC + payload.encode())

        fd = inotify_init1(os.O_NONBLOCK)
        assert fd >= 0, "Unable to initialize filesystem event monitor"
        try:
            wd = inotify_add_watch(fd, output_dir.encode(), watch_mask)
            assert wd >= 0, "Unable to monitor output directory"

            result = run_filter(input_dir, output_dir)
            assert result.returncode == 0, f"Go program failed during atomic-write test: {result.stderr}"

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
                    _, mask, _, name_len = struct.unpack_from("iIII", block, offset)
                    offset += 16
                    raw_name = block[offset:offset + name_len]
                    offset += name_len
                    name = raw_name.split(b"\0", 1)[0].decode("utf-8", "replace")
                    events.append((name, mask))
        finally:
            os.close(fd)

        target_events = [mask for name, mask in events if name == output_name]
        assert any(mask & IN_MOVED_TO for mask in target_events), "Final JSON was not installed with an atomic rename"
        assert not any(mask & (IN_CREATE | IN_MODIFY | IN_CLOSE_WRITE) for mask in target_events), "Final JSON path was written directly instead of atomically renamed"

        with open(os.path.join(output_dir, output_name), "r", encoding="utf-8") as f:
            assert json.load(f) == {"config_data": payload}
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
