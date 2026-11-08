#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PYTEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile

REPO_DIR = "/home/user/fast-telemetry"
TEST_RESULTS_LOG = "/home/user/test_results.log"


def test_branch_checked_out():
    """Ensure the correct branch is checked out."""
    result = subprocess.run(
        ["git", "rev-parse", "--abbrev-ref", "HEAD"],
        cwd=REPO_DIR,
        capture_output=True,
        text=True,
        check=True,
    )
    branch = result.stdout.strip()
    assert branch == "pr-104-fast-delta", \
        f"Expected branch 'pr-104-fast-delta', but got '{branch}'"


def test_test_results_log():
    """Ensure test_results.log exists and contains 'ALL TESTS PASSED'."""
    assert os.path.isfile(TEST_RESULTS_LOG), f"{TEST_RESULTS_LOG} does not exist."
    with open(TEST_RESULTS_LOG, "r") as f:
        content = f.read()
    assert "ALL TESTS PASSED" in content, \
        f"'{TEST_RESULTS_LOG}' does not contain 'ALL TESTS PASSED'."


def test_delta_calc_fixed():
    """Ensure delta_calc.c uses inline subl instead of addl."""
    delta_calc_path = os.path.join(REPO_DIR, "src", "delta_calc.c")
    assert os.path.isfile(delta_calc_path), f"{delta_calc_path} does not exist."
    with open(delta_calc_path, "r") as f:
        content = f.read()
    assert "subl" in content, \
        "delta_calc.c does not contain 'subl'. The assembly was not fixed."
    assert "addl" not in content.split("//")[0], \
        "delta_calc.c still contains 'addl' in the assembly."

    stripped = re.sub(r"/\*.*?\*/", "", content, flags=re.S)
    stripped = re.sub(r"//.*", "", stripped)
    assert re.search(
        r"(?:__asm__|__asm|asm)\s*(?:__volatile__|volatile)?\s*\(.{0,500}subl",
        stripped,
        flags=re.S,
    ), "The subl instruction is not present in an inline assembly block."


