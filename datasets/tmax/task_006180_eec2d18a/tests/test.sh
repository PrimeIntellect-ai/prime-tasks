#!/bin/bash
set -u
mkdir -p /logs/verifier

SCRIPT=/home/user/organize_datasets.py
if [[ ! -f "$SCRIPT" || -L "$SCRIPT" ]]; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

mkdir -p /tmp/verifier_hook
cat << 'HOOK_EOF' > /tmp/verifier_hook/sitecustomize.py
import json
import os

_log_path = "/tmp/organize_atomic_events.jsonl"
_real_rename = os.rename
_real_replace = os.replace

def _record(op, src, dst):
    try:
        src = os.path.abspath(os.fspath(src))
        dst = os.path.abspath(os.fspath(dst))
        with open(_log_path, "a", encoding="utf-8") as f:
            f.write(json.dumps({"op": op, "src": src, "dst": dst}) + "\n")
    except Exception:
        pass

def rename(src, dst, *args, **kwargs):
    result = _real_rename(src, dst, *args, **kwargs)
    _record("rename", src, dst)
    return result

def replace(src, dst, *args, **kwargs):
    result = _real_replace(src, dst, *args, **kwargs)
    _record("replace", src, dst)
    return result

os.rename = rename
os.replace = replace
HOOK_EOF

rm -f /tmp/organize_atomic_events.jsonl /tmp/organize_dynamic.json

if ! python3 << 'FIXTURE_EOF'
import json
import os
import secrets
import struct
import uuid

incoming = "/home/user/incoming_data"
organized = "/home/user/organized_data"
tag = "verify_" + uuid.uuid4().hex


def rle(data):
    out = bytearray()
    i = 0
    while i < len(data):
        value = data[i]
        count = 1
        while i + count < len(data) and data[i + count] == value and count < 255:
            count += 1
        out.extend((value, count))
        i += count
    return bytes(out)


def write_case(suffix, magic, class_id, declared_length, payload, marker=None):
    base = tag + "_" + suffix
    dat_path = os.path.join(incoming, base + ".dat")
    with open(dat_path, "wb") as f:
        f.write(struct.pack("<IHH", magic, class_id, declared_length))
        f.write(payload)
    if marker is not None:
        with open(os.path.join(incoming, base + ".ready"), "wb") as f:
            f.write(marker)
    return base, dat_path

random_part = secrets.token_bytes(513)
valid_specs = [
    ("mixed", 31337, b"\x00" * 256 + b"\xff" + b"Q" * 510 + random_part + b"\x00"),
    ("alternating", 54321, bytes(range(256)) + b"AABCCCC" + secrets.token_bytes(97)),
    ("empty", 0, b""),
]

valid = []
for suffix, class_id, payload in valid_specs:
    base, dat_path = write_case(suffix, 0xDEADBEEF, class_id, len(payload), payload, b"")
    target = os.path.join(organized, f"class_{class_id}", base + ".dat.rle")
    try:
        os.unlink(target)
    except FileNotFoundError:
        pass
    valid.append({
        "base": base,
        "class_id": class_id,
        "dat_path": dat_path,
        "ready_path": os.path.join(incoming, base + ".ready"),
        "target": target,
        "expected_hex": rle(payload).hex(),
    })

invalid = []
base, path = write_case("no_ready", 0xDEADBEEF, 120, 8, b"NOREADY", None)
invalid.append({"base": base, "paths": [path]})

base, path = write_case("nonempty_ready", 0xDEADBEEF, 121, 4, b"BUSY", b"not empty")
invalid.append({"base": base, "paths": [path, os.path.join(incoming, base + ".ready")]})

base, path = write_case("bad_magic", 0x12345678, 122, 5, b"MAGIC", b"")
invalid.append({"base": base, "paths": [path, os.path.join(incoming, base + ".ready")]})

base, path = write_case("truncated", 0xDEADBEEF, 123, 20, b"short", b"")
invalid.append({"base": base, "paths": [path, os.path.join(incoming, base + ".ready")]})

base, path = write_case("trailing", 0xDEADBEEF, 124, 3, b"abcEXTRA", b"")
invalid.append({"base": base, "paths": [path, os.path.join(incoming, base + ".ready")]})

base = tag + "_short_header"
path = os.path.join(incoming, base + ".dat")
with open(path, "wb") as f:
    f.write(b"\xef\xbe\xad")
ready = os.path.join(incoming, base + ".ready")
open(ready, "wb").close()
invalid.append({"base": base, "paths": [path, ready]})

with open("/tmp/organize_dynamic.json", "w", encoding="utf-8") as f:
    json.dump({"tag": tag, "valid": valid, "invalid": invalid}, f)
