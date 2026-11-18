#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import errno
import filecmp
import json
import os
import random
import re
import string
import subprocess
import tempfile
import time
import uuid

SANITIZER = "/home/user/log_sanitizer"


def run_sanitizer(input_bytes):
    with tempfile.TemporaryDirectory() as td:
        inp = os.path.join(td, "input.jsonl")
        out = os.path.join(td, "output.jsonl")
        with open(inp, "wb") as f:
            f.write(input_bytes)
        result = subprocess.run([SANITIZER, inp, out], stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=10)
        assert result.returncode == 0, result.stderr.decode(errors="replace")
        assert os.path.exists(out), "Sanitizer did not create its output file"
        assert not os.path.exists(out + ".tmp"), "Temporary output remained after success"
        with open(out, "rb") as f:
            return f.read()


def test_cjson_built():
    static_lib = "/app/cJSON/libcjson.a"
    shared_lib = "/app/cJSON/libcjson.so"
    assert os.path.exists(static_lib), "/app/cJSON/libcjson.a is missing. The Makefile was not fixed or built."
    assert os.path.exists(shared_lib), "/app/cJSON/libcjson.so is missing. The Makefile was not fixed or built."
    with open(static_lib, "rb") as f:
        assert f.read(8) == b"!<arch>\n", "libcjson.a is not a static archive"
    lib = ctypes.CDLL(shared_lib)
    assert getattr(lib, "cJSON_Parse", None) is not None, "libcjson.so lacks cJSON_Parse"
    assert getattr(lib, "cJSON_Delete", None) is not None, "libcjson.so lacks cJSON_Delete"


