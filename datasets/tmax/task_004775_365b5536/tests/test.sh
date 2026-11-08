#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import random
import re
import shutil
import struct
import subprocess
import tempfile
import time
import uuid

SCRIPT_PATH = "/home/user/curator.py"
MAGIC = b'FWPK\x01\x00\x00\x00\x00\x00\x00\x00'


def sha256(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def run_curator(input_dir, output_dir):
    result = subprocess.run(
        ["python3", SCRIPT_PATH, input_dir, output_dir],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr


def load_manifest(path):
    assert os.path.exists(path), f"Missing manifest: {path}"
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"Invalid JSON in {path}: {exc}")


def write_fw(path, magic, metadata, payload, claimed_length=None):
    encoded = json.dumps(metadata, separators=(",", ":")).encode("utf-8")
    length = len(encoded) if claimed_length is None else claimed_length
    with open(path, "wb") as f:
        f.write(magic)
        f.write(struct.pack("<I", length))
        f.write(encoded)
        f.write(payload)


def test_curator_script_on_original_corpora():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} not found."

    clean_in = "/app/corpus/clean"
    evil_in = "/app/corpus/evil"
    clean_out = "/tmp/out_clean"
    evil_out = "/tmp/out_evil"
    shutil.rmtree(clean_out, ignore_errors=True)
    shutil.rmtree(evil_out, ignore_errors=True)
    os.makedirs(clean_out)
    os.makedirs(evil_out)

    run_curator(clean_in, clean_out)
    run_curator(evil_in, evil_out)

    clean_files = [f for f in os.listdir(clean_in) if f.endswith(".fw")]
    out_clean_files = [f for f in os.listdir(clean_out) if f.endswith(".fw")]
    missing_clean = set(clean_files) - set(out_clean_files)
    assert not missing_clean, (
        f"{len(missing_clean)} of {len(clean_files)} clean files modified or rejected: "
        f"{missing_clean}"
    )

    manifest_clean = load_manifest(os.path.join(clean_out, "manifest.json"))
    for name in clean_files:
        assert name in manifest_clean, f"{name} is missing from manifest.json"
        expected_hash = sha256(os.path.join(clean_in, name))
        assert manifest_clean[name] == expected_hash, f"SHA256 mismatch for {name}"
        with open(os.path.join(clean_in, name), "rb") as source:
            expected_bytes = source.read()
        with open(os.path.join(clean_out, name), "rb") as copied:
            assert copied.read() == expected_bytes, f"Accepted file {name} was not copied exactly"

    evil_files = [f for f in os.listdir(evil_in) if f.endswith(".fw")]
    out_evil_files = [f for f in os.listdir(evil_out) if f.endswith(".fw")]
    assert not out_evil_files, (
        f"{len(out_evil_files)} of {len(evil_files)} evil files bypassed rejection: "
        f"{out_evil_files}"
    )

    evil_manifest_path = os.path.join(evil_out, "manifest.json")
    if os.path.exists(evil_manifest_path):
        manifest_evil = load_manifest(evil_manifest_path)
        assert not manifest_evil, f"Evil manifest should be empty: {manifest_evil}"


