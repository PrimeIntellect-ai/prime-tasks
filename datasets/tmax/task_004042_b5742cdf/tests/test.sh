#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import stat
import struct
import subprocess
import tempfile
import uuid
from pathlib import Path

FRAME_SIZE = 6220800


def run_student_script(input_dir, output_dir):
    script_path = "/home/user/storage_manager.py"
    assert os.path.isfile(script_path), f"Student script not found at {script_path}"

    try:
        return subprocess.run(
            ["python3", script_path, str(input_dir), str(output_dir)],
            capture_output=True,
            text=True,
            timeout=60
        )
    except subprocess.TimeoutExpired:
        assert False, "Student script timed out after 60 seconds."


def expected_info(frm1):
    data = Path(frm1).read_bytes()
    assert len(data) >= 20, f"Verifier fixture is truncated: {frm1}"
    assert data[:4] == b"FRM1", f"Verifier fixture has bad magic: {frm1}"
    original_size, compressed_size = struct.unpack("<QQ", data[4:20])
    assert original_size == FRAME_SIZE, f"Verifier fixture has wrong original size: {frm1}"
    rle = data[20:]
    assert compressed_size == len(rle), f"Verifier fixture has wrong compressed size: {frm1}"
    assert len(rle) % 2 == 0, f"Verifier fixture has incomplete RLE data: {frm1}"

    digest = hashlib.sha256()
    total = 0
    for pos in range(0, len(rle), 2):
        count = rle[pos]
        value = rle[pos + 1]
        assert count != 0, f"Verifier fixture contains a zero count: {frm1}"
        total += count
        assert total <= FRAME_SIZE, f"Verifier fixture expands too far: {frm1}"
        digest.update(bytes((value,)) * count)
    assert total == FRAME_SIZE, f"Verifier fixture expands to the wrong size: {frm1}"
    return digest.hexdigest(), total


def file_sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            chunk = f.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def verify_outputs(input_files, out_dir):
    out_dir = Path(out_dir)
    seq_dir = out_dir / "sequence"
    obj_dir = out_dir / "objects"
    assert seq_dir.is_dir(), f"Sequence directory not created at {seq_dir}"
    assert obj_dir.is_dir(), f"Objects directory not created at {obj_dir}"

    expected = {Path(p).stem: expected_info(p) for p in input_files}
    expected_object_names = {f"{digest}.raw" for digest, _ in expected.values()}
    actual_sequence_names = {p.name for p in seq_dir.iterdir()}
    assert actual_sequence_names == {f"{stem}.raw" for stem in expected}, \
        "Sequence directory does not correspond exactly to the valid input files"

    checked_objects = set()
    failed = []
    for stem, (digest, size) in expected.items():
        link = seq_dir / f"{stem}.raw"
        object_path = obj_dir / f"{digest}.raw"
        if not link.is_symlink():
            failed.append(f"{stem}: missing symlink")
            continue
        if link.resolve() != object_path.resolve() or not object_path.exists():
            failed.append(f"{stem}: symlink points to the wrong object")
            continue

        linked_stat = link.stat()
        object_stat = object_path.stat()
        if linked_stat.st_ino != object_stat.st_ino or linked_stat.st_dev != object_stat.st_dev:
            failed.append(f"{stem}: sequence entry does not resolve to its object inode")
            continue

        if digest not in checked_objects:
            if object_path.is_symlink() or not stat.S_ISREG(object_path.lstat().st_mode):
                failed.append(f"{stem}: object is not a regular file")
            elif object_stat.st_size != size:
                failed.append(f"{stem}: object has size {object_stat.st_size}, expected {size}")
            elif object_path.name != f"{digest}.raw":
                failed.append(f"{stem}: object name is not its SHA-256 digest")
            elif file_sha256(object_path) != digest:
                failed.append(f"{stem}: decompressed object bytes do not match the input")
            checked_objects.add(digest)

    if failed:
        assert False, "Incorrect output correspondence: " + "; ".join(failed[:10])

    actual_object_names = {p.name for p in obj_dir.iterdir()}
    assert actual_object_names == expected_object_names, \
        "Objects directory does not contain exactly the SHA-256-named decompressed objects"


def make_rle_constant(value, total=FRAME_SIZE):
    out = bytearray()
    remaining = total
    while remaining:
        count = min(255, remaining)
        out.extend((count, value))
        remaining -= count
    return bytes(out)


def make_rle_pattern(seed, total=FRAME_SIZE):
    out = bytearray()
    remaining = total
    run = 0
    while remaining:
        count = min(remaining, 1 + ((run * 37 + seed * 19) % 255))
        value = (run * 53 + seed * 29) % 256
        out.extend((count, value))
        remaining -= count
        run += 1
    return bytes(out)


def write_frm1(path, rle, magic=b"FRM1", original_size=FRAME_SIZE, compressed_size=None):
    if compressed_size is None:
        compressed_size = len(rle)
    with open(path, "wb") as f:
        f.write(magic)
        f.write(struct.pack("<Q", original_size))
        f.write(struct.pack("<Q", compressed_size))
        f.write(rle)


