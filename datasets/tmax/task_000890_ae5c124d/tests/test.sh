#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import os
import random
import string
import subprocess
import sys
import uuid
import pytest

ORACLE = "/app/legacy_encoder"
AGENT_SCRIPT = "/home/user/fixed_encode.py"
REPO = "/home/user/encoder_repo"
REPO_SCRIPT = os.path.join(REPO, "encode.py")
KEY = "SUPPORT"


def run_checked(argv):
    return subprocess.run(argv, capture_output=True, text=True, check=True).stdout.strip()


def expected_encoding(value):
    return "".join(
        f"{((ord(char) ^ ord(KEY[index % len(KEY)])) + 5):02x}"
        for index, char in enumerate(value)
    )


def load_source(path):
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read()


def assertion_lines_in_encode(path):
    source = load_source(path)
    tree = ast.parse(source, filename=path)
    functions = [
        node for node in tree.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == "encode"
    ]
    assert functions, f"{path} must define encode(input_str)."
    function = functions[0]
    assertions = [node for node in ast.walk(function) if isinstance(node, ast.Assert)]
    assert assertions, f"{path} lacks assertion-based intermediate validation in encode()."

    local_names = {arg.arg for arg in function.args.args}
    local_names.update(
        node.id for node in ast.walk(function)
        if isinstance(node, ast.Name) and isinstance(node.ctx, ast.Store)
    )
    meaningful = []
    for assertion in assertions:
        used = {node.id for node in ast.walk(assertion.test) if isinstance(node, ast.Name)}
        if used & local_names and not isinstance(assertion.test, ast.Constant):
            meaningful.append(assertion)
    assert meaningful, f"Assertions in {path} do not validate encoder intermediate state."
    return {node.lineno for node in meaningful}


def import_and_trace_assertion(path, sample):
    assertion_lines = assertion_lines_in_encode(path)
    module_name = "submitted_encoder_" + uuid.uuid4().hex
    spec = importlib.util.spec_from_file_location(module_name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, "encode", None)), f"{path} has no callable encode()."

    executed = set()
    target = os.path.realpath(path)

    def tracer(frame, event, arg):
        if event == "line" and os.path.realpath(frame.f_code.co_filename) == target:
            executed.add(frame.f_lineno)
        return tracer

    old_trace = sys.gettrace()
    try:
        sys.settrace(tracer)
        result = module.encode(sample)
    finally:
        sys.settrace(old_trace)

    assert result == expected_encoding(sample), f"encode() in {path} returned an incorrect result."
    assert executed & assertion_lines, f"Intermediate assertions in {path} were not exercised."


def test_fixed_encode_exists():
    assert os.path.isfile(AGENT_SCRIPT), "The fixed python script /home/user/fixed_encode.py does not exist."


def test_git_bisection_and_main_fix():
    assert os.path.isdir(os.path.join(REPO, ".git")), "Encoder Git repository is missing."
    branch = run_checked(["git", "-C", REPO, "branch", "--show-current"])
    assert branch == "main", "The repository must be returned to and fixed on the main branch."
    assert os.path.isfile(REPO_SCRIPT), "The main-branch encode.py is missing."

    bad_commits = run_checked([
        "git", "-C", REPO, "log", "--format=%H", "--grep=^Optimize key cycling$",
        "v1.0..main"
    ]).splitlines()
    assert len(bad_commits) == 1, "Could not identify the unique regression-introducing commit."
    bad_commit = bad_commits[0]

    reflog = run_checked(["git", "-C", REPO, "reflog", "--all", "--format=%H%x09%gs"])
    checkout_hashes = []
    for line in reflog.splitlines():
        commit, _, subject = line.partition("\t")
        if subject.startswith("checkout: moving from "):
            checkout_hashes.append(commit)

    assert bad_commit in checkout_hashes, (
        "Git reflog does not show the regression commit being checked out during investigation."
    )
    investigated_good = False
    for commit in checkout_hashes:
        if commit == bad_commit:
            continue
        after_tag = subprocess.run(
            ["git", "-C", REPO, "merge-base", "--is-ancestor", "v1.0", commit]
        ).returncode == 0
        before_bad = subprocess.run(
            ["git", "-C", REPO, "merge-base", "--is-ancestor", commit, bad_commit]
        ).returncode == 0
        if after_tag and before_bad:
            investigated_good = True
            break
    assert investigated_good, "Git reflog lacks the good/bad midpoint traversal produced by bisection."

    status = run_checked(["git", "-C", REPO, "status", "--porcelain", "--", "encode.py"])
    assert status, "The broken main-branch encode.py was not fixed."