def test_runtime_generated_mixed_corpus_and_atomic_manifest():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} not found."

    root = tempfile.mkdtemp(prefix="fw-check-")
    input_dir = os.path.join(root, uuid.uuid4().hex)
    output_dir = os.path.join(root, uuid.uuid4().hex)
    os.makedirs(input_dir)
    os.makedirs(output_dir)

    accepted = {}
    rejected = set()

    clean_count = random.randint(4, 7)
    for i in range(clean_count):
        name = uuid.uuid4().hex + ".fw"
        path = os.path.join(input_dir, name)
        write_fw(
            path,
            MAGIC,
            {"filename": f"device_{uuid.uuid4().hex}.bin", "version": f"{i + 1}.0"},
            os.urandom(random.randint(17, 257)),
        )
        accepted[name] = path

    malformed_length_name = uuid.uuid4().hex + ".fw"
    malformed_length_path = os.path.join(input_dir, malformed_length_name)
    write_fw(
        malformed_length_path,
        MAGIC,
        {"filename": "device.bin"},
        os.urandom(31),
        claimed_length=1000000,
    )
    rejected.add(malformed_length_name)

    bad_magic_name = uuid.uuid4().hex + ".fw"
    write_fw(
        os.path.join(input_dir, bad_magic_name),
        b"BADK" + MAGIC[4:],
        {"filename": "device.bin"},
        os.urandom(41),
    )
    rejected.add(bad_magic_name)

    for target in ("../outside.bin", "folder/../../outside.bin"):
        name = uuid.uuid4().hex + ".fw"
        write_fw(
            os.path.join(input_dir, name),
            MAGIC,
            {"filename": target, "version": "9.9"},
            os.urandom(random.randint(20, 90)),
        )
        rejected.add(name)

    # A pre-existing valid manifest makes replacement atomicity observable: an
    # atomic writer must replace it rather than truncate it in place.
    sentinel = {"preexisting": "sentinel"}
    manifest_path = os.path.join(output_dir, "manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(sentinel, f)

    expected_manifest = {name: sha256(path) for name, path in accepted.items()}
    trace_path = os.path.join(root, "syscalls.trace")
    command = [
        "strace", "-f", "-qq",
        "-e", "trace=open,openat,creat,rename,renameat,renameat2,unlink,unlinkat",
        "-o", trace_path,
        "python3", SCRIPT_PATH, input_dir, output_dir,
    ]
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    observed_bad_state = None
    while process.poll() is None:
        try:
            with open(manifest_path, "r", encoding="utf-8") as f:
                observed = json.load(f)
            if observed != sentinel and observed != expected_manifest:
                observed_bad_state = f"unexpected intermediate manifest: {observed!r}"
                break
        except (FileNotFoundError, json.JSONDecodeError) as exc:
            observed_bad_state = f"manifest was non-atomic while curator ran: {exc}"
            break
        time.sleep(0.0002)

    stdout, stderr = process.communicate()
    assert process.returncode == 0, f"Curator failed. stdout={stdout!r} stderr={stderr!r}"
    assert observed_bad_state is None, observed_bad_state

    output_fw = {name for name in os.listdir(output_dir) if name.endswith(".fw")}
    assert output_fw == set(accepted), (
        f"Expected exactly {set(accepted)}, but output contained {output_fw}"
    )

    for name, source_path in accepted.items():
        output_path = os.path.join(output_dir, name)
        with open(source_path, "rb") as source, open(output_path, "rb") as copied:
            assert copied.read() == source.read(), f"Accepted file {name} was not copied exactly"

    assert not (rejected & output_fw), f"Rejected files were copied: {rejected & output_fw}"
    assert load_manifest(manifest_path) == expected_manifest

    with open(trace_path, "r", encoding="utf-8", errors="replace") as f:
        trace_lines = f.read().splitlines()

    atomic_replace_seen = False
    direct_manifest_write = []
    manifest_unlink = []
    for line in trace_lines:
        quoted = re.findall(r'"((?:[^"\\]|\\.)*)"', line)
        syscall = re.search(r"\b(renameat2|renameat|rename|openat|open|creat|unlinkat|unlink)\(", line)
        if not syscall or not quoted:
            continue
        call = syscall.group(1)
        successful = re.search(r"=\s*0\s*$", line) is not None

        if call in {"rename", "renameat", "renameat2"} and successful:
            destination = quoted[-1]
            if os.path.basename(destination) == "manifest.json":
                atomic_replace_seen = True

        referenced_manifest = any(os.path.basename(path) == "manifest.json" for path in quoted)
        if referenced_manifest and call in {"open", "openat", "creat"}:
            if call == "creat" or re.search(r"O_(WRONLY|RDWR|TRUNC)", line):
                direct_manifest_write.append(line)
        if referenced_manifest and call in {"unlink", "unlinkat"} and successful:
            manifest_unlink.append(line)

    assert atomic_replace_seen, "manifest.json was not installed with an atomic rename"
    assert not direct_manifest_write, (
        "manifest.json was opened for direct/in-place writing instead of atomic replacement: "
        + "\n".join(direct_manifest_write)
    )
    assert not manifest_unlink, (
        "manifest.json was unlinked before replacement, creating a non-atomic gap: "
        + "\n".join(manifest_unlink)
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
