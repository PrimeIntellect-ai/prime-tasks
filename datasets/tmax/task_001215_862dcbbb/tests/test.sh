#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import os
import secrets
import shutil
import subprocess

BASE = '/home/user/docs_system'


def rle_encode(s):
    if not s:
        return ""
    encoded = []
    count = 1
    for i in range(1, len(s)):
        if s[i] == s[i-1]:
            count += 1
        else:
            encoded.append(f"{count}{s[i-1]}")
            count = 1
    encoded.append(f"{count}{s[-1]}")
    return "".join(encoded)


def test_drafts_modified():
    drafts_dir = '/home/user/docs_system/drafts'

    expected_docA = "Title: Doc A\nStatus: Draft\nContents containing [REDACTED] data.\nMore text here.\n"
    expected_docB = "Title: Doc B\nStatus: Review\nThis one has no secrets.\n"
    expected_docC = "Title: Doc C\nStatus: Draft\nAnother [REDACTED] mission.\n[REDACTED] is everywhere.\n"

    with open(os.path.join(drafts_dir, 'docA.md'), 'r') as f:
        assert f.read() == expected_docA, "docA.md was not correctly modified."

    with open(os.path.join(drafts_dir, 'docB.md'), 'r') as f:
        assert f.read() == expected_docB, "docB.md should not have been modified."

    with open(os.path.join(drafts_dir, 'docC.md'), 'r') as f:
        assert f.read() == expected_docC, "docC.md was not correctly modified."


def test_merged_drafts():
    merged_path = '/home/user/docs_system/merged_drafts.md'
    assert os.path.isfile(merged_path), "merged_drafts.md does not exist."

    expected_docA = "Title: Doc A\nStatus: Draft\nContents containing [REDACTED] data.\nMore text here.\n"
    expected_docC = "Title: Doc C\nStatus: Draft\nAnother [REDACTED] mission.\n[REDACTED] is everywhere.\n"
    expected_merged = expected_docA + expected_docC

    with open(merged_path, 'r') as f:
        assert f.read() == expected_merged, "merged_drafts.md does not contain the correct concatenated content."


def test_cpp_program_exists():
    assert os.path.isfile('/home/user/docs_system/processor.cpp'), "processor.cpp does not exist."
    assert os.path.isfile('/home/user/docs_system/processor'), "Compiled processor executable does not exist."
    assert os.access('/home/user/docs_system/processor', os.X_OK), "Compiled processor is not executable."


def test_chunks_and_rle():
    chunks_dir = '/home/user/docs_system/chunks'
    assert os.path.isdir(chunks_dir), "chunks/ directory does not exist."

    expected_texts = [
        "Chapter 1\nHellooo\n",
        "Chapter 2\nSpacesss   !\n",
        "Chapter 3\nAABBCC\n"
    ]

    for i, text in enumerate(expected_texts, 1):
        chunk_path = os.path.join(chunks_dir, f'chunk_{i}.rle')
        assert os.path.isfile(chunk_path), f"chunk_{i}.rle does not exist."

        expected_rle = rle_encode(text)
        with open(chunk_path, 'r') as f:
            assert f.read() == expected_rle, f"chunk_{i}.rle does not have the correct RLE encoded content."


def test_manifest():
    manifest_path = '/home/user/docs_system/manifest.txt'
    assert os.path.isfile(manifest_path), "manifest.txt does not exist."

    chunks_dir = '/home/user/docs_system/chunks'
    expected_lines = []

    for i in range(1, 4):
        chunk_filename = f'chunk_{i}.rle'
        chunk_path = os.path.join(chunks_dir, chunk_filename)
        if os.path.isfile(chunk_path):
            with open(chunk_path, 'rb') as f:
                sha1 = hashlib.sha1(f.read()).hexdigest()
            expected_lines.append(f"{sha1}  {chunk_filename}")

    expected_lines.sort()

    with open(manifest_path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, "manifest.txt does not match the expected sorted sha1sums."


def run_dynamic_case(binary, chunks):
    monolith = '---SPLIT---\n'.join(chunks)
    with open(os.path.join(BASE, 'monolith.md'), 'w', newline='') as f:
        f.write(monolith)

    chunks_dir = os.path.join(BASE, 'chunks')
    shutil.rmtree(chunks_dir, ignore_errors=True)

    result = subprocess.run(
        [binary], cwd=BASE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=10, text=True
    )
    assert result.returncode == 0, (
        f"{binary} failed on a generated input: {result.stderr}"
    )
    assert os.path.isdir(chunks_dir), "processor did not create chunks/"

    expected_names = [f'chunk_{i}.rle' for i in range(1, len(chunks) + 1)]
    actual_names = sorted(os.path.basename(p) for p in glob.glob(os.path.join(chunks_dir, '*.rle')))
    assert actual_names == sorted(expected_names), "processor generated the wrong set of chunk files"

    for i, text in enumerate(chunks, 1):
        path = os.path.join(chunks_dir, f'chunk_{i}.rle')
        with open(path, 'r', newline='') as f:
            actual = f.read()
        assert actual == rle_encode(text), f"dynamic RLE output for chunk_{i}.rle is incorrect"


def test_processor_is_compiled_cpp_and_handles_generated_input():
    source = os.path.join(BASE, 'processor.cpp')
    submitted_binary = os.path.join(BASE, 'processor')

    with open(submitted_binary, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "processor is not a compiled native executable"

    rebuilt_binary = '/tmp/processor_from_submitted_source'
    result = subprocess.run(
        ['g++', '-std=c++17', '-O2', source, '-o', rebuilt_binary],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30, text=True
    )
    assert result.returncode == 0, f"processor.cpp does not compile: {result.stderr}"

    token = secrets.token_hex(12)
    chunks = [
        f"Generated {token}\nAAAAAAAAAAAA  tail\n",
        f"Near delimiter\n---SPLIT---x\n{token}!!!!!\n",
        f"Spaces      and digits 11111111111\n{token}\n",
        f"Final chunk\nZZZZZZZZZZZZZZ\n{token}\n",
    ]

    # Exercise both the submitted executable and a fresh build of processor.cpp,
    # so neither a dummy executable nor arbitrary/nonfunctional source can pass.
    run_dynamic_case(submitted_binary, chunks)
    run_dynamic_case(rebuilt_binary, chunks)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
