#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
import tempfile
import uuid
import pytest

DETECTOR_PATH = "/home/user/detector"
VIDEO_PATH = "/app/primer_synthesis.mp4"
EVIL_DIR = "/app/evil"
CLEAN_DIR = "/app/clean"


def decode_primer():
    result = subprocess.run([
        "ffmpeg", "-v", "error", "-i", VIDEO_PATH,
        "-vf", "fps=1,scale=1:1", "-frames:v", "20",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-"
    ], capture_output=True, timeout=30)
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    assert len(result.stdout) == 20 * 3, f"Expected 20 decoded frames, got {len(result.stdout) // 3}"

    colors = {
        "A": (255, 0, 0),
        "C": (0, 255, 0),
        "G": (0, 0, 255),
        "T": (255, 255, 0),
    }
    primer = []
    for i in range(20):
        pixel = tuple(result.stdout[i * 3:i * 3 + 3])
        base, distance = min(
            ((base, sum((pixel[j] - rgb[j]) ** 2 for j in range(3)))
             for base, rgb in colors.items()),
            key=lambda item: item[1],
        )
        assert distance < 5000, f"Frame {i} is not close to a defined nucleotide color: {pixel}"
        primer.append(base)
    return "".join(primer)


PRIMER = decode_primer()


def expected_code(sequence):
    for start in range(max(0, len(sequence) - len(PRIMER) + 1)):
        mismatches = sum(a != b for a, b in zip(sequence[start:start + len(PRIMER)], PRIMER))
        if mismatches <= 3:
            return 1
    return 0


def run_detector(executable, path):
    try:
        return subprocess.run([executable, path], capture_output=True, timeout=20).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Detector timed out on {path}")


def has_openmp_runtime(path):
    checks = [
        ["readelf", "-Ws", path],
        ["nm", "-a", path],
        ["ldd", path],
    ]
    output = b""
    for command in checks:
        result = subprocess.run(command, capture_output=True)
        output += result.stdout + result.stderr
    return b"GOMP_parallel" in output or b"libgomp" in output


def make_generated_cases():
    rng = random.Random(0x51A7C0DE)
    alphabet = "ACGT"
    cases = []

    def mutate(count):
        chars = list(PRIMER)
        for pos in rng.sample(range(20), count):
            choices = [base for base in alphabet if base != chars[pos]]
            chars[pos] = rng.choice(choices)
        return "".join(chars)

    cases.extend([
        PRIMER,
        mutate(1),
        mutate(2),
        mutate(3),
        mutate(4),
        PRIMER[:19],
        "A" * 7,
    ])

    for mismatch_count, position, length in [
        (0, 0, 300),
        (1, 137, 500),
        (2, 479, 500),
        (3, 50000, 120000),
    ]:
        background = [rng.choice(alphabet) for _ in range(length)]
        motif = mutate(mismatch_count)
        background[position:position + 20] = motif
        cases.append("".join(background))

    # Rejection sampling makes these genuinely clean instead of trusting a label.
    for length in (20, 21, 73, 1000, 250000):
        while True:
            sequence = "".join(rng.choice(alphabet) for _ in range(length))
            if expected_code(sequence) == 0:
                cases.append(sequence)
                break

    directory = tempfile.mkdtemp(prefix="seqcheck_" + uuid.uuid4().hex + "_")
    materialized = []
    for sequence in cases:
        path = os.path.join(directory, uuid.uuid4().hex + ".dat")
        with open(path, "w", encoding="ascii") as handle:
            handle.write(sequence + "\n")
        materialized.append((path, expected_code(sequence)))
    assert any(code == 0 for _, code in materialized)
    assert any(code == 1 for _, code in materialized)
    return materialized


GENERATED_CASES = make_generated_cases()


def test_detector_exists():
    assert os.path.isfile(DETECTOR_PATH), f"Executable not found at {DETECTOR_PATH}"
    assert os.access(DETECTOR_PATH, os.X_OK), f"File at {DETECTOR_PATH} is not executable"
    file_result = subprocess.run(["file", DETECTOR_PATH], capture_output=True, text=True)
    assert file_result.returncode == 0 and "ELF" in file_result.stdout, "Detector must be a compiled native program"
    assert has_openmp_runtime(DETECTOR_PATH), "Detector is not linked to or using the OpenMP runtime"


def test_c_source_uses_openmp_and_implements_detector():
    candidates = []
    for root in ("/home/user", "/app", "/tmp"):
        for directory, _, files in os.walk(root):
            for filename in files:
                if filename.endswith(".c"):
                    candidates.append(os.path.join(directory, filename))

    pragma = re.compile(r"#\s*pragma\s+omp\s+parallel\s+for\b")
    failures = []
    for source in candidates:
        try:
            with open(source, "r", encoding="utf-8", errors="ignore") as handle:
                text = handle.read()
        except OSError:
            continue
        if not pragma.search(text):
            continue

        output = os.path.join(tempfile.mkdtemp(prefix="cbuild_"), "detector")
        build = subprocess.run(
            ["gcc", "-O2", "-fopenmp", source, "-o", output],
            capture_output=True, text=True, timeout=30,
        )
        if build.returncode != 0:
            failures.append(f"{source}: compilation failed")
            continue
        if not has_openmp_runtime(output):
            failures.append(f"{source}: pragma did not produce OpenMP code")
            continue
        wrong = [(path, expected, run_detector(output, path))
                 for path, expected in GENERATED_CASES
                 if run_detector(output, path) != expected]
        if not wrong:
            return
        failures.append(f"{source}: failed generated behavioral cases")

    pytest.fail("No compilable C source with '#pragma omp parallel for' implements the detector. " + "; ".join(failures[:5]))


def test_evil_corpus():
    evil_files = [f for f in os.listdir(EVIL_DIR) if f.endswith('.txt')]
    assert len(evil_files) > 0, f"No text files found in {EVIL_DIR}"

    bypassed = []
    for filename in evil_files:
        filepath = os.path.join(EVIL_DIR, filename)
        if run_detector(DETECTOR_PATH, filepath) != 1:
            bypassed.append(filename)

    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil bypassed (expected exit code 1). Offending files: {', '.join(bypassed[:10])}")


def test_clean_corpus():
    clean_files = [f for f in os.listdir(CLEAN_DIR) if f.endswith('.txt')]
    assert len(clean_files) > 0, f"No text files found in {CLEAN_DIR}"

    wrong = []
    for filename in clean_files:
        filepath = os.path.join(CLEAN_DIR, filename)
        with open(filepath, "r", encoding="ascii") as handle:
            sequence = handle.read().strip()
        expected = expected_code(sequence)
        actual = run_detector(DETECTOR_PATH, filepath)
        if actual != expected:
            wrong.append(filename)

    if wrong:
        pytest.fail(f"{len(wrong)} of {len(clean_files)} corpus files were misclassified. Offending files: {', '.join(wrong[:10])}")


def test_newly_generated_unlabelled_inputs():
    wrong = []
    for path, expected in GENERATED_CASES:
        actual = run_detector(DETECTOR_PATH, path)
        if actual != expected:
            wrong.append((os.path.basename(path), expected, actual))
    assert not wrong, f"Generated inputs were misclassified: {wrong[:10]}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
