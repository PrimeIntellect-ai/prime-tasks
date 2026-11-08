#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shutil
import subprocess
import tempfile
import uuid

PROJECT_DIR = "/home/user/log-parser"
LOG_FILE = "/home/user/logs/server.log"
MAIN_RS = "/home/user/log-parser/src/main.rs"
MALFORMED_LINE = "2023-10-12T14:32:01Z 10.0.0.42"


def run_cargo(args, cwd=PROJECT_DIR):
    return subprocess.run(
        ["cargo", *args],
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=120,
    )


def test_bug_report_content():
    report_path = "/home/user/bug_report.txt"
    assert os.path.isfile(report_path), f"The bug report file {report_path} is missing."

    with open(report_path, "r") as f:
        content = f.read().strip()

    expected_content = "Line content: 2023-10-12T14:32:01Z 10.0.0.42"
    assert content == expected_content, (
        f"The bug report content is incorrect. Expected: '{expected_content}', "
        f"but got: '{content}'"
    )


def test_cargo_run_success_and_correct_count():
    result = run_cargo(["run", "--", LOG_FILE])

    assert result.returncode == 0, (
        f"`cargo run` failed with exit code {result.returncode}.\nStderr: {result.stderr}"
    )
    assert "Successfully parsed" in result.stdout, (
        "The output does not indicate successful parsing of lines."
    )
    assert result.stdout.strip() == "Successfully parsed 9999 lines.", (
        "The parser must ignore the single malformed line and report exactly 9999 "
        f"successfully parsed lines. Got stdout: {result.stdout!r}"
    )


def test_parser_on_generated_mixed_input():
    rng = random.SystemRandom()
    nonce = uuid.uuid4().hex
    valid_count = rng.randint(8, 24)

    valid_lines = [
        f"2026-09-11T12:34:{i % 60:02d}Z 172.16.{rng.randrange(1, 255)}.{rng.randrange(1, 255)} 200 EVENT_{nonce}_{i}"
        for i in range(valid_count)
    ]
    malformed_lines = [
        "",
        f"ONE_{nonce}",
        f"TWO_{nonce} fields",
        f"THREE_{nonce} fields 200",
        MALFORMED_LINE,
    ]
    lines = valid_lines + malformed_lines
    rng.shuffle(lines)

    with tempfile.NamedTemporaryFile("w", delete=False) as handle:
        generated_log = handle.name
        handle.write("\n".join(lines))
        handle.write("\n")

    try:
        result = run_cargo(["run", "--quiet", "--", generated_log])
    finally:
        os.unlink(generated_log)

    assert result.returncode == 0, (
        "The parser crashed on generated input containing lines with fewer than four "
        f"space-separated parts.\nStdout: {result.stdout}\nStderr: {result.stderr}"
    )
    expected = f"Successfully parsed {valid_count} lines."
    assert result.stdout.strip() == expected, (
        "Malformed lines were not ignored or valid lines were counted incorrectly. "
        f"Expected {expected!r}, got {result.stdout!r}"
    )


def test_cargo_test_success():
    result = run_cargo(["test"])

    assert result.returncode == 0, (
        f"`cargo test` failed with exit code {result.returncode}.\nStderr: {result.stderr}"
    )
    assert "test_malformed_line" in result.stdout, (
        "The output of `cargo test` does not indicate that `test_malformed_line` was run."
    )


def test_main_rs_contains_real_regression_test():
    assert os.path.isfile(MAIN_RS), f"The source file {MAIN_RS} is missing."
    with open(MAIN_RS, "r") as f:
        content = f.read()

    assert "fn test_malformed_line" in content, (
        "The function `test_malformed_line` is missing from main.rs."
    )

    # Remove comments so keywords in a commented-out or empty test do not satisfy this check.
    uncommented = re.sub(r"/\*.*?\*/", "", content, flags=re.S)
    uncommented = re.sub(r"//[^\n]*", "", uncommented)
    matches = list(re.finditer(r"\bfn\s+test_malformed_line\s*\([^)]*\)\s*\{", uncommented))
    assert matches, "No implemented `test_malformed_line` function was found."

    suitable = False
    for match in matches:
        start = match.end() - 1
        depth = 0
        end = None
        for pos in range(start, len(uncommented)):
            if uncommented[pos] == "{":
                depth += 1
            elif uncommented[pos] == "}":
                depth -= 1
                if depth == 0:
                    end = pos
                    break
        if end is None:
            continue
        body = uncommented[start + 1:end]
        if (
            re.search(r"\bparse_line\s*\(", body)
            and MALFORMED_LINE in body
            and re.search(r"\bassert(?:_eq|_ne)?!\s*\(", body)
        ):
            suitable = True
            break

    assert suitable, (
        "`test_malformed_line` must call `parse_line` with the identified malformed "
        "line and assert the result; an empty or unrelated passing test is insufficient."
    )


def test_parse_line_contract_directly():
    # Append verifier-owned tests to a temporary copy of the submitted crate so the
    # private parse_line function is actually exercised without altering the submission.
    with tempfile.TemporaryDirectory() as temp_root:
        copied_project = os.path.join(temp_root, "log-parser")
        shutil.copytree(
            PROJECT_DIR,
            copied_project,
            ignore=shutil.ignore_patterns("target", ".git"),
        )
        copied_main = os.path.join(copied_project, "src", "main.rs")
        suffix = uuid.uuid4().hex
        module_name = f"__verifier_behavior_{suffix}"
        trait_name = f"VerifierOutcome_{suffix}"
        test_name = f"verifier_parse_line_contract_{suffix}"

        injected = f'''

#[cfg(test)]
mod {module_name} {{
    use super::*;

    trait {trait_name} {{
        fn rejected(&self) -> bool;
        fn accepted(&self) -> bool;
    }}

    impl<T> {trait_name} for Option<T> {{
        fn rejected(&self) -> bool {{ self.is_none() }}
        fn accepted(&self) -> bool {{ self.is_some() }}
    }}

    impl<T, E> {trait_name} for Result<T, E> {{
        fn rejected(&self) -> bool {{ self.is_err() }}
        fn accepted(&self) -> bool {{ self.is_ok() }}
    }}

    #[test]
    fn {test_name}() {{
        assert!({trait_name}::rejected(&parse_line("{MALFORMED_LINE}")));
        assert!({trait_name}::rejected(&parse_line("one")));
        assert!({trait_name}::rejected(&parse_line("one two")));
        assert!({trait_name}::rejected(&parse_line("one two 200")));
        assert!({trait_name}::accepted(&parse_line(
            "2026-09-11T00:00:00Z 127.0.0.1 200 VALID_ENTRY"
        )));
    }}
}}
'''
        with open(copied_main, "a") as handle:
            handle.write(injected)

        result = run_cargo(
            ["test", "--manifest-path", os.path.join(copied_project, "Cargo.toml"), test_name],
            cwd=copied_project,
        )
        assert result.returncode == 0, (
            "Direct verification of `parse_line` failed. It must reject the identified "
            "malformed line and other inputs with fewer than four parts without panicking, "
            "while accepting a valid line.\n"
            f"Stdout: {result.stdout}\nStderr: {result.stderr}"
        )
        assert test_name in result.stdout, "The injected parse_line contract test did not run."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
