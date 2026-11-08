#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shutil
import string
import subprocess
import tempfile

LOG_PARSER_DIR = "/home/user/log_parser"
ANOMALY_FILE = os.path.join(LOG_PARSER_DIR, "anomaly_line.txt")
PARSER_SOURCE = os.path.join(LOG_PARSER_DIR, "parser.c")
PARSER_BIN = os.path.join(LOG_PARSER_DIR, "parser")
LOGS_FILE = os.path.join(LOG_PARSER_DIR, "logs.txt")
REGRESSION_TEST = os.path.join(LOG_PARSER_DIR, "regression_test.py")


def test_anomaly_line_correct():
    assert os.path.isfile(ANOMALY_FILE), f"{ANOMALY_FILE} is missing."
    with open(ANOMALY_FILE, "r") as f:
        content = f.read().strip()
    assert content == "4200", f"Expected anomaly line to be '4200', but got '{content}'."


def test_parser_fixed_and_runs():
    assert os.path.isfile(PARSER_BIN), f"{PARSER_BIN} is missing."
    assert os.access(PARSER_BIN, os.X_OK), f"{PARSER_BIN} is not executable."

    result = subprocess.run([PARSER_BIN, LOGS_FILE], capture_output=True)
    assert result.returncode == 0, (
        f"Parser crashed or failed on {LOGS_FILE}. Exit code: {result.returncode}"
    )

    username = "".join(random.SystemRandom().choice(string.ascii_letters) for _ in range(100))
    with tempfile.NamedTemporaryFile("w", delete=False) as f:
        f.write(f"INFO User:{username} Action:VERIFY\n")
        generated_log = f.name
    try:
        result = subprocess.run([PARSER_BIN, generated_log], capture_output=True)
        assert result.returncode == 0, (
            "Submitted parser failed on a verifier-generated 100-character username. "
            f"Exit code: {result.returncode}"
        )
    finally:
        os.unlink(generated_log)


