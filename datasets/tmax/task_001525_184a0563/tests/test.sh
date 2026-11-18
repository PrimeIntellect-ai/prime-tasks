#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import subprocess
import tempfile
import pytest

SCRIPT = "/home/user/run_ci.sh"
SOURCE = "/home/user/src/parser.c"
PARSER = "/home/user/parser"
DATA = "/home/user/data.txt"
VERSION = "/home/user/version.txt"
REPORT = "/home/user/ci_report.txt"


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def snapshot(paths):
    saved = {}
    for path in paths:
        if os.path.exists(path):
            with open(path, "rb") as f:
                saved[path] = (f.read(), stat.S_IMODE(os.stat(path).st_mode))
        else:
            saved[path] = None
    return saved


def restore(saved):
    for path, value in saved.items():
        if value is None:
            if os.path.exists(path):
                os.remove(path)
        else:
            data, mode = value
            with open(path, "wb") as f:
                f.write(data)
            os.chmod(path, mode)


def write_text(path, text, mode=None):
    with open(path, "w") as f:
        f.write(text)
    if mode is not None:
        os.chmod(path, mode)


def clean_source(marker):
    return f'''#include <stdio.h>
int main(int argc, char **argv) {{
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    fclose(f);
    puts("{marker}");
    return 0;
}}
'''


def leaking_source():
    return '''#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    char *p = malloc(137);
    if (!p) { fclose(f); return 1; }
    p[0] = 'x';
    printf("%c\\n", p[0]);
    fclose(f);
    return 0;
}
'''


def test_run_ci_sh_exists_and_executable():
    script_path = "/home/user/run_ci.sh"
    assert os.path.isfile(script_path), f"The file {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."


