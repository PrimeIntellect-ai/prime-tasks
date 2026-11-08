#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import math
import os
import random
import re
import secrets
import subprocess

import numpy as np

HOME = "/home/user"
SCRIPT = os.path.join(HOME, "spectral_primer_score.py")
SCORE_FILE = os.path.join(HOME, "deterministic_score.txt")
OUTPUT_RE = re.compile(r"Total Score:\s*([0-9.eE+-]+)")


def independent_score(primer_path, fasta_path, spectra_path):
    with open(primer_path, "r") as f:
        primer = f.read().strip()

    records = []
    current_id = None
    current_seq = []
    with open(fasta_path, "r") as f:
        for raw_line in f:
            line = raw_line.strip()
            if line.startswith(">"):
                if current_id is not None:
                    records.append((current_id, "".join(current_seq)))
                current_id = line[1:]
                current_seq = []
            else:
                current_seq.append(line)
        if current_id is not None:
            records.append((current_id, "".join(current_seq)))

    with open(spectra_path, "r") as f:
        spectra = json.load(f)

    total = 0.0
    for seq_id, seq in records:
        align_score = seq.count(primer)
        if align_score == 0:
            align_score = sum(
                1 for i in range(len(seq) - 3) if seq[i:i + 3] in primer
            ) * 0.1
        fft_vals = np.fft.fft(spectra[seq_id])
        max_amp = np.max(np.abs(fft_vals))
        total += max_amp * align_score
    return float(total)


def run_script():
    result = subprocess.run(
        ["python3", SCRIPT], cwd=HOME, capture_output=True, text=True, timeout=60
    )
    assert result.returncode == 0, f"Script execution failed:\n{result.stderr}"
    match = OUTPUT_RE.search(result.stdout)
    assert match is not None, (
        "Could not find 'Total Score: <number>' in script output. "
        f"Output was:\n{result.stdout}"
    )
    return match.group(1)


def test_deterministic_score_file():
    assert os.path.isfile(SCORE_FILE), f"File {SCORE_FILE} does not exist."
    with open(SCORE_FILE, "r") as f:
        content = f.read().strip()
    try:
        float(content)
    except ValueError:
        assert False, f"Content of {SCORE_FILE} is not a valid float. Found: '{content}'"


def test_script_uses_pool():
    assert os.path.isfile(SCRIPT), f"File {SCRIPT} does not exist."
    with open(SCRIPT, "r") as f:
        content = f.read()
    assert "Pool" in content, "The script must preserve the use of multiprocessing.Pool."

    tree = ast.parse(content)
    direct_pool_names = set()
    multiprocessing_names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module == "multiprocessing":
            for alias in node.names:
                if alias.name == "Pool":
                    direct_pool_names.add(alias.asname or alias.name)
        elif isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "multiprocessing":
                    multiprocessing_names.add(alias.asname or alias.name)

    def is_pool_constructor(call):
        if not isinstance(call, ast.Call):
            return False
        func = call.func
        if isinstance(func, ast.Name):
            return func.id in direct_pool_names
        return (
            isinstance(func, ast.Attribute)
            and func.attr == "Pool"
            and isinstance(func.value, ast.Name)
            and func.value.id in multiprocessing_names
        )

    pool_vars = set()
    pool_constructed = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and is_pool_constructor(node):
            pool_constructed = True
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            value = node.value
            if is_pool_constructor(value):
                targets = node.targets if isinstance(node, ast.Assign) else [node.target]
                for target in targets:
                    if isinstance(target, ast.Name):
                        pool_vars.add(target.id)
        elif isinstance(node, ast.With):
            for item in node.items:
                if is_pool_constructor(item.context_expr) and isinstance(item.optional_vars, ast.Name):
                    pool_vars.add(item.optional_vars.id)

    dispatch_methods = {
        "map", "imap", "imap_unordered", "starmap", "map_async",
        "starmap_async", "apply", "apply_async"
    }
    dispatched = any(
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr in dispatch_methods
        and isinstance(node.func.value, ast.Name)
        and node.func.value.id in pool_vars
        for node in ast.walk(tree)
    )
    assert pool_constructed, "The script must actually construct multiprocessing.Pool."
    assert dispatched, "The script must submit sequence-processing work through the Pool."


def test_script_deterministic_output_and_correct_score():
    expected = independent_score(
        os.path.join(HOME, "target_primer.txt"),
        os.path.join(HOME, "database.fasta"),
        os.path.join(HOME, "spectra.json"),
    )

    outputs = []
    for i in range(5):
        outputs.append(run_script())

    assert len(set(outputs)) == 1, (
        f"Script output is not deterministic. Outputs over 5 runs: {outputs}"
    )

    with open(SCORE_FILE, "r") as f:
        saved_score = f.read().strip()
    assert float(saved_score) == float(outputs[0]), (
        f"Saved score '{saved_score}' in {SCORE_FILE} does not match "
        f"script output '{outputs[0]}'."
    )
    assert float(outputs[0]) == expected, (
        f"Script reported {outputs[0]}, but independently recomputed score is {expected}."
    )
    assert float(saved_score) == expected, (
        f"Saved score {saved_score} does not equal the independently recomputed score {expected}."
    )


def test_script_on_fresh_data():
    paths = {
        name: os.path.join(HOME, name)
        for name in ("target_primer.txt", "database.fasta", "spectra.json")
    }
    backups = {}
    for name, path in paths.items():
        with open(path, "rb") as f:
            backups[name] = f.read()

    rng = random.Random(secrets.randbits(128))
    primer = "GATTACA"
    spectra = {}
    fasta_lines = []
    bases = "ACGT"

    for i in range(1, 38):
        seq_id = f"verify_{i:03d}"
        seq = "".join(rng.choice(bases) for _ in range(43 + (i % 13)))
        if i % 9 == 0:
            pos = rng.randrange(0, len(seq) - len(primer) + 1)
            seq = seq[:pos] + primer + seq[pos + len(primer):]
        fasta_lines.extend([f">{seq_id}\n", f"{seq}\n"])

        freq = rng.uniform(1.0, 20.0)
        scale = 10.0 ** rng.randint(-4, 6)
        spectra[seq_id] = [
            (math.sin(2.0 * math.pi * freq * (t / 96.0)) + rng.uniform(-0.07, 0.07)) * scale
            for t in range(96)
        ]

    try:
        with open(paths["target_primer.txt"], "w") as f:
            f.write(primer + "\n")
        with open(paths["database.fasta"], "w") as f:
            f.writelines(fasta_lines)
        with open(paths["spectra.json"], "w") as f:
            json.dump(spectra, f)

        expected = independent_score(
            paths["target_primer.txt"], paths["database.fasta"], paths["spectra.json"]
        )
        outputs = [run_script() for _ in range(3)]
        assert len(set(outputs)) == 1, (
            f"Script is non-deterministic on fresh verification data: {outputs}"
        )
        assert float(outputs[0]) == expected, (
            f"On fresh verification data, script reported {outputs[0]}, "
            f"but independently recomputed score is {expected}."
        )
    finally:
        for name, data in backups.items():
            with open(paths[name], "wb") as f:
                f.write(data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
