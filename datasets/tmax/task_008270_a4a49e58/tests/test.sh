#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import stat
import subprocess
import tarfile

import pytest

PROJECT_DIR = "/home/user/project"
SCRIPT_FILE = os.path.join(PROJECT_DIR, "ci_pipeline.sh")
GENERATOR_SOURCE = os.path.join(PROJECT_DIR, "generator.c")
PROCESSOR_SOURCE = os.path.join(PROJECT_DIR, "processor.go")
CONFIG_FILE = os.path.join(PROJECT_DIR, "config.json")
GENERATOR_BIN = os.path.join(PROJECT_DIR, "generator")
PROCESSOR_BIN = os.path.join(PROJECT_DIR, "processor")
TARBALL_FILE = os.path.join(PROJECT_DIR, "release.tar.gz")
RESULT_FILE = os.path.join(PROJECT_DIR, "benchmark_result.json")

EXPECTED_GENERATOR = '''#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    int count = atoi(argv[1]);
    for (int i = 0; i < count; i++) {
        printf("%d\\n", i);
    }
    return 0;
}
'''

EXPECTED_PROCESSOR = '''package main

import (
\t"bufio"
\t"fmt"
\t"os"
\t"strconv"
)

func main() {
\tscanner := bufio.NewScanner(os.Stdin)
\tsum := int64(0)
\tfor scanner.Scan() {
\t\tval, _ := strconv.ParseInt(scanner.Text(), 10, 64)
\t\tsum += val
\t}
\tfmt.Println(sum)
}
'''

INSTRUMENTED_GENERATOR = r'''#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    int count = atoi(argv[1]);
    FILE *log = fopen("/tmp/verifier_generator.log", "a");
    if (!log) return 2;
    fprintf(log, "%d\n", count);
    fclose(log);
    for (int i = 0; i < count; i++) printf("%d\n", i);
    return 0;
}
'''

INSTRUMENTED_PROCESSOR = r'''package main

import (
    "bufio"
    "fmt"
    "os"
    "strconv"
    "time"
)

func main() {
    scanner := bufio.NewScanner(os.Stdin)
    count := 0
    sum := int64(0)
    valid := true
    for scanner.Scan() {
        val, err := strconv.Atoi(scanner.Text())
        if err != nil || val != count { valid = false }
        sum += int64(val)
        count++
    }
    if err := scanner.Err(); err != nil { valid = false }
    if !valid { os.Exit(3) }

    delay := 50
    if count == 17 { delay = 250 }
    if count == 23 { delay = 1300 }
    time.Sleep(time.Duration(delay) * time.Millisecond)

    log, err := os.OpenFile("/tmp/verifier_processor.log", os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0666)
    if err != nil { os.Exit(4) }
    fmt.Fprintf(log, "%d %d\n", count, sum)
    log.Close()
    fmt.Println(sum)
}
'''


def run_pipeline_script(timeout=180):
    return subprocess.run(
        [SCRIPT_FILE],
        cwd=PROJECT_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
        env=os.environ.copy(),
    )


def read_result():
    assert os.path.isfile(RESULT_FILE), f"Benchmark result {RESULT_FILE} missing."
    with open(RESULT_FILE) as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{RESULT_FILE} is not valid JSON.")


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_FILE), f"Script {SCRIPT_FILE} does not exist."
    st = os.stat(SCRIPT_FILE)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_FILE} is not executable."