def test_sanitizer_executable():
    assert os.path.exists(SANITIZER), f"{SANITIZER} is missing."
    assert os.access(SANITIZER, os.X_OK), f"{SANITIZER} is not executable."
    with open(SANITIZER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "log_sanitizer is not a compiled native program"

    symbols = subprocess.run(
        ["readelf", "-Ws", SANITIZER], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, check=True
    ).stdout
    assert re.search(r"\bcJSON_Parse(?:WithOpts)?\b", symbols), \
        "Compiled sanitizer does not reference cJSON parsing"
    assert re.search(r"\bcJSON_Delete\b", symbols), \
        "Compiled sanitizer does not reference cJSON cleanup"


def test_exact_argument_count():
    no_args = subprocess.run([SANITIZER], stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, timeout=5)
    assert no_args.returncode != 0, "Sanitizer accepted zero file arguments"
    with tempfile.TemporaryDirectory() as td:
        inp = os.path.join(td, "in")
        out = os.path.join(td, "out")
        with open(inp, "w") as f:
            f.write('{"ok":true}\n')
        extra = subprocess.run([SANITIZER, inp, out, "extra"], stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, timeout=5)
        assert extra.returncode != 0, "Sanitizer accepted more than two arguments"


def test_adversarial_corpus():
    evil_dir = "/app/corpora/evil/"
    clean_dir = "/app/corpora/clean/"
    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_bypassed = []
    clean_modified = []

    with tempfile.TemporaryDirectory() as tmpdir:
        for f in evil_files:
            in_path = os.path.join(evil_dir, f)
            out_path = os.path.join(tmpdir, f + ".out")
            subprocess.run([SANITIZER, in_path, out_path], check=True, timeout=10)
            if os.path.exists(out_path) and os.path.getsize(out_path) > 0:
                evil_bypassed.append(f)

        for f in clean_files:
            in_path = os.path.join(clean_dir, f)
            out_path = os.path.join(tmpdir, f + ".out")
            subprocess.run([SANITIZER, in_path, out_path], check=True, timeout=10)
            if not os.path.exists(out_path) or not filecmp.cmp(in_path, out_path, shallow=False):
                clean_modified.append(f)

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    assert not errors, " | ".join(errors)


def test_generated_json_semantics_and_exact_preservation():
    token = uuid.uuid4().hex
    rng = random.SystemRandom()
    lines = []

    objects = [
        {"message": "clean-" + token, "value": rng.randrange(1, 10**9)},
        {"core_dump": "drop-" + token, "other": rng.randrange(1, 10**9)},
        {"nested": {"core_dump": "not-top-level-" + token}, "keep": True},
        {"message": "the text core_dump is harmless", "token": token},
        {"Core_Dump": "case-sensitive", "token": token},
    ]
    for i, obj in enumerate(objects):
        if i % 2:
            text = json.dumps(obj, separators=(",", ":"), sort_keys=True)
        else:
            text = "  " + json.dumps(obj, separators=(", ", ": ")) + "  "
        lines.append((text + "\n").encode())

    # This key is semantically core_dump after JSON escape decoding, but does not
    # contain the literal substring that a grep-based implementation expects.
    escaped_key_line = ('{"core_\\u0064ump":"escaped-' + token + '","n":' +
                        str(rng.randrange(1, 10**9)) + '}\n').encode()
    lines.insert(rng.randrange(len(lines) + 1), escaped_key_line)

    rng.shuffle(lines)
    expected = b"".join(
        line for line in lines
        if "core_dump" not in json.loads(line.decode())
    )
    assert run_sanitizer(b"".join(lines)) == expected


def test_atomic_write_implemented():
    src_file = "/home/user/log_sanitizer.c"
    assert os.path.exists(src_file), f"{src_file} is missing."
    with open(src_file, "r") as f:
        src = f.read()
    assert ".tmp" in src, "The C source does not seem to use a .tmp file for atomic writes."
    assert "rename" in src, "The C source does not seem to use rename() for atomic writes."


def test_atomic_write_behavior():
    with tempfile.TemporaryDirectory() as td:
        fifo = os.path.join(td, "stream")
        out = os.path.join(td, "result.jsonl")
        tmp = out + ".tmp"
        os.mkfifo(fifo)
        sentinel = b"PREVIOUS-COMPLETE-FILE\n"
        with open(out, "wb") as f:
            f.write(sentinel)

        proc = subprocess.Popen([SANITIZER, fifo, out], stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE)
        writer = None
        deadline = time.time() + 5
        while time.time() < deadline:
            try:
                writer = os.open(fifo, os.O_WRONLY | os.O_NONBLOCK)
                break
            except OSError as e:
                if e.errno != errno.ENXIO:
                    raise
                assert proc.poll() is None, "Sanitizer exited before opening its input"
                time.sleep(0.02)
        assert writer is not None, "Sanitizer did not open the input FIFO"

        first = b'{"message":"first-' + uuid.uuid4().hex.encode() + b'"}\n'
        os.write(writer, first)

        deadline = time.time() + 5
        while time.time() < deadline and not os.path.exists(tmp):
            assert proc.poll() is None, "Sanitizer exited while input was still open"
            time.sleep(0.02)
        assert os.path.exists(tmp), "Sanitizer did not write through <output>.tmp"
        with open(out, "rb") as f:
            assert f.read() == sentinel, "Final output was modified before processing completed"

        os.write(writer, b'{"core_dump":"discard-me"}\n')
        os.close(writer)
        stdout, stderr = proc.communicate(timeout=10)
        assert proc.returncode == 0, stderr.decode(errors="replace")
        assert not os.path.exists(tmp), "Temporary file remains after atomic rename"
        with open(out, "rb") as f:
            assert f.read() == first, "Atomic result has incorrect content"


def wait_for_output(path, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if os.path.exists(path):
            return
        time.sleep(0.05)


def test_watch_logs_script():
    script_path = "/home/user/watch_logs.sh"
    assert os.path.exists(script_path), f"{script_path} is missing."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."

    test_file = "test_integration.log"
    in_path = os.path.join("/var/spool/incoming_logs", test_file)
    out_path = os.path.join("/var/log/sanitized_logs", test_file)
    if os.path.exists(out_path):
        os.remove(out_path)
    with open(in_path, "w") as f:
        f.write('{"message": "hello"}\n')
        f.write('{"core_dump": "bad"}\n')
    wait_for_output(out_path)
    assert os.path.exists(out_path), f"Integration test failed: {out_path} was not created. Is watch_logs.sh running in the background?"
    with open(out_path, "r") as f:
        content = f.read()
    assert '{"message": "hello"}\n' in content, "Clean log not preserved in integration test."
    assert "core_dump" not in content, "Evil log not filtered in integration test."


def test_watch_logs_generated_payload():
    name = "verify-" + uuid.uuid4().hex + ".jsonl"
    in_path = os.path.join("/var/spool/incoming_logs", name)
    out_path = os.path.join("/var/log/sanitized_logs", name)
    token = uuid.uuid4().hex
    lines = [
        (' {"message":"' + token + '","core_dump_text":"keep"} \n').encode(),
        ('{"core_\\u0064ump":"drop-' + token + '"}\n').encode(),
        ('{"nested":{"core_dump":"keep-nested"},"id":"' + token + '"}\n').encode(),
    ]
    expected = b"".join(line for line in lines if "core_dump" not in json.loads(line.decode()))
    if os.path.exists(out_path):
        os.remove(out_path)
    with open(in_path, "wb") as f:
        f.write(b"".join(lines))
    wait_for_output(out_path)
    assert os.path.exists(out_path), "Watcher did not process a newly closed, randomly named file"
    with open(out_path, "rb") as f:
        assert f.read() == expected, "Watcher output was not the sanitizer's exact expected output"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