def test_run_ci_execution_and_report():
    script_path = "/home/user/run_ci.sh"
    version_path = "/home/user/version.txt"
    report_path = "/home/user/ci_report.txt"

    assert os.path.isfile(version_path), "version.txt is missing."
    with open(version_path, "r") as f:
        version = f.read().strip()

    if os.path.exists(report_path):
        os.remove(report_path)

    result = subprocess.run([script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"run_ci.sh failed with exit code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"

    assert os.path.isfile(report_path), f"The report file {report_path} was not created by run_ci.sh."
    with open(report_path, "r") as f:
        report_content = f.read().strip()

    expected_report = f"CI SUCCESS: {version}"
    assert report_content == expected_report, f"Expected report content '{expected_report}', but got '{report_content}'."


def test_parser_memory_leak_fixed():
    parser_path = "/home/user/parser"
    data_path = "/home/user/data.txt"

    assert os.path.isfile(parser_path), f"The compiled executable {parser_path} does not exist."
    assert os.access(parser_path, os.X_OK), f"The file {parser_path} is not executable."

    valgrind_cmd = [
        "valgrind",
        "--leak-check=full",
        "--error-exitcode=1",
        parser_path,
        data_path,
    ]
    result = subprocess.run(valgrind_cmd, capture_output=True, text=True)
    assert result.returncode == 0, f"Valgrind detected memory leaks or errors. Exit code: {result.returncode}.\nStderr: {result.stderr}"


def test_supplied_parser_source_compiles_cleanly_and_preserves_behavior():
    assert os.path.isfile(SOURCE), f"The source file {SOURCE} is missing."
    token = secrets.token_hex(8)
    key = "key_" + token
    value = "value_" + secrets.token_hex(7)
    with tempfile.TemporaryDirectory() as td:
        binary = os.path.join(td, "parser")
        input_path = os.path.join(td, "data.txt")
        write_text(input_path, f"{key}={value}\n")

        compiled = run(["gcc", "-Wall", "-Wextra", "-Werror", SOURCE, "-o", binary])
        assert compiled.returncode == 0, f"parser.c did not compile without warnings.\nStdout: {compiled.stdout}\nStderr: {compiled.stderr}"

        parsed = run([binary, input_path])
        assert parsed.returncode == 0, f"Compiled parser failed.\nStdout: {parsed.stdout}\nStderr: {parsed.stderr}"
        assert parsed.stdout == f"Loaded: {key} = {value}\n", f"The supplied parser's key/value behavior was not preserved: {parsed.stdout!r}"

        checked = run(["valgrind", "--leak-check=full", "--error-exitcode=1", binary, input_path])
        assert checked.returncode == 0, f"The executable compiled directly from parser.c has memory errors or leaks.\nStderr: {checked.stderr}"


def test_ci_semver_ordering_source_compilation_and_valgrind():
    saved = snapshot([SOURCE, PARSER, VERSION, REPORT])
    try:
        # Versions below 2.0.0 must exit with status 1 before compilation.
        low_versions = [
            f"1.{secrets.randbelow(900) + 100}.{secrets.randbelow(900) + 100}",
            f"0.{secrets.randbelow(1000)}.{secrets.randbelow(1000)}",
        ]
        for version in low_versions:
            marker = "LOW_" + secrets.token_hex(12)
            write_text(SOURCE, clean_source(marker))
            sentinel = ("#!/bin/sh\necho SENTINEL_" + secrets.token_hex(12) + "\n").encode()
            with open(PARSER, "wb") as f:
                f.write(sentinel)
            os.chmod(PARSER, 0o755)
            write_text(VERSION, version + "\n")
            if os.path.exists(REPORT):
                os.remove(REPORT)

            result = run([SCRIPT])
            assert result.returncode == 1, f"Version {version} must be rejected with status 1, got {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"
            with open(PARSER, "rb") as f:
                assert f.read() == sentinel, "run_ci.sh compiled or replaced /home/user/parser before rejecting a low version."
            assert not os.path.exists(REPORT), "run_ci.sh wrote a success report for a rejected version."

        # Accepted versions must compile the current parser.c before running it.
        high_versions = [
            "2.0.0",
            f"2.{secrets.randbelow(900) + 1}.{secrets.randbelow(1000)}",
            f"{secrets.randbelow(18) + 3}.{secrets.randbelow(1000)}.{secrets.randbelow(1000)}",
        ]
        for version in high_versions:
            marker = "BUILT_" + secrets.token_hex(12)
            write_text(SOURCE, clean_source(marker))
            write_text(VERSION, version + "\n")
            if os.path.exists(PARSER):
                os.remove(PARSER)
            if os.path.exists(REPORT):
                os.remove(REPORT)

            result = run([SCRIPT])
            assert result.returncode == 0, f"Valid version {version} was rejected.\nStdout: {result.stdout}\nStderr: {result.stderr}"
            assert os.path.isfile(PARSER) and os.access(PARSER, os.X_OK), "run_ci.sh did not create an executable /home/user/parser."
            parser_result = run([PARSER, DATA])
            assert parser_result.returncode == 0
            assert parser_result.stdout == marker + "\n", "The CI artifact was not compiled from the current /home/user/src/parser.c."
            assert os.path.isfile(REPORT), "run_ci.sh did not create ci_report.txt after a successful run."
            with open(REPORT, "r") as f:
                assert f.read().strip() == f"CI SUCCESS: {version}"

        # A newly compiled leaking source must be rejected, proving the compiled
        # artifact is run through leak-detecting Valgrind before success is logged.
        version = f"2.{secrets.randbelow(800) + 1}.{secrets.randbelow(1000)}"
        write_text(SOURCE, leaking_source())
        write_text(VERSION, version + "\n")
        if os.path.exists(PARSER):
            os.remove(PARSER)
        if os.path.exists(REPORT):
            os.remove(REPORT)

        result = run([SCRIPT])
        assert result.returncode != 0, f"run_ci.sh accepted a freshly compiled program with a definite memory leak.\nStdout: {result.stdout}\nStderr: {result.stderr}"
        assert os.path.isfile(PARSER), "The leaking test source was not compiled before the CI failure."
        assert not os.path.exists(REPORT), "run_ci.sh wrote a success report even though Valgrind should have failed."
    finally:
        restore(saved)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
