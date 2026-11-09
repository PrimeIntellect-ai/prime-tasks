#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pytest

def test_final_docs_01():
    """Verify the contents of the first merged document."""
    file_path = "/home/user/final_docs/01_Introduction_To_System.md"
    assert os.path.isfile(file_path), f"Missing merged document: {file_path}"

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected_content = (
        "Welcome to the system.\n"
        "This is the first paragraph.\n"
        "This is the second part of the introduction."
    )

    assert content == expected_content, f"Content of {file_path} does not match expected output."

def test_final_docs_02():
    """Verify the contents of the second merged document."""
    file_path = "/home/user/final_docs/02_API_Reference.md"
    assert os.path.isfile(file_path), f"Missing merged document: {file_path}"

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected_content = (
        "The API has the following endpoints:\n"
        "- /v1/auth\n"
        "- /v1/data"
    )

    assert content == expected_content, f"Content of {file_path} does not match expected output."

def test_chapter_index_log():
    """Verify the chapter index log exists and contains correct mappings."""
    log_path = "/home/user/chapter_index.log"
    assert os.path.isfile(log_path), f"Missing log file: {log_path}"

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert "Chap_01:Introduction_To_System" in lines, f"Missing Chap_01 mapping in {log_path}"
    assert "Chap_02:API_Reference" in lines, f"Missing Chap_02 mapping in {log_path}"

def test_c_parser_exists():
    """Verify the C parser source and executable exist."""
    src_path = "/home/user/parser.c"
    bin_path = "/home/user/parser"

    assert os.path.isfile(src_path), f"Missing C source file: {src_path}"
    assert os.path.isfile(bin_path), f"Missing compiled executable: {bin_path}"
    assert os.access(bin_path, os.X_OK), f"Compiled parser is not executable: {bin_path}"

def test_scripts_exist():
    """Verify the Bash scripts exist."""
    step1 = "/home/user/step1_extract.sh"
    step3 = "/home/user/step3_build.sh"

    assert os.path.isfile(step1), f"Missing extraction script: {step1}"
    assert os.path.isfile(step3), f"Missing build script: {step3}"
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_pipeline.py
import gzip
import os
import secrets
import shutil
import subprocess
import tarfile
import tempfile
from pathlib import Path

HOME = Path("/home/user")

def run(cmd):
    subprocess.run(cmd, cwd=str(HOME), check=True, timeout=30)

def record(chap, part, text, title=None):
    lines = ["BEGIN_FRAGMENT", f"Chap: {chap}", f"Part: {part}"]
    if title is not None:
        lines.append(f"Title: {title}")
    lines.extend(["Text:", text, "END_FRAGMENT"])
    return "\n".join(lines) + "\n"

# Generate values after the agent has finished so fixed expected outputs cannot pass.
chap1 = f"{10 + secrets.randbelow(40):02d}"
chap2 = f"{50 + secrets.randbelow(40):02d}"
token = secrets.token_hex(12)
title1 = f"Dynamic_Guide_{token[:8]}"
title2 = f"Reference_{token[8:16]}"

bodies = {
    (chap1, "01"): f"Opening line {token}.\nSecond opening line.",
    (chap1, "02"): f"Compressed middle {token[::-1]}.",
    (chap1, "10"): "The tenth part must sort after part 02.",
    (chap2, "01"): f"Reference start {token[4:]}.",
    (chap2, "02"): "Reference continuation.\n- generated endpoint",
}
titles = {chap1: title1, chap2: title2}

