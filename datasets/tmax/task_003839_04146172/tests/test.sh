#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import pytest

CLEAN_DIR = "/app/corpus/clean"
EVIL_DIR = "/app/corpus/evil"
SOURCE_FILE = "/home/user/primer_filter.cpp"
EXECUTABLE = "/home/user/primer_filter"
SVG_FILE = "/home/user/gc_density.svg"


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} not found."
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable."
    assert os.path.isfile(SOURCE_FILE), f"C++ source {SOURCE_FILE} not found."
    assert os.path.getsize(SOURCE_FILE) > 0, f"C++ source {SOURCE_FILE} is empty."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not a compiled executable."


def _number(value):
    if value is None:
        return None
    match = re.match(r"^\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+))", value)
    return float(match.group(1)) if match else None


def test_svg_exists_and_not_empty():
    assert os.path.isfile(SVG_FILE), f"SVG file {SVG_FILE} not found."
    assert os.path.getsize(SVG_FILE) > 0, f"SVG file {SVG_FILE} is empty."
    with open(SVG_FILE, "r") as f:
        content = f.read()
    assert "<svg" in content.lower(), f"{SVG_FILE} does not appear to be a valid SVG file."

    try:
        root = ET.fromstring(content)
    except ET.ParseError as exc:
        pytest.fail(f"{SVG_FILE} is not well-formed XML: {exc}")
    assert root.tag.split("}")[-1].lower() == "svg", f"{SVG_FILE} has no SVG root element."

    # A histogram must contain multiple non-degenerate visible plotting marks,
    # rather than merely an empty SVG container or the '<svg' substring.
    marks = 0
    for element in root.iter():
        tag = element.tag.split("}")[-1].lower()
        if tag == "rect":
            width = _number(element.get("width"))
            height = _number(element.get("height"))
            if width is not None and height is not None and width > 0 and height > 0:
                marks += 1
        elif tag == "path" and len((element.get("d") or "").strip()) >= 4:
            marks += 1
        elif tag in {"polygon", "polyline"}:
            points = re.findall(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)", element.get("points") or "")
            if len(points) >= 6:
                marks += 1
        elif tag == "line":
            coords = [_number(element.get(k)) for k in ("x1", "y1", "x2", "y2")]
            if all(v is not None for v in coords) and (coords[0] != coords[2] or coords[1] != coords[3]):
                marks += 1
    assert marks >= 2, f"{SVG_FILE} does not contain multiple graphical marks representing histogram bins."


def test_adversarial_corpus_clean():
    if not os.path.isdir(CLEAN_DIR):
        pytest.skip(f"Clean corpus directory {CLEAN_DIR} not found.")

    clean_files = [os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR) if f.endswith(".fasta") or f.endswith(".fa")]
    if not clean_files:
        pytest.skip(f"No FASTA files found in {CLEAN_DIR}.")

    failed_clean = []
    for f in clean_files:
        result = subprocess.run([EXECUTABLE, f], capture_output=True)
        if result.returncode != 0:
            failed_clean.append(os.path.basename(f))

    assert not failed_clean, f"{len(failed_clean)} of {len(clean_files)} clean files were incorrectly rejected: {', '.join(failed_clean[:10])}"


def test_adversarial_corpus_evil():
    if not os.path.isdir(EVIL_DIR):
        pytest.skip(f"Evil corpus directory {EVIL_DIR} not found.")

    evil_files = [os.path.join(EVIL_DIR, f) for f in os.listdir(EVIL_DIR) if f.endswith(".fasta") or f.endswith(".fa")]
    if not evil_files:
        pytest.skip(f"No FASTA files found in {EVIL_DIR}.")

    bypassed_evil = []
    for f in evil_files:
        result = subprocess.run([EXECUTABLE, f], capture_output=True)
        if result.returncode == 0:
            bypassed_evil.append(os.path.basename(f))

    assert not bypassed_evil, f"{len(bypassed_evil)} of {len(evil_files)} evil files bypassed the filter: {', '.join(bypassed_evil[:10])}"


def _properties(seq):
    gc = sum(base in "GC" for base in seq)
    tm = 2 * (len(seq) - gc) + 4 * gc
    longest = 1
    current = 1
    for i in range(1, len(seq)):
        if seq[i] == seq[i - 1]:
            current += 1
            longest = max(longest, current)
        else:
            current = 1
    gc_ok = 5 * gc >= 2 * len(seq) and 5 * gc <= 3 * len(seq)
    return tm, longest, gc_ok


def _expected(seq):
    tm, longest, gc_ok = _properties(seq)
    return 0 if 60 <= tm <= 66 and longest <= 3 and gc_ok else 1


def test_classifier_on_derived_unseen_inputs():
    rng = random.Random(918273645)
    pools = {"valid": [], "tm_only": [], "gc_only": [], "run_only": []}
    all_cases = []

    # Answers are independently derived from the recovered assay constraints.
    # The mixed cases are placed together under fresh neutral paths, preventing
    # classification based on the known clean/evil directory names.
    for _ in range(30000):
        length = rng.randint(17, 27)
        seq = "".join(rng.choice("ACGT") for _ in range(length))
        tm, longest, gc_ok = _properties(seq)
        tm_ok = 60 <= tm <= 66
        run_ok = longest <= 3
        expected = 0 if tm_ok and run_ok and gc_ok else 1
        if len(all_cases) < 180:
            all_cases.append((seq, expected))
        if tm_ok and run_ok and gc_ok and len(pools["valid"]) < 25:
            pools["valid"].append(seq)
        if not tm_ok and run_ok and gc_ok and len(pools["tm_only"]) < 25:
            pools["tm_only"].append(seq)
        if tm_ok and run_ok and not gc_ok and len(pools["gc_only"]) < 25:
            pools["gc_only"].append(seq)
        if tm_ok and not run_ok and gc_ok and len(pools["run_only"]) < 25:
            pools["run_only"].append(seq)

    assert all(len(values) >= 12 for values in pools.values()), "Verifier failed to generate sufficient coverage."
    cases = all_cases + [(seq, _expected(seq)) for values in pools.values() for seq in values]
    rng.shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix="primer_inputs_") as directory:
        for index, (seq, expected) in enumerate(cases):
            path = os.path.join(directory, f"sample_{index:04d}.fasta")
            chunks = [seq[i:i + 5] for i in range(0, len(seq), 5)]
            with open(path, "w") as f:
                f.write(f">candidate_{index}\n")
                for j, chunk in enumerate(chunks):
                    f.write(("  " if j % 2 == 0 else "\t") + chunk + " \n")
            try:
                result = subprocess.run([EXECUTABLE, path], capture_output=True, timeout=3)
                actual = result.returncode
            except subprocess.TimeoutExpired:
                actual = "timeout"
            if actual != expected:
                tm, longest, gc_ok = _properties(seq)
                failures.append(f"case {index}: expected {expected}, got {actual}, Tm={tm}, maxrun={longest}, GC_ok={gc_ok}")

    assert not failures, "Classifier failed derived unseen cases: " + "; ".join(failures[:10])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
