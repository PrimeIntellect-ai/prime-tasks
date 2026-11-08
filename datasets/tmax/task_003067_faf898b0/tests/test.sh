#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import string
import subprocess
import tempfile
import pytest

SANITIZER_PATH = "/home/user/sanitizer"
CLEAN_DIR = "/home/user/corpora/clean"
EVIL_DIR = "/home/user/corpora/evil"


def run_sanitizer(filepath):
    return subprocess.run(
        [SANITIZER_PATH, filepath],
        capture_output=True,
        text=True,
        timeout=5,
    )


def test_sanitizer_exists_and_executable():
    assert os.path.isfile(SANITIZER_PATH), f"Compiled program not found at {SANITIZER_PATH}"
    assert os.access(SANITIZER_PATH, os.X_OK), f"Program at {SANITIZER_PATH} is not executable"
    with open(SANITIZER_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Sanitizer must be a compiled executable"


def test_clean_corpus():
    if not os.path.isfile(SANITIZER_PATH):
        pytest.fail("Sanitizer missing")

    clean_files = [os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f))]
    assert len(clean_files) > 0, "No files found in clean corpus directory"

    failed_files = []
    for filepath in clean_files:
        result = run_sanitizer(filepath)
        stdout = result.stdout.strip()
        if result.returncode != 0 or stdout != "CLEAN":
            failed_files.append((os.path.basename(filepath), result.returncode, stdout))

    if failed_files:
        details = ", ".join([f"{f} (code {c}, out {o})" for f, c, o in failed_files])
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified/rejected: {details}")


def test_evil_corpus():
    if not os.path.isfile(SANITIZER_PATH):
        pytest.fail("Sanitizer missing")

    evil_files = [os.path.join(EVIL_DIR, f) for f in os.listdir(EVIL_DIR) if os.path.isfile(os.path.join(EVIL_DIR, f))]
    assert len(evil_files) > 0, "No files found in evil corpus directory"

    failed_files = []
    for filepath in evil_files:
        result = run_sanitizer(filepath)
        stdout = result.stdout.strip()
        if result.returncode != 1 or stdout != "EVIL":
            failed_files.append((os.path.basename(filepath), result.returncode, stdout))

    if failed_files:
        details = ", ".join([f"{f} (code {c}, out {o})" for f, c, o in failed_files])
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil bypassed: {details}")


class PolicyParser:
    def __init__(self, text):
        self.text = text
        self.pos = 0

    def skip_ws(self):
        while self.pos < len(self.text) and self.text[self.pos].isspace():
            self.pos += 1

    def parse_identifier(self):
        self.skip_ws()
        if self.pos >= len(self.text) or not (self.text[self.pos].isalpha() or self.text[self.pos] == "_"):
            raise ValueError("identifier expected")
        start = self.pos
        self.pos += 1
        while self.pos < len(self.text) and (self.text[self.pos].isalnum() or self.text[self.pos] == "_"):
            self.pos += 1
        return self.text[start:self.pos]

    def parse_expr(self):
        self.skip_ws()
        if self.pos >= len(self.text):
            raise ValueError("expression expected")

        if self.text[self.pos].isdigit():
            while self.pos < len(self.text) and self.text[self.pos].isdigit():
                self.pos += 1
            return 1, False

        name = self.parse_identifier()
        self.skip_ws()
        if self.pos >= len(self.text) or self.text[self.pos] != "(":
            return 1, False

        self.pos += 1
        child_depths = []
        forbidden = name == "alloc"
        depth, child_forbidden = self.parse_expr()
        child_depths.append(depth)
        forbidden = forbidden or child_forbidden

        while True:
            self.skip_ws()
            if self.pos < len(self.text) and self.text[self.pos] == ",":
                self.pos += 1
                depth, child_forbidden = self.parse_expr()
                child_depths.append(depth)
                forbidden = forbidden or child_forbidden
                continue
            if self.pos < len(self.text) and self.text[self.pos] == ")":
                self.pos += 1
                break
            raise ValueError("comma or closing parenthesis expected")

        return 1 + max(child_depths), forbidden

    def evaluate(self):
        try:
            depth, forbidden = self.parse_expr()
            self.skip_ws()
            if self.pos != len(self.text):
                return False
            return depth <= 4 and not forbidden
        except ValueError:
            return False


def policy_allows(expression):
    return PolicyParser(expression).evaluate()


def random_space(rng):
    return rng.choice(["", " ", "  ", "\t"])


def make_clean_expr(rng, levels):
    if levels == 0:
        if rng.choice([True, False]):
            return str(rng.randint(10, 999999))
        return "v" + "".join(rng.choice(string.ascii_lowercase) for _ in range(10))

    function = rng.choice(["add", "mul", "sub", "concat"])
    left = make_clean_expr(rng, levels - 1)
    right = make_clean_expr(rng, rng.randint(0, levels - 1))
    return (
        function + random_space(rng) + "(" + random_space(rng) + left
        + random_space(rng) + "," + random_space(rng) + right
        + random_space(rng) + ")"
    )


