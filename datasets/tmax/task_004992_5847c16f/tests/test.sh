#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import glob
import os
import subprocess
import tempfile
import time
import uuid

import pytest

SCRIPT_PATH = "/home/user/filter_primers.py"


def read_fasta(file_path):
    """Simple FASTA parser returning a list of (header, sequence) tuples."""
    sequences = []
    if not os.path.exists(file_path):
        return sequences

    with open(file_path, "r") as f:
        header = None
        seq = []
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith(">"):
                if header is not None:
                    sequences.append((header, "".join(seq)))
                header = line
                seq = []
            else:
                seq.append(line)
        if header is not None:
            sequences.append((header, "".join(seq)))
    return sequences


def test_filter_script_exists():
    assert os.path.isfile(SCRIPT_PATH), "The script /home/user/filter_primers.py does not exist."


def test_parallel_library_is_used():
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=SCRIPT_PATH)

    imported = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.update(alias.name.split(".")[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported.add(node.module.split(".")[0])

    assert "multiprocessing" in imported or "mpi4py" in imported, (
        "The filter must use Python multiprocessing or mpi4py."
    )


def test_adversarial_corpus():
    clean_in = "/home/user/corpus/clean"
    evil_in = "/home/user/corpus/evil"
    clean_out = "/tmp/out_clean"
    evil_out = "/tmp/out_evil"

    for path in (clean_out, evil_out):
        if os.path.exists(path):
            import shutil
            shutil.rmtree(path)
        os.makedirs(path)

    result_clean = subprocess.run(
        ["python3", SCRIPT_PATH, clean_in, clean_out],
        capture_output=True, text=True
    )
    assert result_clean.returncode == 0, f"Script failed on clean corpus:\n{result_clean.stderr}"

    result_evil = subprocess.run(
        ["python3", SCRIPT_PATH, evil_in, evil_out],
        capture_output=True, text=True
    )
    assert result_evil.returncode == 0, f"Script failed on evil corpus:\n{result_evil.stderr}"

    clean_files = glob.glob(os.path.join(clean_in, "*.fasta"))
    assert len(clean_files) > 0, "No clean corpus files found to test."

    clean_modified = []
    for cf in clean_files:
        basename = os.path.basename(cf)
        if read_fasta(cf) != read_fasta(os.path.join(clean_out, basename)):
            clean_modified.append(basename)

    evil_files = glob.glob(os.path.join(evil_in, "*.fasta"))
    assert len(evil_files) > 0, "No evil corpus files found to test."

    evil_bypassed = []
    for ef in evil_files:
        basename = os.path.basename(ef)
        if read_fasta(os.path.join(evil_out, basename)):
            evil_bypassed.append(basename)

    errors = []
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if errors:
        pytest.fail(" | ".join(errors))


def stability_cutoff():
    alpha = 5.2
    beta = 8.5

    def equation(x):
        import math
        return x**3 - alpha * x**2 + beta * math.log(x) - 10

    lo, hi = 1.0, 2.0
    while equation(hi) <= 0:
        hi *= 2
    for _ in range(100):
        mid = (lo + hi) / 2
        if equation(mid) <= 0:
            lo = mid
        else:
            hi = mid
    return int(((lo + hi) / 2) * 10 // 1)


def descendants_of(parent_pid):
    descendants = set()
    frontier = {parent_pid}
    while frontier:
        new_frontier = set()
        for entry in os.listdir("/proc"):
            if not entry.isdigit():
                continue
            pid = int(entry)
            if pid in descendants or pid == parent_pid:
                continue
            try:
                with open(f"/proc/{pid}/status", "r") as f:
                    ppid = None
                    for line in f:
                        if line.startswith("PPid:"):
                            ppid = int(line.split()[1])
                            break
                if ppid in frontier:
                    descendants.add(pid)
                    new_frontier.add(pid)
            except (FileNotFoundError, ProcessLookupError, PermissionError, ValueError):
                pass
        frontier = new_frontier
    return descendants


def write_fasta(path, records, width):
    with open(path, "w") as f:
        for header, sequence in records:
            f.write(header + "\n")
            for start in range(0, len(sequence), width):
                f.write(sequence[start:start + width] + "\n")


def test_randomized_mixed_corpus_and_runtime_parallelism():
    cutoff = stability_cutoff()
    assert 1 <= cutoff < 100

    token = uuid.uuid4().hex
    base = tempfile.mkdtemp(prefix=f"primer_case_{token}_")
    input_dir = os.path.join(base, f"incoming_{token}")
    output_dir = os.path.join(base, f"results_{token}")
    os.makedirs(input_dir)

    expected = {}
    for index in range(12):
        filename = f"batch_{uuid.uuid4().hex}_{index}.fasta"
        path = os.path.join(input_dir, filename)

        at_boundary = ("G" * cutoff + "A" * (100 - cutoff)) * 3000
        above_boundary = ("C" * (cutoff + 1) + "T" * (99 - cutoff)) * 3000
        if index % 2:
            at_boundary = at_boundary.lower()
            above_boundary = above_boundary.lower()

        records = [
            (f">zero_gc_{token}_{index}", "ATATATATAT"),
            (f">boundary_{token}_{index}", at_boundary),
            (f">above_{token}_{index}", above_boundary),
            (f">all_gc_{token}_{index}", "GCGCGCGCGC"),
        ]
        write_fasta(path, records, 61 + (index % 7))

        kept = []
        for header, sequence in records:
            gc = sum(base in "GC" for base in sequence.upper()) / len(sequence) * 100
            if gc <= cutoff:
                kept.append((header, sequence))
        expected[filename] = kept

    proc = subprocess.Popen(
        ["python3", SCRIPT_PATH, input_dir, output_dir],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    observed_children = set()
    deadline = time.monotonic() + 30
    while proc.poll() is None and time.monotonic() < deadline:
        observed_children.update(descendants_of(proc.pid))
        time.sleep(0.0005)

    if proc.poll() is None:
        proc.kill()
        stdout, stderr = proc.communicate()
        pytest.fail(f"Script timed out on randomized corpus.\nstdout:\n{stdout}\nstderr:\n{stderr}")

    stdout, stderr = proc.communicate()
    assert proc.returncode == 0, (
        f"Script failed on randomized corpus.\nstdout:\n{stdout}\nstderr:\n{stderr}"
    )
    assert observed_children, (
        "No worker process was observed while processing multiple FASTA files; "
        "the files must be processed in parallel."
    )

    assert os.path.isdir(output_dir), "The script did not create the output directory."
    for filename, wanted in expected.items():
        output_file = os.path.join(output_dir, filename)
        assert os.path.isfile(output_file), f"Missing output FASTA file: {filename}"
        actual = read_fasta(output_file)
        assert actual == wanted, f"Incorrect filtering for randomized file {filename}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
