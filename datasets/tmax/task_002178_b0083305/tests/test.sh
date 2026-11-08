#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import os
from pathlib import Path
import secrets
import shutil
import string
import subprocess
import tempfile


def run_command(cmd, cwd=None, timeout=60):
    return subprocess.run(cmd, shell=True, cwd=cwd, capture_output=True, text=True, timeout=timeout)


def test_sanitizer_compiles_and_runs():
    project_dir = "/home/user/sanitizer"

    # Preserve the original project and compilation assertions.
    assert os.path.exists(project_dir), f"Sanitizer project directory not found at {project_dir}"
    assert os.path.exists(os.path.join(project_dir, "Cargo.toml")), "Cargo.toml not found in sanitizer project"

    build_result = run_command("cargo build --release", cwd=project_dir)
    assert build_result.returncode == 0, f"Compilation failed:\n{build_result.stderr}"

    binary_path = os.path.join(project_dir, "target", "release", "sanitizer")
    assert os.path.exists(binary_path), f"Compiled binary not found at {binary_path}"
    assert os.access(binary_path, os.X_OK), f"Compiled binary is not executable at {binary_path}"

    # Preserve the original visible-corpus checks.
    out_clean = "/tmp/out_clean"
    out_evil = "/tmp/out_evil"
    for path in (out_clean, out_evil):
        if os.path.exists(path):
            shutil.rmtree(path)
        os.makedirs(path, exist_ok=True)

    clean_corpus = "/app/verifier_corpus/clean"
    evil_corpus = "/app/verifier_corpus/evil"

    run_clean = run_command(f"{binary_path} --input {clean_corpus} --output {out_clean}")
    assert run_clean.returncode == 0, f"Sanitizer failed on clean corpus:\n{run_clean.stderr}"

    run_evil = run_command(f"{binary_path} --input {evil_corpus} --output {out_evil}")
    assert run_evil.returncode == 0, f"Sanitizer failed on evil corpus:\n{run_evil.stderr}"

    clean_original_files = []
    for root, _, files in os.walk(clean_corpus):
        for f in files:
            clean_original_files.append(os.path.relpath(os.path.join(root, f), clean_corpus))

    clean_copied_files = []
    for root, _, files in os.walk(out_clean):
        for f in files:
            clean_copied_files.append(os.path.relpath(os.path.join(root, f), out_clean))

    missing_clean = set(clean_original_files) - set(clean_copied_files)
    modified_clean = []
    for f in set(clean_original_files).intersection(clean_copied_files):
        if not filecmp.cmp(os.path.join(clean_corpus, f), os.path.join(out_clean, f), shallow=False):
            modified_clean.append(f)

    assert not missing_clean, f"{len(missing_clean)} of {len(clean_original_files)} clean files were missing. Examples: {list(missing_clean)[:5]}"
    assert not modified_clean, f"{len(modified_clean)} of {len(clean_original_files)} clean files were modified. Examples: {modified_clean[:5]}"

    evil_copied_files = []
    for root, _, files in os.walk(out_evil):
        for f in files:
            evil_copied_files.append(os.path.relpath(os.path.join(root, f), out_evil))

    evil_original_files = []
    for root, _, files in os.walk(evil_corpus):
        for f in files:
            evil_original_files.append(os.path.relpath(os.path.join(root, f), evil_corpus))

    assert not evil_copied_files, f"{len(evil_copied_files)} of {len(evil_original_files)} evil files bypassed the filter. Examples: {evil_copied_files[:5]}"

    # Exercise a single, randomly named mixed corpus so behavior cannot depend on
    # input paths named 'clean' and 'evil' or on the visible filenames.
    def parser_would_overflow(data):
        in_sig = False
        sig = b""
        for line in data.splitlines(keepends=True):
            if line.startswith(b"Signature:"):
                in_sig = True
                sig += line[10:]
            elif in_sig and line[:1] in (b" ", b"\t"):
                sig += line
            else:
                if in_sig and len(sig) > 63:
                    return True
                if in_sig:
                    in_sig = False
        return in_sig and len(sig) > 63

    alphabet = string.ascii_letters + string.digits
    token = lambda n: ''.join(secrets.choice(alphabet) for _ in range(n))

    with tempfile.TemporaryDirectory(prefix="sanitizer-check-") as base:
        input_dir = Path(base) / ("incoming_" + secrets.token_hex(8))
        output_dir = Path(base) / ("result_" + secrets.token_hex(8))
        input_dir.mkdir()
        output_dir.mkdir()

        documents = []
        # Short signatures, folded short signatures, and no signature.
        documents.append(f"Author: {token(9)}\nDate: 2026-01-01\nBody:\n{token(180)}\n".encode())
        documents.append(f"Author: {token(8)}\nSignature: {token(18)}\nBody:\n{token(90)}\n".encode())
        documents.append(f"Author: {token(8)}\nSignature: {token(9)}\n {token(12)}\nRevision-History: initial\nBody:\n{token(70)}\n".encode())
        documents.append(f"Signature: {token(25)}\n\t{token(15)}\nBody:\n{token(60)}\n".encode())

        # Oversized signatures in both direct and folded forms.
        documents.append(f"Author: {token(8)}\nSignature: {token(130)}\nBody:\n{token(40)}\n".encode())
        documents.append(f"Date: 2026-02-02\nSignature: {token(12)}\n {token(105)}\nBody:\n{token(50)}\n".encode())
        documents.append(f"Signature: {token(20)}\n\t{token(30)}\n {token(80)}\nRevision-History: x\nBody:\n{token(50)}\n".encode())

        # Also include renamed copies of every supplied sample in the same mixed tree.
        for corpus in (Path(clean_corpus), Path(evil_corpus)):
            for source in corpus.rglob("*.doclog"):
                documents.append(source.read_bytes())

        expected_safe = {}
        expected_rejected = set()
        for index, data in enumerate(documents):
            rel = Path("level_" + token(7)) / ("branch_" + token(7)) / (token(12) + ".doclog")
            destination = input_dir / rel
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
            if parser_would_overflow(data):
                expected_rejected.add(rel.as_posix())
            else:
                expected_safe[rel.as_posix()] = data

        assert expected_safe and expected_rejected

        result = subprocess.run(
            [binary_path, "--input", str(input_dir), "--output", str(output_dir)],
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert result.returncode == 0, f"Sanitizer failed on mixed corpus:\n{result.stderr}"

        actual_files = {
            p.relative_to(output_dir).as_posix()
            for p in output_dir.rglob("*")
            if p.is_file()
        }
        assert actual_files == set(expected_safe), (
            f"Mixed-corpus output mismatch. Missing safe files: "
            f"{sorted(set(expected_safe) - actual_files)[:5]}; unexpected/rejected files: "
            f"{sorted(actual_files - set(expected_safe))[:5]}"
        )
        for rel, original_data in expected_safe.items():
            assert (output_dir / rel).read_bytes() == original_data, f"Safe file was modified: {rel}"
        for rel in expected_rejected:
            assert not (output_dir / rel).exists(), f"Crash-inducing file was copied: {rel}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