with tempfile.TemporaryDirectory(prefix="verifier_docs_") as td:
    staging = Path(td) / "source"
    (staging / "outer" / "deep" / "deeper").mkdir(parents=True)
    (staging / "other").mkdir(parents=True)

    plain1 = (
        "unrelated preamble\n"
        + record(chap1, "10", bodies[(chap1, "10")])
        + "noise between records\n"
        + record(chap1, "01", bodies[(chap1, "01")], title1)
    )
    compressed = (
        record(chap2, "02", bodies[(chap2, "02")])
        + "ignored text\n"
        + record(chap1, "02", bodies[(chap1, "02")])
    )
    plain2 = record(chap2, "01", bodies[(chap2, "01")], title2)

    p1 = staging / "outer" / "first.txt"
    p2 = staging / "outer" / "deep" / "deeper" / "records.txt.gz"
    p3 = staging / "other" / "second.txt"
    p1.write_text(plain1)
    p2.write_bytes(gzip.compress(compressed.encode()))
    p3.write_text(plain2)

    archive = HOME / "legacy_docs.tar.gz"
    archive.unlink(missing_ok=True)
    with tarfile.open(archive, "w:gz") as tf:
        tf.add(staging, arcname=".")

    shutil.rmtree(HOME / "raw_docs", ignore_errors=True)
    shutil.rmtree(HOME / "chunks", ignore_errors=True)
    shutil.rmtree(HOME / "final_docs", ignore_errors=True)
    (HOME / "chapter_index.log").unlink(missing_ok=True)

    # Exercise the extraction script and verify nested plaintext and gzip members.
    run(["bash", str(HOME / "step1_extract.sh")])
    raw1 = HOME / "raw_docs" / "outer" / "first.txt"
    raw2 = HOME / "raw_docs" / "outer" / "deep" / "deeper" / "records.txt.gz"
    raw3 = HOME / "raw_docs" / "other" / "second.txt"
    assert raw1.is_file() and raw1.read_text() == plain1
    assert raw2.is_file()
    with gzip.open(raw2, "rt") as f:
        assert f.read() == compressed
    assert raw3.is_file() and raw3.read_text() == plain2

    expected_chunk_names = {f"frag_{c}_{p}.md" for c, p in bodies}
    expected_index = {f"Chap_{chap1}:{title1}", f"Chap_{chap2}:{title2}"}
    expected_final = {
        f"{chap1}_{title1}.md": "\n".join(
            [bodies[(chap1, "01")], bodies[(chap1, "02")], bodies[(chap1, "10")]]
        ),
        f"{chap2}_{title2}.md": "\n".join(
            [bodies[(chap2, "01")], bodies[(chap2, "02")]]
        ),
    }

    def verify_parser_outputs():
        chunks = HOME / "chunks"
        assert chunks.is_dir()
        actual_names = {p.name for p in chunks.glob("frag_*.md")}
        assert actual_names == expected_chunk_names
        for key, body in bodies.items():
            path = chunks / f"frag_{key[0]}_{key[1]}.md"
            assert path.read_text().strip() == body

        index = HOME / "chapter_index.log"
        assert index.is_file()
        lines = [line.strip() for line in index.read_text().splitlines() if line.strip()]
        assert len(lines) == len(expected_index)
        assert set(lines) == expected_index

    def verify_final_outputs():
        final_dir = HOME / "final_docs"
        assert final_dir.is_dir()
        actual_names = {p.name for p in final_dir.glob("*.md")}
        assert actual_names == set(expected_final)
        for name, expected in expected_final.items():
            assert (final_dir / name).read_text().strip() == expected

    # Exercise the submitted executable itself.
    run([str(HOME / "parser")])
    verify_parser_outputs()
    run(["bash", str(HOME / "step3_build.sh")])
    verify_final_outputs()

    # Also prove parser.c builds into a working parser rather than being a dummy source.
    rebuilt = Path(td) / "parser_rebuilt"
    run(["gcc", str(HOME / "parser.c"), "-o", str(rebuilt), "-lz"])
    shutil.rmtree(HOME / "chunks", ignore_errors=True)
    shutil.rmtree(HOME / "final_docs", ignore_errors=True)
    (HOME / "chapter_index.log").unlink(missing_ok=True)
    run([str(rebuilt)])
    verify_parser_outputs()
    run(["bash", str(HOME / "step3_build.sh")])
    verify_final_outputs()
DYNAMIC_EOF

passed=1
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || passed=0
python3 /tmp/test_dynamic_pipeline.py 2>&1 || passed=0

if [ "$passed" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