def test_real_implementation_and_assertions():
    for path in (AGENT_SCRIPT, REPO_SCRIPT):
        source = load_source(path)
        assert "/app/legacy_encoder" not in source and "legacy_encoder" not in source, (
            f"{path} delegates to the oracle instead of implementing the encoder."
        )
        import_and_trace_assertion(path, "Bisect!Root~Cause")

    reference = subprocess.run(
        ["git", "-C", REPO, "show", "v1.0:encode.py"],
        capture_output=True, check=True
    ).stdout
    assert open(AGENT_SCRIPT, "rb").read() != reference, (
        "The final script must not be a byte-identical copy of the known-good reference."
    )


def test_independent_equivalence_without_oracle_available():
    hidden = f"/tmp/legacy_encoder.hidden.{uuid.uuid4().hex}"
    assert os.path.isfile(ORACLE), f"Oracle program {ORACLE} missing."
    os.replace(ORACLE, hidden)
    try:
        cases = [
            "", "!", "~", "!~!~", "SUPPORT", "customer escalation",
            "".join(chr(code) for code in range(1, 128)),
        ]
        random.seed(1907)
        ascii_chars = [chr(code) for code in range(1, 128)]
        for _ in range(100):
            cases.append("".join(random.choice(ascii_chars) for _ in range(random.randint(0, 160))))

        for path in (AGENT_SCRIPT, REPO_SCRIPT):
            for value in cases:
                proc = subprocess.run(
                    ["python3", path, value], capture_output=True, text=True
                )
                assert proc.returncode == 0, (
                    f"{path} crashed on {value!r}: {proc.stderr}"
                )
                assert proc.stdout.strip() == expected_encoding(value), (
                    f"Independent mismatch from {path} on {value!r}."
                )
    finally:
        os.replace(hidden, ORACLE)


def test_fuzz_equivalence():
    oracle_path = "/app/legacy_encoder"
    agent_script = "/home/user/fixed_encode.py"

    assert os.path.isfile(oracle_path), f"Oracle program {oracle_path} missing."
    assert os.path.isfile(agent_script), f"Agent script {agent_script} missing."

    # Generate printable characters excluding null byte
    # string.printable includes ascii_letters, digits, punctuation, and whitespace
    chars = [c for c in string.printable if c != '\0']

    random.seed(42)
    num_tests = 500

    for i in range(num_tests):
        length = random.randint(1, 100)
        test_input = "".join(random.choice(chars) for _ in range(length))

        # Run oracle
        try:
            oracle_proc = subprocess.run(
                [oracle_path, test_input],
                capture_output=True,
                text=True,
                check=True
            )
            oracle_out = oracle_proc.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle crashed on input {repr(test_input)}: {e.stderr}")

        # Run agent
        try:
            agent_proc = subprocess.run(
                ["python3", agent_script, test_input],
                capture_output=True,
                text=True,
                check=True
            )
            agent_out = agent_proc.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent program crashed on input {repr(test_input)}.\nError: {e.stderr}")

        assert agent_out == oracle_out, (
            f"Mismatch on input: {repr(test_input)}\n"
            f"Expected (Oracle): {oracle_out}\n"
            f"Got (Agent):       {agent_out}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
