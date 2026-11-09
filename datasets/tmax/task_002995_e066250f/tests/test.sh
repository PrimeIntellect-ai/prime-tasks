#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import pytest

SCRIPT_PATH = "/home/user/sanitizer.py"


def test_sanitizer_exists():
    assert os.path.exists(SCRIPT_PATH), f"Sanitizer script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Path {SCRIPT_PATH} is not a file"


def run_sanitizer(input_content):
    return subprocess.run(
        ["python3", SCRIPT_PATH],
        input=input_content,
        text=True,
        capture_output=True,
        timeout=5,
    )


def test_clean_corpus():
    clean_dirs = ["/home/user/corpus/clean", "/app/test_corpus/clean"]
    failed_files = []
    total_files = 0

    for clean_dir in clean_dirs:
        if not os.path.exists(clean_dir):
            continue
        for filename in os.listdir(clean_dir):
            if not filename.endswith(".sql"):
                continue
            filepath = os.path.join(clean_dir, filename)
            total_files += 1
            with open(filepath, "r") as f:
                content = f.read()

            result = run_sanitizer(content)

            if result.returncode != 0 or result.stdout.strip() != content.strip():
                failed_files.append(filepath)

    assert total_files > 0, "No clean corpus files found to test."
    if failed_files:
        pytest.fail(f"{len(failed_files)} of {total_files} clean files modified or rejected. Offending files: {', '.join(os.path.basename(f) for f in failed_files)}")


def test_evil_corpus():
    evil_dirs = ["/home/user/corpus/evil", "/app/test_corpus/evil"]
    failed_files = []
    total_files = 0

    for evil_dir in evil_dirs:
        if not os.path.exists(evil_dir):
            continue
        for filename in os.listdir(evil_dir):
            if not filename.endswith(".sql"):
                continue
            filepath = os.path.join(evil_dir, filename)
            total_files += 1
            with open(filepath, "r") as f:
                content = f.read()

            result = run_sanitizer(content)

            if result.returncode != 1 or result.stdout.strip() != "REJECTED":
                failed_files.append(filepath)

    assert total_files > 0, "No evil corpus files found to test."
    if failed_files:
        pytest.fail(f"{len(failed_files)} of {total_files} evil files bypassed. Offending files: {', '.join(os.path.basename(f) for f in failed_files)}")


def mixed_case(word):
    return "".join(ch.upper() if secrets.randbelow(2) else ch.lower() for ch in word)


def generated_queries():
    clean = []
    evil = []
    for i in range(48):
        tag = "g" + secrets.token_hex(10)
        value = secrets.randbelow(1000000)

        clean_templates = [
            f"SELECT * FROM edge_list AS {tag} WHERE {tag}.source = {value};\n",
            f"SELECT a.source, b.target FROM edge_list a JOIN edge_list b ON a.target = b.source WHERE a.source = {value};\n",
            f"WITH path AS (SELECT source, target FROM edge_list WHERE source = {value}) SELECT p.source, e.target FROM path p JOIN edge_list e ON p.target = e.source;\n",
            f"SELECT * FROM (SELECT source, target FROM edge_list WHERE target = {value}) AS {tag};\n",
            f"SELECT * FROM edge_list NOT INDEXED WHERE source = {value};\n",
            f"SELECT 'edge_list INDEXED BY corrupted_type_idx' AS note, source FROM edge_list WHERE source = {value};\n",
            f"SELECT source FROM edge_list /* INDEXED BY corrupted_type_idx {tag} */ WHERE target = {value};\n",
            f"-- INDEXED BY corrupted_type_idx is documentation only: {tag}\nSELECT source, target FROM edge_list WHERE source = {value};\n",
        ]
        clean.append(clean_templates[i % len(clean_templates)])

        indexed = mixed_case("indexed")
        by = mixed_case("by")
        idx_forms = [
            "corrupted_type_idx",
            '"corrupted_type_idx"',
            "[corrupted_type_idx]",
            "`corrupted_type_idx`",
        ]
        idx = idx_forms[i % len(idx_forms)]
        separator = [" ", "\n", f" /*{tag}*/ ", "\t"][i % 4]
        evil_templates = [
            f"SELECT * FROM edge_list {indexed}{separator}{by} {idx} WHERE source = {value};\n",
            f"SELECT a.source, b.target FROM edge_list AS a {indexed}{separator}{by} {idx} JOIN edge_list AS b ON a.target = b.source WHERE a.source = {value};\n",
            f"WITH bad AS (SELECT source, target FROM edge_list {indexed}{separator}{by} {idx} WHERE source = {value}) SELECT * FROM bad;\n",
            f"SELECT * FROM (SELECT source, target FROM edge_list {indexed}{separator}{by} {idx} WHERE target = {value}) AS {tag};\n",
            f"SELECT e.source FROM edge_list e WHERE EXISTS (SELECT 1 FROM edge_list x {indexed}{separator}{by} {idx} WHERE x.source = e.target AND x.target = {value});\n",
            f"SELECT a.source FROM edge_list a JOIN (SELECT source FROM edge_list {indexed}{separator}{by} {idx}) AS {tag} ON a.target = {tag}.source;\n",
        ]
        evil.append(evil_templates[i % len(evil_templates)])
    return clean, evil


def test_generated_hidden_queries():
    clean, evil = generated_queries()

    for query in clean:
        result = run_sanitizer(query)
        assert result.returncode == 0, f"Generated clean query was rejected: {query!r}"
        assert result.stdout.strip() == query.strip(), f"Generated clean query was modified: {query!r}"

    for query in evil:
        result = run_sanitizer(query)
        assert result.returncode == 1, f"Generated evil query was not rejected: {query!r}"
        assert result.stdout.strip() == "REJECTED", f"Generated evil query produced incorrect output: {query!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