FIXTURE_EOF
then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

if ! PYTHONPATH=/tmp/verifier_hook python3 "$SCRIPT"; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os

INCOMING_DIR = "/home/user/incoming_data"
ORGANIZED_DIR = "/home/user/organized_data"
SCRIPT = "/home/user/organize_datasets.py"

with open("/tmp/organize_dynamic.json", encoding="utf-8") as f:
    DYNAMIC = json.load(f)


def test_script_exists_and_is_a_regular_file():
    assert os.path.isfile(SCRIPT), f"Required script {SCRIPT} is missing."
    assert not os.path.islink(SCRIPT), f"Required script {SCRIPT} must be an actual file, not a symlink."


def test_chunk_a_processed_correctly():
    expected_file = os.path.join(ORGANIZED_DIR, "class_1", "chunk_a.dat.rle")
    assert os.path.isfile(expected_file), f"Expected processed file {expected_file} is missing."

    with open(expected_file, "rb") as f:
        content = f.read()

    expected_content = bytes([0x41, 0x05, 0x42, 0x05])
    assert content == expected_content, f"Content of {expected_file} is incorrect. Expected {expected_content.hex()}, got {content.hex()}."


def test_chunk_d_processed_correctly():
    expected_file = os.path.join(ORGANIZED_DIR, "class_5", "chunk_d.dat.rle")
    assert os.path.isfile(expected_file), f"Expected processed file {expected_file} is missing."

    with open(expected_file, "rb") as f:
        content = f.read()

    expected_content = bytes([0x58, 0xFF, 0x58, 0x2D, 0x59, 0x02])
    assert content == expected_content, f"Content of {expected_file} is incorrect. Expected {expected_content.hex()}, got {content.hex()}."


def test_invalid_chunks_skipped():
    # chunk_b has no ready file, chunk_c has invalid magic. Neither should be processed.
    for root, dirs, files in os.walk(ORGANIZED_DIR):
        for file in files:
            assert "chunk_b" not in file, f"Found {file} in {ORGANIZED_DIR}, but chunk_b should have been skipped (no .ready file)."
            assert "chunk_c" not in file, f"Found {file} in {ORGANIZED_DIR}, but chunk_c should have been skipped (invalid magic number)."


def test_original_files_not_deleted():
    original_files = [
        "chunk_a.dat", "chunk_a.ready",
        "chunk_b.dat",
        "chunk_c.dat", "chunk_c.ready",
        "chunk_d.dat", "chunk_d.ready"
    ]
    for filename in original_files:
        filepath = os.path.join(INCOMING_DIR, filename)
        assert os.path.isfile(filepath), f"Original file {filepath} was deleted, but instructions said 'Do not delete the original files'."


def test_dynamic_valid_files_are_parsed_and_rle_encoded():
    for case in DYNAMIC["valid"]:
        assert os.path.isfile(case["target"]), f"Missing dynamically generated output {case['target']}"
        with open(case["target"], "rb") as f:
            actual = f.read()
        expected = bytes.fromhex(case["expected_hex"])
        assert actual == expected, (
            f"Incorrect RLE output for {case['base']}: expected {expected.hex()}, got {actual.hex()}"
        )


def test_dynamic_unsynchronized_and_malformed_files_are_skipped():
    invalid_bases = {case["base"] for case in DYNAMIC["invalid"]}
    for _, _, files in os.walk(ORGANIZED_DIR):
        for filename in files:
            assert not any(base in filename for base in invalid_bases), (
                f"Invalid or unsynchronized input was processed into {filename}"
            )


def test_all_dynamic_input_files_and_markers_remain():
    paths = []
    for case in DYNAMIC["valid"]:
        paths.extend((case["dat_path"], case["ready_path"]))
    for case in DYNAMIC["invalid"]:
        paths.extend(case["paths"])
    for path in paths:
        assert os.path.isfile(path), f"Original input or marker was deleted: {path}"


def test_dynamic_outputs_were_installed_by_atomic_rename():
    events = []
    if os.path.exists("/tmp/organize_atomic_events.jsonl"):
        with open("/tmp/organize_atomic_events.jsonl", encoding="utf-8") as f:
            for line in f:
                if line.strip():
                    events.append(json.loads(line))

    for case in DYNAMIC["valid"]:
        target = os.path.abspath(case["target"])
        matching = [event for event in events if event.get("dst") == target]
        assert matching, f"No rename/replace installed dynamic output atomically: {target}"
        assert any(
            event.get("src") != target
            and os.path.dirname(event.get("src", "")) == os.path.dirname(target)
            for event in matching
        ), f"Output {target} was not renamed from a temporary file in its target directory"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