def write_case(directory, expression):
    filename = "case_" + secrets.token_hex(12) + ".txt"
    path = os.path.join(directory, filename)
    with open(path, "w", encoding="utf-8") as f:
        f.write(expression)
    return path


def test_fresh_independently_classified_expressions():
    seed = int.from_bytes(secrets.token_bytes(16), "big")
    rng = random.Random(seed)
    cases = []

    # Valid trees stay at or below AST depth 4.
    for _ in range(24):
        cases.append(make_clean_expr(rng, rng.randint(1, 3)))

    # Forbidden calls occur at varying positions in otherwise valid trees.
    for _ in range(12):
        inner = make_clean_expr(rng, rng.randint(0, 2))
        if rng.choice([True, False]):
            cases.append(f"alloc({inner})")
        else:
            cases.append(f"add({rng.randint(1, 9999)}, alloc({inner}))")

    # These have AST depth 6, unambiguously beyond the policy maximum of 4.
    for _ in range(12):
        expression = str(rng.randint(1, 999999))
        for _ in range(5):
            expression = f"add({expression}, {rng.randint(1, 999999)})"
        cases.append(expression)

    # Fresh malformed variants exercise complete syntax validation.
    n = rng.randint(10000, 99999)
    cases.extend([
        f"add({n},)",
        f"mul(,{n})",
        f"sub({n} {n + 1})",
        f"concat({n}, {n + 1}",
        f"add({n}, {n + 1}))",
        f"add(({n}), {n + 1})",
        f"mul({n}, {n + 1}) trailing_{secrets.token_hex(4)}",
        "",
    ])

    expected = [policy_allows(expression) for expression in cases]
    assert any(expected) and not all(expected), "Generated suite must contain both policy outcomes"

    with tempfile.TemporaryDirectory(prefix="sanitizer_dynamic_") as directory:
        order = list(range(len(cases)))
        rng.shuffle(order)
        failures = []
        for index in order:
            filepath = write_case(directory, cases[index])
            result = run_sanitizer(filepath)
            wanted_clean = expected[index]
            wanted_code = 0 if wanted_clean else 1
            wanted_output = "CLEAN" if wanted_clean else "EVIL"
            if result.returncode != wanted_code or result.stdout.strip() != wanted_output:
                failures.append((index, wanted_code, wanted_output, result.returncode, result.stdout.strip()))

        assert not failures, f"Fresh policy cases failed (seed={seed}): {failures[:5]}"


def test_memory_leaks_valgrind():
    if not os.path.isfile(SANITIZER_PATH):
        pytest.fail("Sanitizer missing")

    clean_files = [os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f))]
    assert len(clean_files) > 0, "No files found in clean corpus directory"

    test_file = clean_files[0]
    valgrind_cmd = [
        "valgrind",
        "--leak-check=full",
        "--show-leak-kinds=all",
        "--error-exitcode=42",
        SANITIZER_PATH,
        test_file,
    ]

    try:
        result = subprocess.run(valgrind_cmd, capture_output=True, text=True, timeout=30)
    except FileNotFoundError:
        pytest.fail("valgrind is not installed or not in PATH")

    if result.returncode == 42:
        pytest.fail(f"Memory leak detected by valgrind on file {os.path.basename(test_file)}.\nValgrind output:\n{result.stderr}")

    if "definitely lost:" in result.stderr:
        for line in result.stderr.splitlines():
            if "definitely lost:" in line and " 0 bytes in 0 blocks" not in line:
                pytest.fail(f"Memory leak detected in valgrind output: {line.strip()}")


def test_memory_leaks_on_fresh_nested_tree():
    expression = "mul(add(101, sub(202, 303)), concat(item_alpha, item_beta))"
    assert policy_allows(expression)
    with tempfile.TemporaryDirectory(prefix="sanitizer_valgrind_") as directory:
        filepath = write_case(directory, expression)
        result = subprocess.run([
            "valgrind",
            "--leak-check=full",
            "--show-leak-kinds=all",
            "--errors-for-leak-kinds=all",
            "--error-exitcode=42",
            SANITIZER_PATH,
            filepath,
        ], capture_output=True, text=True, timeout=30)

        assert result.returncode == 0, f"Valgrind or sanitizer failure:\n{result.stderr}\n{result.stdout}"
        assert result.stdout.strip() == "CLEAN"
        for line in result.stderr.splitlines():
            if "definitely lost:" in line:
                assert " 0 bytes in 0 blocks" in line, f"Memory leak detected: {line.strip()}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
