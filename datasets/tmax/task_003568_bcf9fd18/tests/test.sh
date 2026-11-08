#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import subprocess
import tempfile
import uuid

import pytest

CJSON_DIR = "/app/vendored/cJSON"
SCRIPT_PATH = "/home/user/filter.sh"


def run_filter(*args, cwd=None):
    try:
        return subprocess.run(
            [SCRIPT_PATH, *args],
            cwd=cwd,
            capture_output=True,
            timeout=5,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("filter.sh timed out")


def test_cjson_build_and_test():
    """Verify that cJSON really builds, its tests pass, and its library works."""
    subprocess.run(
        ["make", "clean"],
        cwd=CJSON_DIR,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    make_all = subprocess.run(
        ["make", "all"], cwd=CJSON_DIR, capture_output=True, text=True
    )
    assert make_all.returncode == 0, f"'make all' failed in {CJSON_DIR}:\n{make_all.stderr}"

    test_binary = os.path.join(CJSON_DIR, "cJSON_test")
    assert os.path.isfile(test_binary), "make all did not produce cJSON_test"
    assert os.access(test_binary, os.X_OK), "cJSON_test is not executable"

    test_run = subprocess.run(
        ["./cJSON_test"], cwd=CJSON_DIR, capture_output=True, text=True
    )
    assert test_run.returncode == 0, f"'./cJSON_test' failed in {CJSON_DIR}:\n{test_run.stderr}"

    make_test = subprocess.run(
        ["make", "test"], cwd=CJSON_DIR, capture_output=True, text=True
    )
    assert make_test.returncode == 0, f"'make test' failed in {CJSON_DIR}:\n{make_test.stderr}"

    library = os.path.join(CJSON_DIR, "libcjson.a")
    header = os.path.join(CJSON_DIR, "cJSON.h")
    assert os.path.isfile(library) and os.path.getsize(library) > 0, "make all did not produce libcjson.a"
    assert os.path.isfile(header), "cJSON.h is missing"

    # Link and run an independent consumer against the artifact produced by make.
    probe_source = r'''
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "cJSON.h"

int main(int argc, char **argv)
{
    char input[512];
    char *printed;
    cJSON *root;
    cJSON *again;
    cJSON *cpu;
    cJSON *mem;
    cJSON *status;
    double expected;

    if (argc != 3) return 20;
    expected = strtod(argv[1], NULL);
    snprintf(input, sizeof(input),
             "{\"cpu\":%s,\"mem\":%s,\"status\":\"ok\",\"samples\":[1,2,3]}",
             argv[1], argv[2]);
    root = cJSON_Parse(input);
    if (root == NULL) return 21;
    cpu = cJSON_GetObjectItemCaseSensitive(root, "cpu");
    mem = cJSON_GetObjectItemCaseSensitive(root, "mem");
    status = cJSON_GetObjectItemCaseSensitive(root, "status");
    if (!cJSON_IsNumber(cpu) || !cJSON_IsNumber(mem) || !cJSON_IsString(status)) return 22;
    if (fabs(cpu->valuedouble - expected) > 1e-9 || strcmp(status->valuestring, "ok") != 0) return 23;
    printed = cJSON_PrintUnformatted(root);
    if (printed == NULL) return 24;
    again = cJSON_Parse(printed);
    if (again == NULL) return 25;
    cJSON_Delete(again);
    free(printed);
    cJSON_Delete(root);
    if (cJSON_Parse("{\"broken\":[1,}") != NULL) return 26;
    return 0;
}
'''
    with tempfile.TemporaryDirectory(prefix="cjson-probe-") as td:
        source = os.path.join(td, "probe.c")
        binary = os.path.join(td, "probe")
        with open(source, "w", encoding="utf-8") as f:
            f.write(probe_source)
        compile_run = subprocess.run(
            ["gcc", "-std=c89", "-I", CJSON_DIR, source, library, "-lm", "-o", binary],
            capture_output=True,
            text=True,
        )
        assert compile_run.returncode == 0, f"Could not link against built cJSON library:\n{compile_run.stderr}"
        value = random.uniform(10.0, 90.0)
        probe_run = subprocess.run(
            [binary, format(value, ".12f"), str(random.randint(100, 8000))],
            capture_output=True,
            text=True,
        )
        assert probe_run.returncode == 0, f"Built cJSON library failed functional probe (status {probe_run.returncode})"


def test_filter_script_exists_and_executable():
    """Verify that the filter script exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"Filter script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Filter script at {SCRIPT_PATH} is not executable"


def test_filter_script_clean_corpus():
    """Verify that the filter script accepts all clean files."""
    clean_dir = "/app/corpora/clean"
    clean_files = glob.glob(os.path.join(clean_dir, "*"))
    assert len(clean_files) > 0, f"No files found in {clean_dir}"

    failed_files = []
    for path in clean_files:
        result = run_filter(path)
        if result.returncode != 0:
            failed_files.append(os.path.basename(path))

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(clean_files)} clean modified/rejected. "
            f"Offending files: {', '.join(failed_files)}"
        )


def test_filter_script_evil_corpus():
    """Verify that the filter script rejects all evil files."""
    evil_dir = "/app/corpora/evil"
    evil_files = glob.glob(os.path.join(evil_dir, "*"))
    assert len(evil_files) > 0, f"No files found in {evil_dir}"

    failed_files = []
    for path in evil_files:
        result = run_filter(path)
        if result.returncode != 1:
            failed_files.append(os.path.basename(path))

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(evil_files)} evil bypassed. "
            f"Offending files: {', '.join(failed_files)}"
        )


def test_filter_interface_and_unseen_inputs():
    """Exercise the required interface on newly generated, neutrally named files."""
    with tempfile.TemporaryDirectory(prefix="logs-") as td:
        cases = []

        # Fresh clean logs with values unknown until verification time.
        for _ in range(8):
            path = os.path.join(td, uuid.uuid4().hex + ".dat")
            payload = {
                "cpu": random.uniform(10.0, 90.0),
                "mem": random.randint(100, 8000),
                "status": "ok",
            }
            with open(path, "w", encoding="utf-8") as f:
                json.dump(payload, f)
            cases.append((path, 0))

        # Invalid UTF-8 in an otherwise ordinary performance log.
        path = os.path.join(td, uuid.uuid4().hex + ".dat")
        with open(path, "wb") as f:
            f.write(b'{"cpu":31.5,"mem":2048,"status":"ok","note":"\xff\xfe"}')
        cases.append((path, 1))

        # Excessively deep structure, using the same anomaly class as the corpus.
        path = os.path.join(td, uuid.uuid4().hex + ".dat")
        deep = '{"a":' * 200 + "1" + "}" * 200
        with open(path, "w", encoding="utf-8") as f:
            f.write(deep)
        cases.append((path, 1))

        # Non-finite numeric result from an extreme JSON exponent.
        path = os.path.join(td, uuid.uuid4().hex + ".dat")
        with open(path, "w", encoding="utf-8") as f:
            f.write('{"cpu":9.75e999,"mem":2048,"status":"ok"}')
        cases.append((path, 1))

        # Fresh broken serializations.
        malformed = [
            '{"cpu":42.5,"mem":1024,"status":"ok"',
            '{"cpu":42.5,"mem":1024,,"status":"ok"}',
            '{"cpu":42.5,"mem":[1,2,],"status":"ok"}',
        ]
        for payload in malformed:
            path = os.path.join(td, uuid.uuid4().hex + ".dat")
            with open(path, "w", encoding="utf-8") as f:
                f.write(payload)
            cases.append((path, 1))

        random.shuffle(cases)
        for path, expected in cases:
            result = run_filter(path)
            assert result.returncode == expected, (
                f"filter returned {result.returncode}, expected {expected}, "
                f"for generated case {os.path.basename(path)}"
            )

        # It must require exactly one argument and require that argument to be absolute.
        assert run_filter().returncode != 0, "filter accepted zero arguments"
        assert run_filter(cases[0][0], cases[1][0]).returncode != 0, "filter accepted two arguments"
        relative_name = os.path.basename(cases[0][0])
        assert run_filter(relative_name, cwd=td).returncode != 0, "filter accepted a relative path"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
