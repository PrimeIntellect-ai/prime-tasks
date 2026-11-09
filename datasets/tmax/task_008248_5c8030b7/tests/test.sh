#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile
import textwrap
import pytest

PROJECT = "/home/user/waf_pr"
ENGINE = os.path.join(PROJECT, "waf_engine")
LOG = os.path.join(PROJECT, "test_results.log")


def test_waf_engine_compiled():
    assert os.path.isfile(ENGINE), f"Compiled binary {ENGINE} is missing. Did you run gcc?"
    assert os.access(ENGINE, os.X_OK), f"File {ENGINE} is not executable."


def test_test_results_log():
    assert os.path.isfile(LOG), f"Output file {LOG} is missing."

    with open(LOG, "r") as f:
        content = f.read().strip()

    assert len(content) > 0, f"Output file {LOG} is empty."

    # Preserve the original output assertions.
    assert "1" in content and "0" in content, \
        f"Output file {LOG} does not contain expected routing paths."


def test_rebuild_from_submitted_sources_and_verify_output():
    result = subprocess.run(
        ["gcc", "main.c", "ip_trie.c", "-o", "waf_engine"],
        cwd=PROJECT,
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"Project failed to compile:\n{result.stderr}"

    run = subprocess.run(
        [ENGINE], cwd=PROJECT, capture_output=True, text=True, timeout=10
    )
    assert run.returncode == 0, f"Rebuilt waf_engine failed:\n{run.stderr}"

    # These paths are derived from main.c's inserts and the required merge rule:
    # the root absorbs its sole '1' child, and the unary 11->1 branch is merged.
    assert run.stdout.splitlines() == ["100", "101", "11"], \
        f"Unexpected routing paths from rebuilt engine: {run.stdout!r}"

    with open(LOG, "r") as f:
        saved = f.read()
    assert saved == run.stdout, \
        "test_results.log is not the redirected output of the rebuilt waf_engine"


def test_trie_compression_structure_and_memory_safety():
    harness = textwrap.dedent(r'''
        #include <stdio.h>
        #include <stdlib.h>
        #include "ip_trie.h"

        static void require(int condition, const char *message) {
            if (!condition) {
                fprintf(stderr, "%s\n", message);
                exit(2);
            }
        }

        int main(void) {
            Node *root = create_node('R');
            require(root != NULL, "create_node returned NULL");
            insert(root, "101");
            insert(root, "100");
            insert(root, "111");
            trie_compress(root);

            require(root->key == '1' && root->is_end == 0,
                    "root did not absorb its sole child");
            require(root->left != NULL && root->right != NULL,
                    "compression lost a branching child");
            require(root->left->key == '0' && root->left->is_end == 0,
                    "branching node was compressed incorrectly");
            require(root->left->left != NULL && root->left->right != NULL,
                    "compression lost the 100/101 branches");
            require(root->left->left->key == '0' && root->left->left->is_end,
                    "100 terminal was not preserved");
            require(root->left->right->key == '1' && root->left->right->is_end,
                    "101 terminal was not preserved");
            require(root->right->key == '1' && root->right->is_end,
                    "recursive unary path was not merged");
            require(root->right->left == NULL && root->right->right == NULL,
                    "merged child links were not updated");
            trie_free(root);

            root = create_node('R');
            require(root != NULL, "create_node returned NULL");
            insert(root, "0");
            insert(root, "00");
            trie_compress(root);
            require(root->key == '0' && root->is_end == 1,
                    "unary root merge did not preserve the assigned rule");
            require(root->left != NULL && root->left->is_end == 1,
                    "a node with an assigned rule was incorrectly merged");
            require(root->right == NULL,
                    "compression introduced an unexpected branch");
            trie_free(root);
            return 0;
        }
    ''')

    with tempfile.TemporaryDirectory() as td:
        harness_path = os.path.join(td, "trie_harness.c")
        binary_path = os.path.join(td, "trie_harness")
        with open(harness_path, "w") as f:
            f.write(harness)

        build = subprocess.run(
            ["gcc", "-I", PROJECT, harness_path,
             os.path.join(PROJECT, "ip_trie.c"), "-o", binary_path],
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert build.returncode == 0, f"Trie harness failed to compile:\n{build.stderr}"

        result = subprocess.run(
            [
                "valgrind",
                "--leak-check=full",
                "--show-leak-kinds=all",
                "--errors-for-leak-kinds=all",
                "--error-exitcode=1",
                binary_path,
            ],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, \
            f"Trie behavior or memory-safety test failed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"


def test_memory_safety_with_valgrind():
    assert os.path.isfile(ENGINE), "Cannot run valgrind because waf_engine is missing."

    cmd = [
        "valgrind",
        "--leak-check=full",
        "--show-leak-kinds=all",
        "--error-exitcode=1",
        ENGINE,
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, \
            f"Valgrind reported memory errors or leaks. stderr:\n{result.stderr}"
    except FileNotFoundError:
        pytest.fail("valgrind is not installed or not found in PATH. Cannot verify memory safety.")
    except subprocess.TimeoutExpired:
        pytest.fail("valgrind execution timed out. There might be an infinite loop in your code.")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