def test_clean_corpus_processing():
    clean_dir = Path("/app/clean_corpus")
    assert clean_dir.is_dir(), f"Clean corpus missing at {clean_dir}"

    frm1_files = list(clean_dir.glob("*.frm1"))
    assert len(frm1_files) > 0, "No .frm1 files found in clean corpus."

    with tempfile.TemporaryDirectory() as temp_out:
        out_dir = Path(temp_out)
        result = run_student_script(clean_dir, out_dir)

        seq_dir = out_dir / "sequence"
        obj_dir = out_dir / "objects"

        assert seq_dir.is_dir(), f"Sequence directory not created at {seq_dir}"
        assert obj_dir.is_dir(), f"Objects directory not created at {obj_dir}"

        failed_clean = []
        for frm1 in frm1_files:
            expected_symlink = seq_dir / f"{frm1.stem}.raw"
            if not expected_symlink.is_symlink():
                failed_clean.append(frm1.name)
                continue

            target = expected_symlink.resolve()
            if not target.is_file() or target.parent != obj_dir:
                failed_clean.append(frm1.name)

        if failed_clean:
            assert False, f"{len(failed_clean)} of {len(frm1_files)} clean files were modified/rejected or incorrectly processed. Offending files: {', '.join(failed_clean[:10])}"

        objects = list(obj_dir.glob("*.raw"))
        assert len(objects) == 40, f"Expected exactly 40 deduplicated objects in clean output, found {len(objects)}"

        inodes = set()
        for obj in objects:
            inodes.add(obj.stat().st_ino)
        assert len(inodes) == 40, f"Expected 40 unique inodes in objects directory, found {len(inodes)}"

        verify_outputs(frm1_files, out_dir)


def test_evil_corpus_rejection():
    evil_dir = Path("/app/evil_corpus")
    assert evil_dir.is_dir(), f"Evil corpus missing at {evil_dir}"

    frm1_files = list(evil_dir.glob("*.frm1"))
    assert len(frm1_files) > 0, "No .frm1 files found in evil corpus."

    with tempfile.TemporaryDirectory() as temp_out:
        out_dir = Path(temp_out)
        result = run_student_script(evil_dir, out_dir)

        seq_dir = out_dir / "sequence"

        bypassed_evil = []
        for frm1 in frm1_files:
            expected_symlink = seq_dir / f"{frm1.stem}.raw"
            if expected_symlink.exists() or expected_symlink.is_symlink():
                bypassed_evil.append(frm1.name)

        if bypassed_evil:
            assert False, f"{len(bypassed_evil)} of {len(frm1_files)} evil files bypassed validation. Offending files: {', '.join(bypassed_evil[:10])}"

        obj_dir = out_dir / "objects"
        if obj_dir.is_dir():
            objects = list(obj_dir.glob("*.raw"))
            assert len(objects) == 0, f"Expected 0 objects from evil corpus, found {len(objects)}"
            assert list(obj_dir.iterdir()) == [], "Evil corpus produced unexpected object entries"
        if seq_dir.is_dir():
            assert list(seq_dir.iterdir()) == [], "Evil corpus produced unexpected sequence entries"


def test_generated_mixed_corpus_content_hashes_and_rejection():
    token = uuid.uuid4().hex
    with tempfile.TemporaryDirectory() as temp_in, tempfile.TemporaryDirectory() as temp_out:
        input_dir = Path(temp_in)
        output_dir = Path(temp_out)

        rle_a = make_rle_pattern(7)
        rle_b = make_rle_pattern(11)
        rle_c = make_rle_constant(193)
        valid = [
            input_dir / f"{token}_alpha.frm1",
            input_dir / f"{token}_beta.frm1",
            input_dir / f"{token}_duplicate.frm1",
            input_dir / f"{token}_constant.frm1",
        ]
        write_frm1(valid[0], rle_a)
        write_frm1(valid[1], rle_b)
        write_frm1(valid[2], rle_a)
        write_frm1(valid[3], rle_c)

        write_frm1(input_dir / f"{token}_bad_magic.frm1", rle_a, magic=b"BAD1")
        write_frm1(input_dir / f"{token}_bad_original.frm1", rle_a, original_size=FRAME_SIZE - 1)
        write_frm1(input_dir / f"{token}_bad_compressed.frm1", rle_a, compressed_size=len(rle_a) + 1)
        zero_rle = bytearray(rle_a)
        zero_rle[0] = 0
        write_frm1(input_dir / f"{token}_zero.frm1", bytes(zero_rle))
        write_frm1(input_dir / f"{token}_under.frm1", make_rle_constant(4, FRAME_SIZE - 1))
        write_frm1(input_dir / f"{token}_over.frm1", make_rle_constant(5, FRAME_SIZE + 1))
        write_frm1(input_dir / f"{token}_odd.frm1", rle_a + b"\x01")
        (input_dir / f"{token}_truncated.frm1").write_bytes(b"FRM1\x00")
        write_frm1(input_dir / f"{token}_huge_claim.frm1", b"", compressed_size=2**63)

        result = run_student_script(input_dir, output_dir)
        verify_outputs(valid, output_dir)

        seq_dir = output_dir / "sequence"
        obj_dir = output_dir / "objects"
        assert len(list(seq_dir.iterdir())) == len(valid), "Malformed inputs produced sequence outputs"
        assert len(list(obj_dir.iterdir())) == 3, "Expected three unique objects from four valid generated inputs"

        first = seq_dir / f"{valid[0].stem}.raw"
        duplicate = seq_dir / f"{valid[2].stem}.raw"
        assert first.resolve() == duplicate.resolve(), "Duplicate frames did not use the same deduplicated object"
        assert first.stat().st_ino == duplicate.stat().st_ino, "Duplicate frames do not resolve to the same inode"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
