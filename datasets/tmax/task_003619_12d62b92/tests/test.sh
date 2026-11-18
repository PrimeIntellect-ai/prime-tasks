#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import os
import re
import shutil
import stat
import subprocess

DATA_DIR = "/home/user/dataset"
CATS_DIR = "/home/user/categories"
RULES_FILE = "/home/user/rules.csv"
SOURCE_FILE = "/home/user/organizer.c"
XXHASH_DIR = "/app/xxHash-0.8.2"
LIB_FILE = os.path.join(XXHASH_DIR, "libxxhash.a")


def get_file_hash(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            chunk = f.read(8192)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def parse_rules():
    rules = []
    with open(RULES_FILE, newline="") as f:
        for row in csv.reader(f):
            if len(row) < 3:
                continue
            try:
                min_size = int(row[1].strip())
            except ValueError:
                continue
            rules.append((row[0].strip(), min_size, row[2].strip().lower()))
    return rules


def category_entries():
    entries = []
    if not os.path.lexists(CATS_DIR):
        return entries
    assert os.path.isdir(CATS_DIR) and not os.path.islink(CATS_DIR), \
        f"{CATS_DIR} must be a real directory"
    for cat_name in os.listdir(CATS_DIR):
        cat_path = os.path.join(CATS_DIR, cat_name)
        assert os.path.isdir(cat_path) and not os.path.islink(cat_path), \
            f"Unexpected non-directory category entry: {cat_path}"
        for filename in os.listdir(cat_path):
            entries.append((cat_name, filename, os.path.join(cat_path, filename)))
    return entries


def calculate_and_assert_score():
    rules = parse_rules()
    total_logical_size = 0
    unique_contents = {}
    file_contents = {}

    for filename in os.listdir(DATA_DIR):
        path = os.path.join(DATA_DIR, filename)
        if not os.path.isfile(path):
            continue
        st = os.stat(path)
        total_logical_size += st.st_size
        file_hash = get_file_hash(path)
        file_contents[filename] = file_hash
        if file_hash not in unique_contents:
            unique_contents[file_hash] = st.st_size

    ideal_physical_size = sum(unique_contents.values())
    inodes = set()
    total_physical_size = 0
    for filename in os.listdir(DATA_DIR):
        path = os.path.join(DATA_DIR, filename)
        if not os.path.isfile(path):
            continue
        st = os.stat(path)
        inode = (st.st_dev, st.st_ino)
        if inode not in inodes:
            inodes.add(inode)
            total_physical_size += st.st_size

    if total_logical_size > ideal_physical_size:
        space_score = ((total_logical_size - total_physical_size) /
                       (total_logical_size - ideal_physical_size))
    else:
        space_score = 1.0
    space_score = min(max(space_score, 0.0), 1.0)

    content_to_categories = {h: set() for h in unique_contents}
    samples = {}
    for filename, file_hash in file_contents.items():
        samples.setdefault(file_hash, os.path.join(DATA_DIR, filename))

    for file_hash, sample_path in samples.items():
        with open(sample_path, "rb") as f:
            header = f.read(16).hex().lower()
        for cat_name, min_size, magic_hex in rules:
            if unique_contents[file_hash] >= min_size and header.startswith(magic_hex):
                content_to_categories[file_hash].add(cat_name)

    actual_symlinks = []
    entries = category_entries()
    for cat_name, filename, link_path in entries:
        assert os.path.islink(link_path), f"Category entry is not a symlink: {link_path}"
        target_path = os.path.realpath(link_path)
        try:
            inside_dataset = os.path.commonpath([target_path, DATA_DIR]) == DATA_DIR
        except ValueError:
            inside_dataset = False
        if inside_dataset and os.path.isfile(target_path):
            actual_symlinks.append((cat_name, get_file_hash(target_path)))
        else:
            actual_symlinks.append((cat_name, None))

    actual_content_cats = set(actual_symlinks)
    tp = 0
    fp = 0
    for cat_name, file_hash in actual_content_cats:
        if cat_name in content_to_categories.get(file_hash, set()):
            tp += 1
        else:
            fp += 1

    fn = 0
    expected_count = 0
    for file_hash, expected_cats in content_to_categories.items():
        for cat_name in expected_cats:
            expected_count += 1
            if (cat_name, file_hash) not in actual_content_cats:
                fn += 1

    if tp + fp == 0:
        precision = 1.0 if tp + fn == 0 else 0.0
    else:
        precision = tp / (tp + fp)
    recall = 1.0 if tp + fn == 0 else tp / (tp + fn)
    f1_score = 0.0 if precision + recall == 0 else 2 * precision * recall / (precision + recall)
    final_score = space_score * f1_score

    assert final_score >= 0.95, (
        f"Combined optimization score is too low: {final_score:.4f} < 0.95.\n"
        f"Space Score: {space_score:.4f} (Logical: {total_logical_size}, "
        f"Physical: {total_physical_size}, Ideal: {ideal_physical_size})\n"
        f"Symlink F1 Score: {f1_score:.4f} (TP: {tp}, FP: {fp}, FN: {fn})"
    )
    assert len(entries) == expected_count, \
        f"Expected exactly {expected_count} category symlinks, found {len(entries)}"


def remove_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def test_full_workflow():
    expected_original = {
        f"file_{i}.bin": f"dummy data {i}\n".encode() for i in range(1, 11)
    }
    assert os.path.isdir(DATA_DIR) and not os.path.islink(DATA_DIR)
    assert set(os.listdir(DATA_DIR)) == set(expected_original), "Dataset filenames were not preserved"
    for filename, expected in expected_original.items():
        path = os.path.join(DATA_DIR, filename)
        assert stat.S_ISREG(os.lstat(path).st_mode) and not os.path.islink(path)
        with open(path, "rb") as f:
            assert f.read() == expected, f"Input file was modified: {filename}"

    expected_rules = b"Archives,500,504B0304\nDocuments,200,25504446\n"
    with open(RULES_FILE, "rb") as f:
        assert f.read() == expected_rules, "rules.csv was modified"

    # The shipped data has no duplicates and matches no rule. This must be a
    # perfect result, not an F1 failure caused by an empty prediction set.
    calculate_and_assert_score()

    assert os.path.isfile(SOURCE_FILE), "Missing /home/user/organizer.c"
    with open(SOURCE_FILE, "r", errors="replace") as f:
        source = f.read()
    assert re.search(r"\bmmap\s*\(", source), "organizer.c does not call mmap"
    assert re.search(r"\bXXH64\s*\(", source), "organizer.c does not call XXH64"

    makefile = os.path.join(XXHASH_DIR, "Makefile")
    with open(makefile, "r", errors="replace") as f:
        make_text = f.read()
    assert not re.search(r"^\s*CC\s*(?:\?|\+|:)?=\s*NOPE_COMPILER\b", make_text, re.M), \
        "The corrupted compiler assignment was not fixed"

    subprocess.run(["make", "-B", "libxxhash.a"], cwd=XXHASH_DIR,
                   check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                   text=True, timeout=120)
    assert os.path.isfile(LIB_FILE), "libxxhash.a was not produced"
    subprocess.run(["ar", "t", LIB_FILE], check=True, stdout=subprocess.PIPE,
                   stderr=subprocess.STDOUT, text=True, timeout=30)

    verified_binary = "/tmp/organizer_verified"
    subprocess.run([
        "gcc", SOURCE_FILE, "-I", XXHASH_DIR, LIB_FILE, "-o", verified_binary
    ], check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
       text=True, timeout=120)

    symbols = subprocess.run(["nm", verified_binary], check=True,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             text=True, timeout=30).stdout
    assert re.search(r"\bXXH64$", symbols, re.M), \
        "The compiled organizer does not contain the statically linked XXH64 implementation"
    assert re.search(r"\bU\s+mmap(?:@|$)", symbols, re.M), \
        "The compiled organizer does not use mmap"

    # Exercise the compiled artifact on derived inputs that require both
    # deduplication and categorization.
    for name in os.listdir(DATA_DIR):
        remove_path(os.path.join(DATA_DIR, name))
    if os.path.lexists(CATS_DIR):
        remove_path(CATS_DIR)

    zip_blob = b"PK\x03\x04" + bytes(range(256)) * 3
    pdf_blob = b"%PDF" + b"D" * 300
    fixture = {
        "archive_a.bin": zip_blob,
        "archive_b.bin": zip_blob,
        "document_a.bin": pdf_blob,
        "document_b.bin": pdf_blob,
        "small.bin": b"unique-small-file" * 5,
    }
    for filename, data in fixture.items():
        with open(os.path.join(DATA_DIR, filename), "wb") as f:
            f.write(data)

    subprocess.run([verified_binary], check=True, stdout=subprocess.PIPE,
                   stderr=subprocess.STDOUT, text=True, timeout=120,
                   cwd="/home/user")

    assert set(os.listdir(DATA_DIR)) == set(fixture), "Organizer removed or renamed input files"
    for filename, expected in fixture.items():
        path = os.path.join(DATA_DIR, filename)
        assert stat.S_ISREG(os.lstat(path).st_mode) and not os.path.islink(path)
        with open(path, "rb") as f:
            assert f.read() == expected, f"Organizer changed file contents: {filename}"

    assert os.stat(os.path.join(DATA_DIR, "archive_a.bin")).st_ino == \
           os.stat(os.path.join(DATA_DIR, "archive_b.bin")).st_ino, \
           "Archive duplicates were not replaced with hard links"
    assert os.stat(os.path.join(DATA_DIR, "document_a.bin")).st_ino == \
           os.stat(os.path.join(DATA_DIR, "document_b.bin")).st_ino, \
           "Document duplicates were not replaced with hard links"

    with open(RULES_FILE, "rb") as f:
        assert f.read() == expected_rules, "Organizer modified rules.csv"

    calculate_and_assert_score()
    for _, filename, link_path in category_entries():
        target = os.path.realpath(link_path)
        assert filename == os.path.basename(target), \
            f"Symlink name does not match its target filename: {link_path}"


if __name__ == "__main__":
    test_full_workflow()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
