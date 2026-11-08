#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import subprocess
import tempfile
import uuid
import pytest

VALIDATE_SCRIPT = "/home/user/validate_doc_tree.sh"
EVIL_CORPUS = "/home/user/corpora/evil"
CLEAN_CORPUS = "/home/user/corpora/clean"
PARSER_SCRIPT = "/app/vendored/doc_compiler_v2.1/bin/parser.sh"
MANIFEST_FILE = "/home/user/safe_docs_manifest.txt"
SYNC_LOG = "/home/user/sync_requests.log"


def run_validator(path):
    try:
        return subprocess.run(
            [VALIDATE_SCRIPT, path], capture_output=True, timeout=5
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Validator hung on dynamically generated tree: {path}")


def test_validate_doc_tree_exists():
    assert os.path.isfile(VALIDATE_SCRIPT), f"Missing script: {VALIDATE_SCRIPT}"
    assert os.access(VALIDATE_SCRIPT, os.X_OK), f"Script not executable: {VALIDATE_SCRIPT}"


def test_adversarial_corpus_validate_script():
    evil_dirs = sorted([os.path.join(EVIL_CORPUS, d) for d in os.listdir(EVIL_CORPUS) if os.path.isdir(os.path.join(EVIL_CORPUS, d))])
    clean_dirs = sorted([os.path.join(CLEAN_CORPUS, d) for d in os.listdir(CLEAN_CORPUS) if os.path.isdir(os.path.join(CLEAN_CORPUS, d))])

    evil_bypassed = []
    for edir in evil_dirs:
        try:
            result = subprocess.run([VALIDATE_SCRIPT, edir], capture_output=True, timeout=5)
            if result.returncode != 1:
                evil_bypassed.append(os.path.basename(edir))
        except subprocess.TimeoutExpired:
            evil_bypassed.append(f"{os.path.basename(edir)} (timeout)")

    clean_modified = []
    for cdir in clean_dirs:
        try:
            result = subprocess.run([VALIDATE_SCRIPT, cdir], capture_output=True, timeout=5)
            if result.returncode != 0:
                clean_modified.append(os.path.basename(cdir))
        except subprocess.TimeoutExpired:
            clean_modified.append(f"{os.path.basename(cdir)} (timeout)")

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_dirs)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {len(clean_dirs)} clean modified/rejected: {', '.join(clean_modified)}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_validator_on_fresh_unpredictable_topologies():
    with tempfile.TemporaryDirectory(prefix="doc-tree-") as base:
        paths = [os.path.join(base, uuid.uuid4().hex) for _ in range(4)]
        clean, self_loop, ancestor_loop, mutual_loop = paths

        # A clean deep tree with both file and directory symlinks.
        deep = os.path.join(clean, *[f"level{i}" for i in range(40)])
        os.makedirs(deep)
        with open(os.path.join(clean, "doc.md"), "w") as f:
            f.write("clean\n")
        with open(os.path.join(deep, "deep.md"), "w") as f:
            f.write("deep\n")
        os.symlink(os.path.join(clean, "doc.md"), os.path.join(deep, "reference.md"))
        os.mkdir(os.path.join(clean, "target"))
        os.symlink("target", os.path.join(clean, "target_alias"))

        # A directory symlink to itself.
        os.makedirs(os.path.join(self_loop, "branch"))
        with open(os.path.join(self_loop, "doc.md"), "w") as f:
            f.write("self loop\n")
        os.symlink(".", os.path.join(self_loop, "branch", "again"))

        # A descendant symlink back to an ancestor.
        os.makedirs(os.path.join(ancestor_loop, "one", "two"))
        with open(os.path.join(ancestor_loop, "one", "note.md"), "w") as f:
            f.write("ancestor loop\n")
        os.symlink("../..", os.path.join(ancestor_loop, "one", "two", "back"))

        # Two separate directories that point to each other.
        os.makedirs(os.path.join(mutual_loop, "left"))
        os.makedirs(os.path.join(mutual_loop, "right"))
        with open(os.path.join(mutual_loop, "doc.md"), "w") as f:
            f.write("mutual loop\n")
        os.symlink("../right", os.path.join(mutual_loop, "left", "to_right"))
        os.symlink("../left", os.path.join(mutual_loop, "right", "to_left"))

        assert run_validator(clean) == 0, "Validator rejected a fresh clean tree"
        for path in (self_loop, ancestor_loop, mutual_loop):
            assert run_validator(path) == 1, f"Validator accepted a fresh symlink loop: {path}"


def test_vendored_doc_compiler_fixed():
    assert os.path.isfile(PARSER_SCRIPT), f"Missing parser script: {PARSER_SCRIPT}"

    # Test it doesn't hang on evil corpus
    evil_dirs = [os.path.join(EVIL_CORPUS, d) for d in os.listdir(EVIL_CORPUS) if os.path.isdir(os.path.join(EVIL_CORPUS, d))]
    if evil_dirs:
        test_dir = evil_dirs[0]
        try:
            subprocess.run(["bash", PARSER_SCRIPT, test_dir], capture_output=True, timeout=5)
        except subprocess.TimeoutExpired:
            pytest.fail("Vendored doc compiler still hangs on infinite symlink loops.")


def test_vendored_compiler_processes_markdown_in_fresh_looped_tree():
    with tempfile.TemporaryDirectory(prefix="compiler-tree-") as root:
        nested = os.path.join(root, uuid.uuid4().hex, "nested docs")
        os.makedirs(nested)
        expected = [
            os.path.join(root, "README.md"),
            os.path.join(root, uuid.uuid4().hex + ".md"),
            os.path.join(nested, "guide.md"),
        ]
        for index, path in enumerate(expected):
            with open(path, "w") as f:
                f.write(f"document {index}\n")

        loop_dir = os.path.join(root, uuid.uuid4().hex)
        os.mkdir(loop_dir)
        os.symlink("..", os.path.join(loop_dir, "back"))

        try:
            result = subprocess.run(
                ["bash", PARSER_SCRIPT, root], capture_output=True, text=True, timeout=5
            )
        except subprocess.TimeoutExpired:
            pytest.fail("Vendored doc compiler hung on a fresh symlink loop")

        assert result.returncode == 0, (
            f"Vendored doc compiler failed on a looped tree: {result.stderr}"
        )
        for path in expected:
            assert path in result.stdout, f"Compiler did not find/process markdown file: {path}"


def test_manifest_generation():
    assert os.path.isfile(MANIFEST_FILE), f"Missing manifest file: {MANIFEST_FILE}"

    # Parse sync_requests.log
    clean_requested_dirs = []
    if os.path.isfile(SYNC_LOG):
        with open(SYNC_LOG, "r") as f:
            lines = f.read().splitlines()
            for line in lines:
                if line.startswith("PATH:"):
                    path = line.split("PATH:", 1)[1].strip()
                    if path.startswith(CLEAN_CORPUS):
                        clean_requested_dirs.append(path)

    expected_hashes = []
    for cdir in clean_requested_dirs:
        for root, dirs, files in os.walk(cdir):
            for file in files:
                if file.endswith(".md"):
                    filepath = os.path.join(root, file)
                    hasher = hashlib.sha256()
                    with open(filepath, "rb") as f:
                        hasher.update(f.read())
                    expected_hashes.append(f"{hasher.hexdigest()}  {filepath}")

    expected_hashes.sort()

    with open(MANIFEST_FILE, "r") as f:
        actual_hashes = f.read().splitlines()

    assert actual_hashes == expected_hashes, "Manifest file content does not match expected sorted SHA256 checksums of clean requested .md files."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
