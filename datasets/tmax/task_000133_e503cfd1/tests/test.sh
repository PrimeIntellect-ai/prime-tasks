#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'GO_EOF' > /tmp/inspect_go_source.go
package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
)

func main() {
    if len(os.Args) != 2 {
        os.Exit(2)
    }
    f, err := parser.ParseFile(token.NewFileSet(), os.Args[1], nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }
    if f.Name.Name != "main" {
        fmt.Fprintln(os.Stderr, "classifier.go must declare package main")
        os.Exit(1)
    }
    hasMain := false
    hasGoStmt := false
    ast.Inspect(f, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.FuncDecl:
            if x.Name.Name == "main" {
                hasMain = true
            }
        case *ast.GoStmt:
            hasGoStmt = true
        }
        return true
    })
    if !hasMain {
        fmt.Fprintln(os.Stderr, "classifier.go has no main function")
        os.Exit(1)
    }
    if !hasGoStmt {
        fmt.Fprintln(os.Stderr, "classifier.go does not use a goroutine")
        os.Exit(1)
    }
}
GO_EOF

cat <<'PY_EOF' > /tmp/test_final_state.py
import math
import os
import random
import secrets
import shutil
import struct
import subprocess
import tempfile
import wave
from pathlib import Path

SOURCE = Path("/home/user/classifier.go")
EXECUTABLE = Path("/home/user/classifier")
AUDIO = Path("/app/audio/target.wav")
CLEAN_DIR = Path("/app/corpus/clean")
EVIL_DIR = Path("/app/corpus/evil")
DNA = "ACGT"