def test_parser_source_actually_parses_and_truncates():
    assert os.path.isfile(PARSER_SOURCE), f"{PARSER_SOURCE} is missing."
    assert not os.path.islink(PARSER_SOURCE), f"{PARSER_SOURCE} must be a regular source file."

    with open(PARSER_SOURCE, "r", encoding="utf-8") as f:
        source = f.read()

    function_match = re.search(r"\bprocess_log\s*\([^)]*\)\s*\{", source)
    assert function_match, "parser.c must contain the process_log function."

    opening_brace = source.find("{", function_match.start())
    depth = 0
    closing_brace = None
    for index in range(opening_brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                closing_brace = index
                break
    assert closing_brace is not None, "Could not locate the end of process_log."

    function_body = source[opening_brace:closing_brace]
    buffer_match = re.search(r"\bchar\s+([A-Za-z_]\w*)\s*\[\s*32\s*\]", function_body)
    assert buffer_match, "process_log must retain and safely use a 32-byte username buffer."
    username_var = buffer_match.group(1)

    injection = f'''
    fwrite("__LP_BEGIN__", 1, 12, stdout);
    fwrite({username_var}, 1, sizeof({username_var}), stdout);
    fwrite("__LP_END__", 1, 10, stdout);
'''
    instrumented_source = source[:closing_brace] + injection + source[closing_brace:]

    username = "".join(random.SystemRandom().choice(string.ascii_letters) for _ in range(100))
    expected_buffer = username[:31].encode("ascii") + b"\0"

    with tempfile.TemporaryDirectory() as temp_dir:
        source_path = os.path.join(temp_dir, "instrumented_parser.c")
        binary_path = os.path.join(temp_dir, "instrumented_parser")
        input_path = os.path.join(temp_dir, "challenge.log")

        with open(source_path, "w", encoding="utf-8") as f:
            f.write(instrumented_source)
        with open(input_path, "w", encoding="utf-8") as f:
            f.write(f"INFO User:{username} Action:VERIFY\n")

        compile_result = subprocess.run(
            [
                "gcc", "-O0", "-g", "-fsanitize=address", "-fno-omit-frame-pointer",
                "-o", binary_path, source_path,
            ],
            capture_output=True,
        )
        assert compile_result.returncode == 0, (
            "The submitted parser.c did not compile under the verifier.\n"
            f"stdout: {compile_result.stdout.decode(errors='replace')}\n"
            f"stderr: {compile_result.stderr.decode(errors='replace')}"
        )

        env = os.environ.copy()
        env["ASAN_OPTIONS"] = "detect_leaks=0:halt_on_error=1"
        run_result = subprocess.run(
            [binary_path, input_path], capture_output=True, env=env
        )
        assert run_result.returncode == 0, (
            "The parser built from parser.c crashed or accessed memory unsafely on a "
            "verifier-generated long username.\n"
            f"stderr: {run_result.stderr.decode(errors='replace')}"
        )

        begin = run_result.stdout.find(b"__LP_BEGIN__")
        end = run_result.stdout.find(b"__LP_END__", begin + 12)
        assert begin >= 0 and end >= 0, "Could not observe the username buffer after parsing."
        observed_buffer = run_result.stdout[begin + 12:end]
        assert observed_buffer == expected_buffer, (
            "parser.c did not parse the generated username into the 32-byte buffer, "
            "truncate it to exactly 31 characters, and append a null terminator."
        )


def test_regression_test_passes():
    assert os.path.isfile(REGRESSION_TEST), f"{REGRESSION_TEST} is missing."

    result = subprocess.run(
        ["python3", REGRESSION_TEST], cwd=LOG_PARSER_DIR, capture_output=True
    )
    assert result.returncode == 0, (
        f"Regression test failed. Exit code: {result.returncode}\n"
        f"Stdout: {result.stdout.decode()}\nStderr: {result.stderr.decode()}"
    )


def test_regression_test_fails_on_vulnerable_parser():
    vulnerable_c_code = r'''#include <stdio.h>
#include <string.h>

void process_log(const char *log_line) {
    char username[32];
    const char *user_ptr = strstr(log_line, "User:");
    if (user_ptr) {
        user_ptr += 5;
        const char *space_ptr = strchr(user_ptr, ' ');
        if (space_ptr) {
            int len = space_ptr - user_ptr;
            for(int i = 0; i < len; i++) {
                username[i] = user_ptr[i];
            }
            username[len] = '\0';
        }
    }
}

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    char line[1024];
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    while (fgets(line, sizeof(line), f)) {
        process_log(line);
    }
    fclose(f);
    return 0;
}
'''
    backup_bin = PARSER_BIN + ".bak"
    if os.path.exists(PARSER_BIN):
        shutil.copy2(PARSER_BIN, backup_bin)

    try:
        vuln_c = os.path.join(LOG_PARSER_DIR, "vuln_parser_test.c")
        with open(vuln_c, "w") as f:
            f.write(vulnerable_c_code)

        compile_res = subprocess.run(
            ["gcc", "-O0", "-fno-stack-protector", "-o", PARSER_BIN, vuln_c],
            capture_output=True,
        )
        assert compile_res.returncode == 0, "Failed to compile vulnerable parser for testing."

        result = subprocess.run(
            ["python3", REGRESSION_TEST], cwd=LOG_PARSER_DIR, capture_output=True
        )
        assert result.returncode == 1, (
            "Regression test should have failed (exit code 1) with vulnerable parser, "
            f"but it returned {result.returncode}."
        )
    finally:
        if os.path.exists(backup_bin):
            shutil.move(backup_bin, PARSER_BIN)
        if os.path.exists(os.path.join(LOG_PARSER_DIR, "vuln_parser_test.c")):
            os.remove(os.path.join(LOG_PARSER_DIR, "vuln_parser_test.c"))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
