#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import pytest

DB_DIR = "/app/tiny-graph-db"
BINARY = os.path.join(DB_DIR, "bin/tiny-graph-db")
MAKEFILE = os.path.join(DB_DIR, "Makefile")
SOURCE = os.path.join(DB_DIR, "main.c")
EXPECTED_SOURCE = b'''#include <stdio.h>\n\n#ifdef _INVALID_FLAG_\nthis is a deliberate syntax error\n#endif\n\nint main(void) {\n    printf("tiny-graph-db version 1.2.0\\n");\n    return 0;\n}\n'''


def run_make(target):
    env = os.environ.copy()
    env["PATH"] = "/usr/bin:/bin"
    return subprocess.run(
        ["/usr/bin/make", "-C", DB_DIR, target],
        capture_output=True,
        text=True,
        timeout=20,
        env=env,
    )


def assert_make_success(target):
    result = run_make(target)
    assert result.returncode == 0, (
        f"make {target} failed. stdout: {result.stdout} stderr: {result.stderr}"
    )


def assert_real_binary(expected_text):
    assert os.path.isfile(BINARY), f"The binary {BINARY} does not exist. Did you compile the package?"
    assert os.access(BINARY, os.X_OK), f"The file {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled ELF executable."
    result = subprocess.run([BINARY, "--version"], capture_output=True, text=True, timeout=5)
    assert expected_text in result.stdout or expected_text in result.stderr, (
        f"Expected {expected_text!r} from {BINARY} --version, but got "
        f"stdout: {result.stdout} stderr: {result.stderr}"
    )


def test_tiny_graph_db_compiled():
    assert os.path.isfile(MAKEFILE), f"The Makefile {MAKEFILE} does not exist."
    assert os.path.isfile(SOURCE), f"The source file {SOURCE} does not exist."

    # Preserve the original assertions about the submitted executable.
    assert_real_binary("tiny-graph-db version 1.2.0")

    with open(SOURCE, "rb") as f:
        original_source = f.read()
    assert original_source == EXPECTED_SOURCE, "The vendored source was changed instead of fixing its Makefile."

    with open(MAKEFILE, "r", encoding="utf-8") as f:
        makefile_text = f.read()
    active_makefile = "\n".join(line.split("#", 1)[0] for line in makefile_text.splitlines())
    assert not re.search(r"(?:^|\s)-D_INVALID_FLAG_(?:=\S+)?", active_makefile), (
        "The invalid _INVALID_FLAG_ compiler definition is still active in the Makefile."
    )

    # Delete and rebuild so a pre-created version-printing executable cannot pass.
    assert_make_success("clean")
    if os.path.lexists(BINARY):
        os.unlink(BINARY)
    assert_make_success("all")
    assert_real_binary("tiny-graph-db version 1.2.0")

    # Rebuild after changing the vendored C source to prove the Makefile's output
    # is actually compiled from main.c rather than copied or scripted.
    marker = "tiny-graph-db build marker " + secrets.token_hex(16)
    marked_source = original_source.replace(
        b"tiny-graph-db version 1.2.0", marker.encode("ascii"), 1
    )
    try:
        with open(SOURCE, "wb") as f:
            f.write(marked_source)
        assert_make_success("clean")
        if os.path.lexists(BINARY):
            os.unlink(BINARY)
        assert_make_success("all")
        assert_real_binary(marker)
    finally:
        with open(SOURCE, "wb") as f:
            f.write(original_source)
        assert_make_success("clean")
        if os.path.lexists(BINARY):
            os.unlink(BINARY)
        assert_make_success("all")

    assert_real_binary("tiny-graph-db version 1.2.0")


def invoke_sanitizer(script_path, query):
    return subprocess.run([script_path, query], capture_output=True, text=True, timeout=5)


def test_query_sanitizer_script():
    script_path = "/home/user/query_sanitizer.sh"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."

    evil_corpus = "/app/corpora/evil_queries.txt"
    clean_corpus = "/app/corpora/clean_queries.txt"
    assert os.path.isfile(evil_corpus), f"Evil corpus missing at {evil_corpus}"
    assert os.path.isfile(clean_corpus), f"Clean corpus missing at {clean_corpus}"

    with open(evil_corpus, "r") as f:
        evil_queries = [line.strip() for line in f if line.strip()]
    with open(clean_corpus, "r") as f:
        clean_queries = [line.strip() for line in f if line.strip()]

    evil_bypassed = []
    for query in evil_queries:
        result = invoke_sanitizer(script_path, query)
        if result.returncode != 1 or "REJECT" not in result.stdout.upper():
            evil_bypassed.append(query)

    clean_rejected = []
    for query in clean_queries:
        result = invoke_sanitizer(script_path, query)
        if result.returncode != 0 or "ACCEPT" not in result.stdout.upper():
            clean_rejected.append(query)

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_queries)} evil queries bypassed: {evil_bypassed[:5]}")
    if clean_rejected:
        errors.append(f"{len(clean_rejected)} of {len(clean_queries)} clean queries rejected: {clean_rejected[:5]}")
    if errors:
        pytest.fail(" | ".join(errors))

    # Exercise fresh, unpredictable queries so the shipped corpora cannot simply
    # be hardcoded. Expected answers are derived from the generated path bounds.
    rng = secrets.SystemRandom()
    generated = []
    for _ in range(16):
        tag = secrets.token_hex(10)
        left = "n" + tag
        right = "m" + tag

        generated.append((f"MATCH ({left})->({right}) RETURN '{tag}'", "ACCEPT", 0))

        maximum = rng.randint(1, 5)
        minimum = rng.randint(1, maximum)
        generated.append((
            f"MATCH ({left})-[*{minimum}..{maximum}]->({right}) RETURN '{tag}'",
            "ACCEPT", 0
        ))

        bad_maximum = rng.randint(6, 250)
        bad_minimum = rng.randint(1, bad_maximum)
        generated.append((
            f"MATCH ({left})-[*{bad_minimum}..{bad_maximum}]->({right}) RETURN '{tag}'",
            "REJECT", 1
        ))

        omitted_upper_minimum = rng.randint(1, 50)
        omitted_lower_maximum = rng.randint(1, 50)
        generated.extend([
            (f"MATCH ({left})-[*]->({right}) RETURN '{tag}'", "REJECT", 1),
            (f"MATCH ({left})-[*..]->({right}) RETURN '{tag}'", "REJECT", 1),
            (f"MATCH ({left})-[*..{omitted_lower_maximum}]->({right}) RETURN '{tag}'", "REJECT", 1),
            (f"MATCH ({left})-[*{omitted_upper_minimum}..]->({right}) RETURN '{tag}'", "REJECT", 1),
            (f"MATCH ({left})-[*1..3]->({right}), ({right})-[*2..{bad_maximum}]->(z{tag})", "REJECT", 1),
        ])

    rng.shuffle(generated)
    failures = []
    for query, expected_output, expected_code in generated:
        result = invoke_sanitizer(script_path, query)
        if result.returncode != expected_code or result.stdout.strip().upper() != expected_output:
            failures.append(
                f"query={query!r}, expected ({expected_code}, {expected_output}), "
                f"got ({result.returncode}, {result.stdout!r})"
            )
    assert not failures, "Generated sanitizer cases failed: " + " | ".join(failures[:5])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