def decode_audio(path):
    with wave.open(str(path), "rb") as wav:
        assert wav.getsampwidth() == 2, "target.wav must contain 16-bit PCM audio"
        rate = wav.getframerate()
        channels = wav.getnchannels()
        raw = wav.readframes(wav.getnframes())
    values = struct.unpack("<%dh" % (len(raw) // 2), raw)
    samples = values[::channels]
    block = max(1, rate // 100)  # 10 ms RMS envelope
    states = []
    for start in range(0, len(samples), block):
        chunk = samples[start:start + block]
        rms = math.sqrt(sum(v * v for v in chunk) / len(chunk))
        states.append(rms > 1000)
    runs = []
    for state in states:
        if runs and runs[-1][0] == state:
            runs[-1][1] += 1
        else:
            runs.append([state, 1])

    inverse = {".-": "A", "-.-.": "C", "--.": "G", "-": "T"}
    sequence = []
    code = ""
    for active, blocks in runs:
        duration = blocks * block / rate
        if active:
            code += "." if duration < 0.20 else "-"
        elif duration >= 0.20 and code:
            assert code in inverse, f"Unknown Morse character {code!r} in target.wav"
            sequence.append(inverse[code])
            code = ""
    if code:
        assert code in inverse, f"Unknown final Morse character {code!r} in target.wav"
        sequence.append(inverse[code])
    result = "".join(sequence)
    assert result and set(result) <= set(DNA), "Audio did not decode to a DNA sequence"
    return result


def kl_divergence(primer, target):
    dimers = [a + b for a in DNA for b in DNA]
    pc = {d: 1 for d in dimers}
    tc = {d: 1 for d in dimers}
    for i in range(len(primer) - 1):
        pc[primer[i:i + 2]] += 1
    for i in range(len(target) - 1):
        tc[target[i:i + 2]] += 1
    ptotal = sum(pc.values())
    ttotal = sum(tc.values())
    return sum((pc[d] / ptotal) * math.log((pc[d] / ptotal) / (tc[d] / ttotal)) for d in dimers)


def should_copy(primer, target):
    if not primer or any(c not in DNA for c in primer):
        return False
    gc = 100.0 * sum(c in "GC" for c in primer) / len(primer)
    return primer in target and 40.0 <= gc <= 60.0 and kl_divergence(primer, target) < 0.5


def expected_for_directory(directory, target):
    result = set()
    for path in directory.iterdir():
        if path.is_file() and path.name.endswith(".txt"):
            primer = path.read_text()
            if should_copy(primer, target):
                result.add(path.name)
    return result


def run_and_check(executable, target, input_dir, expected):
    with tempfile.TemporaryDirectory() as output_name:
        output_dir = Path(output_name)
        result = subprocess.run(
            [str(executable), target, str(input_dir), str(output_dir)],
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"Classifier {executable} failed with status {result.returncode}:\n{result.stderr}"
        )
        actual = {p.name for p in output_dir.iterdir()}
        assert actual == expected, (
            f"Classifier {executable} produced {sorted(actual)}, expected {sorted(expected)}"
        )
        for name in expected:
            assert (output_dir / name).is_file(), f"Output {name} is not a regular file"
            assert (output_dir / name).read_bytes() == (input_dir / name).read_bytes(), (
                f"Output {name} was not copied byte-for-byte"
            )


def make_hidden_challenge(root):
    rng = random.SystemRandom()
    background = "".join(rng.choice(DNA) for _ in range(600))
    kl_reject = "AC" * 20
    gc_reject = "G" * 12
    target = background + ("AC" * 30) + ("G" * 20)

    assert kl_reject in target
    assert 40 <= 100 * sum(c in "GC" for c in kl_reject) / len(kl_reject) <= 60
    assert kl_divergence(kl_reject, target) >= 0.5
    assert gc_reject in target and not should_copy(gc_reject, target)

    passing = []
    for length in range(6, 19):
        for start in range(0, len(background) - length + 1):
            candidate = background[start:start + length]
            if should_copy(candidate, target):
                passing.append(candidate)
    assert len(set(passing)) >= 10, "Could not construct enough valid hidden primers"
    passing = rng.sample(list(set(passing)), 10)

    candidates = passing + [kl_reject, gc_reject]
    while len(candidates) < 40:
        length = rng.randint(5, 18)
        candidate = "".join(rng.choice(DNA) for _ in range(length))
        if candidate not in target:
            candidates.append(candidate)

    expected = set()
    for index, primer in enumerate(candidates):
        name = f"{secrets.token_hex(8)}_{index}.txt"
        (root / name).write_text(primer)
        if should_copy(primer, target):
            expected.add(name)
    (root / f"ignored_{secrets.token_hex(8)}.dat").write_text(passing[0])
    assert expected and len(expected) < len(candidates)
    return target, expected


def test_classifier_artifacts_and_behavior():
    assert SOURCE.is_file(), f"Go source not found at {SOURCE}"
    assert EXECUTABLE.is_file(), f"Executable not found at {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not executable"
    assert EXECUTABLE.read_bytes()[:4] == b"\x7fELF", "classifier is not a compiled executable"

    inspection = subprocess.run(
        ["go", "run", "/tmp/inspect_go_source.go", str(SOURCE)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert inspection.returncode == 0, f"Invalid Go source or goroutine use:\n{inspection.stderr}"

    target = decode_audio(AUDIO)
    assert CLEAN_DIR.is_dir(), f"Clean corpus dir missing: {CLEAN_DIR}"
    assert EVIL_DIR.is_dir(), f"Evil corpus dir missing: {EVIL_DIR}"
    clean_files = {p.name for p in CLEAN_DIR.iterdir() if p.is_file() and p.name.endswith(".txt")}
    evil_files = {p.name for p in EVIL_DIR.iterdir() if p.is_file() and p.name.endswith(".txt")}
    assert clean_files, "No .txt files found in clean corpus"
    assert evil_files, "No .txt files found in evil corpus"

    expected_clean = expected_for_directory(CLEAN_DIR, target)
    expected_evil = expected_for_directory(EVIL_DIR, target)
    assert expected_clean == clean_files, "The supplied clean corpus is not semantically clean"
    assert expected_evil != evil_files, "The supplied evil corpus contains no rejecting case"

    with tempfile.TemporaryDirectory() as build_name:
        rebuilt = Path(build_name) / "classifier"
        build = subprocess.run(
            ["go", "build", "-o", str(rebuilt), str(SOURCE)],
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert build.returncode == 0, f"classifier.go does not compile:\n{build.stderr}"

        with tempfile.TemporaryDirectory() as challenge_name:
            challenge_dir = Path(challenge_name)
            hidden_target, hidden_expected = make_hidden_challenge(challenge_dir)
            for executable in (EXECUTABLE, rebuilt):
                run_and_check(executable, target, CLEAN_DIR, expected_clean)
                run_and_check(executable, target, EVIL_DIR, expected_evil)
                run_and_check(executable, hidden_target, challenge_dir, hidden_expected)
PY_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