def test_pipeline_execution_config_parsing_run_count_and_timing():
    with open(GENERATOR_SOURCE) as f:
        assert f.read() == EXPECTED_GENERATOR, "generator.c was modified."
    with open(PROCESSOR_SOURCE) as f:
        assert f.read() == EXPECTED_PROCESSOR, "processor.go was modified."

    with open(CONFIG_FILE, "rb") as f:
        original_config = f.read()

    low_average = None
    high_average = None
    try:
        with open(GENERATOR_SOURCE, "w") as f:
            f.write(INSTRUMENTED_GENERATOR)
        with open(PROCESSOR_SOURCE, "w") as f:
            f.write(INSTRUMENTED_PROCESSOR)

        cases = [
            (2, 17, 250, "17 136"),
            (3, 23, 1300, "23 253"),
        ]
        for runs, count, delay, expected_processor_line in cases:
            for path in (GENERATOR_BIN, PROCESSOR_BIN, TARBALL_FILE, RESULT_FILE,
                         "/tmp/verifier_generator.log", "/tmp/verifier_processor.log"):
                try:
                    os.remove(path)
                except FileNotFoundError:
                    pass

            with open(CONFIG_FILE, "w") as f:
                json.dump({"runs": runs, "count": count}, f)

            completed = run_pipeline_script()
            assert completed.returncode == 0, (
                f"ci_pipeline.sh failed for runs={runs}, count={count}.\n"
                f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
            )

            with open("/tmp/verifier_generator.log") as f:
                generator_calls = [line.strip() for line in f if line.strip()]
            with open("/tmp/verifier_processor.log") as f:
                processor_calls = [line.strip() for line in f if line.strip()]

            assert generator_calls == [str(count)] * runs, (
                "generator was not invoked exactly 'runs' times with the parsed count"
            )
            assert processor_calls == [expected_processor_line] * runs, (
                "processor was not invoked exactly 'runs' times on the generator output"
            )

            data = read_result()
            assert set(data.keys()) == {"average_ms", "status"}, "Benchmark JSON has unexpected structure."
            assert data["status"] == "success"
            assert isinstance(data["average_ms"], int) and not isinstance(data["average_ms"], bool), (
                "average_ms must be a JSON integer"
            )
            average = data["average_ms"]
            if delay == 250:
                assert 150 <= average <= 1000, f"Measured average {average}ms is inconsistent with the 250ms runs."
                low_average = average
            else:
                assert 1050 <= average <= 3500, f"Measured average {average}ms is inconsistent with the 1300ms runs."
                high_average = average

        assert high_average - low_average >= 500, (
            "average_ms did not respond to the controlled change in pipeline execution time"
        )
    finally:
        with open(GENERATOR_SOURCE, "w") as f:
            f.write(EXPECTED_GENERATOR)
        with open(PROCESSOR_SOURCE, "w") as f:
            f.write(EXPECTED_PROCESSOR)
        with open(CONFIG_FILE, "wb") as f:
            f.write(original_config)

        # Rebuild and benchmark the real, unmodified application so all final-state
        # checks below apply to the requested artifacts rather than test instruments.
        completed = run_pipeline_script()
        assert completed.returncode == 0, (
            "ci_pipeline.sh failed on the original sources/config after behavioral testing.\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )


def test_binaries_exist():
    assert os.path.isfile(GENERATOR_BIN), f"Binary {GENERATOR_BIN} was not built."
    assert os.path.isfile(PROCESSOR_BIN), f"Binary {PROCESSOR_BIN} was not built."


def test_generator_is_statically_linked():
    assert os.path.isfile(GENERATOR_BIN), "Generator binary missing."
    try:
        result = subprocess.run(
            ["ldd", GENERATOR_BIN], stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True
        )
    except FileNotFoundError:
        pytest.fail("ldd command not found to verify static linking.")
    output = result.stdout
    assert "not a dynamic executable" in output, \
        f"generator is not statically linked. ldd output: {output.strip()}"


def test_processor_is_statically_linked():
    assert os.path.isfile(PROCESSOR_BIN), "Processor binary missing."
    try:
        result = subprocess.run(
            ["ldd", PROCESSOR_BIN], stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True
        )
    except FileNotFoundError:
        pytest.fail("ldd command not found to verify static linking.")
    output = result.stdout
    assert "not a dynamic executable" in output, \
        f"processor is not statically linked. ldd output: {output.strip()}"


def test_real_binaries_execute_and_pipeline_output_is_correct():
    generated = subprocess.run(
        [GENERATOR_BIN, "10"], cwd=PROJECT_DIR,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert generated.returncode == 0, generated.stderr
    assert generated.stdout == "".join(f"{i}\n" for i in range(10))

    processed = subprocess.run(
        [PROCESSOR_BIN], cwd=PROJECT_DIR, input="1\n2\n3\n4\n",
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert processed.returncode == 0, processed.stderr
    assert processed.stdout.strip() == "10"

    pipeline = subprocess.run(
        ["bash", "-c", "./generator 100 | ./processor"], cwd=PROJECT_DIR,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert pipeline.returncode == 0, pipeline.stderr
    assert pipeline.stdout.strip() == str(100 * 99 // 2)


def test_release_tarball():
    assert os.path.isfile(TARBALL_FILE), f"Tarball {TARBALL_FILE} missing."
    try:
        with tarfile.open(TARBALL_FILE, "r:gz") as tar:
            members = tar.getmembers()
            names_bases = [os.path.basename(m.name) for m in members]
            assert "generator" in names_bases, "generator binary not found in release.tar.gz"
            assert "processor" in names_bases, "processor binary not found in release.tar.gz"
            assert names_bases.count("generator") == 1
            assert names_bases.count("processor") == 1
            for basename, disk_path in (("generator", GENERATOR_BIN), ("processor", PROCESSOR_BIN)):
                member = next(m for m in members if os.path.basename(m.name) == basename)
                assert member.isfile(), f"{basename} in release.tar.gz is not a regular file"
                archived = tar.extractfile(member).read()
                with open(disk_path, "rb") as f:
                    assert archived == f.read(), f"Archived {basename} does not match the built binary"
    except tarfile.ReadError:
        pytest.fail(f"{TARBALL_FILE} is not a valid gzip-compressed tarball.")


def test_benchmark_result():
    data = read_result()
    assert "status" in data, "JSON missing 'status' key."
    assert data["status"] == "success", f"Expected status 'success', got '{data['status']}'"
    assert "average_ms" in data, "JSON missing 'average_ms' key."
    val = data["average_ms"]
    assert isinstance(val, int) or (isinstance(val, float) and val.is_integer()) or (isinstance(val, str) and val.isdigit()), \
        f"average_ms should be a valid integer, got {val}"
    assert set(data.keys()) == {"average_ms", "status"}, "JSON must contain exactly average_ms and status."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