def test_make_test_passes():
    """Ensure 'make test' compiles and runs successfully."""
    subprocess.run(["make", "clean"], cwd=REPO_DIR, check=True)
    result = subprocess.run(
        ["make", "test"],
        cwd=REPO_DIR,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, \
        f"'make test' failed with output:\n{result.stdout}\n{result.stderr}"
    assert "ALL TESTS PASSED" in result.stdout, \
        "'make test' output does not contain 'ALL TESTS PASSED'."


def test_mock_sink_used():
    """Ensure tests/test_main.c uses mock_output and not the real sink path."""
    test_main_path = os.path.join(REPO_DIR, "tests", "test_main.c")
    assert os.path.isfile(test_main_path), f"{test_main_path} does not exist."
    with open(test_main_path, "r") as f:
        content = f.read()
    assert "mock_output" in content, \
        "test_main.c does not contain 'mock_output' as requested."
    assert "/etc/telemetry.log" not in content, \
        "test_main.c still contains references to '/etc/telemetry.log'."


def test_independent_library_and_mock_behavior():
    """Compile and exercise the submitted sources independently of their tests."""
    harness = r'''
#include "telemetry.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define main agent_test_main
#include "/home/user/fast-telemetry/tests/test_main.c"
#undef main

static int fail(const char *message) {
    fprintf(stderr, "%s\n", message);
    return 1;
}

int main(void) {
    /* Run fixture setup, including any mock assignment performed in its main. */
    if (agent_test_main() != 0)
        return fail("submitted test fixture returned failure");

    mock_output[0] = '\0';
    flush_telemetry("fixture-");
    flush_telemetry("mock");
    if (strcmp(mock_output, "fixture-mock") != 0)
        return fail("write_sink does not append telemetry to mock_output");

    int32_t curr[257], prev[257], out[257];
    uint32_t state = 0x91e10da5u;
    for (size_t i = 0; i < 257; ++i) {
        state = state * 1664525u + 1013904223u;
        curr[i] = (int32_t)(state % 2000001u) - 1000000;
        state = state * 1664525u + 1013904223u;
        prev[i] = (int32_t)(state % 2000001u) - 1000000;
        out[i] = 0x12345678;
    }
    compute_deltas(curr, prev, out, 257);
    for (size_t i = 0; i < 257; ++i) {
        int32_t expected = curr[i] - prev[i];
        if (out[i] != expected)
            return fail("compute_deltas produced an incorrect result");
    }

    int32_t storage[4] = {0};
    CircularDeltaBuffer cb = {storage, 0, 0, 4, false};
    int32_t value = 0;
    if (pop_buffer(&cb, &value))
        return fail("pop_buffer succeeded on an empty buffer");
    for (int32_t i = 1; i <= 4; ++i)
        if (!push_buffer(&cb, i))
            return fail("push_buffer rejected an available slot");
    if (push_buffer(&cb, 99))
        return fail("push_buffer succeeded on a full buffer");
    for (int32_t i = 1; i <= 2; ++i)
        if (!pop_buffer(&cb, &value) || value != i)
            return fail("pop_buffer violated FIFO order");
    if (!push_buffer(&cb, 5) || !push_buffer(&cb, 6))
        return fail("push_buffer failed after wraparound");
    if (push_buffer(&cb, 100))
        return fail("wrapped buffer did not report full");
    for (int32_t expected = 3; expected <= 6; ++expected)
        if (!pop_buffer(&cb, &value) || value != expected)
            return fail("wrapped buffer violated FIFO order");
    if (pop_buffer(&cb, &value))
        return fail("buffer did not report empty after all values were popped");

    int32_t single_storage[1] = {0};
    CircularDeltaBuffer single = {single_storage, 0, 0, 1, false};
    if (!push_buffer(&single, -77) || push_buffer(&single, 8))
        return fail("single-element buffer full handling is incorrect");
    if (!pop_buffer(&single, &value) || value != -77 || pop_buffer(&single, &value))
        return fail("single-element buffer pop handling is incorrect");

    char config_path[160];
    int expected_size = 1000 + (int)(getpid() % 50000);
    snprintf(config_path, sizeof(config_path),
             "/tmp/fast_telemetry_config_%ld.cfg", (long)getpid());
    FILE *config = fopen(config_path, "w");
    if (!config)
        return fail("could not create verifier config file");
    fprintf(config, "\nIGNORED_KEY=abc\nMAX_BUFFER_SIZE=%d\nOTHER=9\n\n",
            expected_size);
    if (fclose(config) != 0)
        return fail("could not finish verifier config file");

    Config cfg;
    cfg.max_buffer_size = -12345;
    if (parse_config(config_path, &cfg) != 0)
        return fail("parse_config rejected a valid config");
    unlink(config_path);
    if (cfg.max_buffer_size != expected_size)
        return fail("parse_config extracted the wrong MAX_BUFFER_SIZE");

    snprintf(config_path, sizeof(config_path),
             "/tmp/fast_telemetry_missing_%ld.cfg", (long)getpid());
    unlink(config_path);
    if (parse_config(config_path, &cfg) != -1)
        return fail("parse_config did not fail for a nonexistent file");

    return 0;
}
'''
    with tempfile.TemporaryDirectory(prefix="fast-telemetry-verifier-") as tmp:
        harness_path = os.path.join(tmp, "harness.c")
        executable = os.path.join(tmp, "harness")
        with open(harness_path, "w") as f:
            f.write(harness)

        compile_result = subprocess.run(
            [
                "gcc", "-std=gnu11", "-O2", "-Wall", "-Wextra",
                "-I", os.path.join(REPO_DIR, "include"),
                harness_path,
                os.path.join(REPO_DIR, "src", "delta_calc.c"),
                os.path.join(REPO_DIR, "src", "buffer.c"),
                os.path.join(REPO_DIR, "src", "config.c"),
                "-o", executable,
            ],
            cwd=REPO_DIR,
            capture_output=True,
            text=True,
        )
        assert compile_result.returncode == 0, \
            f"Independent harness failed to compile:\n{compile_result.stdout}\n{compile_result.stderr}"

        result = subprocess.run(
            [executable],
            cwd=REPO_DIR,
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, \
            f"Independent behavior checks failed:\n{result.stdout}\n{result.stderr}"
PYTEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
