#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess

WORKSPACE_DIR = "/home/user/workspace"
MAKEFILE_PATH = os.path.join(WORKSPACE_DIR, "Makefile")
SCRIPT_PATH = os.path.join(WORKSPACE_DIR, "run_qa.sh")
MOCK_CONFIG_PATH = os.path.join(WORKSPACE_DIR, "mock_config.ini")
QA_REPORT_PATH = os.path.join(WORKSPACE_DIR, "qa_report.txt")
PROCESSOR_PATH = os.path.join(WORKSPACE_DIR, "processor")
MAIN_PATH = os.path.join(WORKSPACE_DIR, "src", "main.c")
PROBE_LOG = "/tmp/qa_processor_calls.log"
PROBE_COUNT = "/tmp/qa_processor_count"
PROBE_FAIL = "/tmp/qa_processor_fail_at"
MAKE_LOG = "/tmp/qa_make_calls.log"
WRAPPER_DIR = "/tmp/qa_verifier_bin"

EXPECTED_REPORT = (
    "BUILD: SUCCESS\n"
    "MOCK: CREATED\n"
    "PROPERTY_TESTS: 10/10 PASSED\n"
    "BENCHMARK: 5 RUNS COMPLETED"
)

PROBE_SOURCE = r'''#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

int main(void) {
    unsigned long long hash = 1469598103934665603ULL;
    size_t length = 0;
    int all_alnum = 1;
    int all_a = 1;
    char small[51];
    int ch;

    while ((ch = fgetc(stdin)) != EOF) {
        unsigned char c = (unsigned char)ch;
        if (length < 50) small[length] = (char)c;
        length++;
        if (!isalnum(c)) all_alnum = 0;
        if (c != 'A') all_a = 0;
        hash ^= c;
        hash *= 1099511628211ULL;
    }
    if (length <= 50) small[length] = '\0';

    const char *cfg = getenv("CONFIG_PATH");
    int cfg_ok = cfg && strcmp(cfg, "/home/user/workspace/mock_config.ini") == 0;

    FILE *log = fopen("/tmp/qa_processor_calls.log", "a");
    if (!log) return 97;
    fprintf(log, "%zu|%d|%d|%d|%llu|%s\n", length, all_alnum,
            all_a, cfg_ok, hash, length <= 50 ? small : "-");
    fclose(log);

    int count = 0;
    FILE *cf = fopen("/tmp/qa_processor_count", "r");
    if (cf) { fscanf(cf, "%d", &count); fclose(cf); }
    count++;
    cf = fopen("/tmp/qa_processor_count", "w");
    if (!cf) return 96;
    fprintf(cf, "%d\n", count);
    fclose(cf);

    int fail_at = 0;
    FILE *ff = fopen("/tmp/qa_processor_fail_at", "r");
    if (ff) { fscanf(ff, "%d", &fail_at); fclose(ff); }
    return count == fail_at ? 42 : 0;
}
'''


def remove_if_present(path):
    try:
        os.remove(path)
    except FileNotFoundError:
        pass


def clear_build_artifacts():
    remove_if_present(PROCESSOR_PATH)
    remove_if_present(os.path.join(WORKSPACE_DIR, "src", "main.o"))
    remove_if_present(os.path.join(WORKSPACE_DIR, "src", "utils.o"))


def reset_probe(fail_at=None):
    for path in (PROBE_LOG, PROBE_COUNT, PROBE_FAIL, MAKE_LOG):
        remove_if_present(path)
    if fail_at is not None:
        with open(PROBE_FAIL, "w") as f:
            f.write(str(fail_at) + "\n")


def run_qa():
    env = os.environ.copy()
    env["PATH"] = WRAPPER_DIR + os.pathsep + env.get("PATH", "")
    return subprocess.run(
        [SCRIPT_PATH], cwd=WORKSPACE_DIR, env=env,
        capture_output=True, text=True, timeout=120
    )


def assert_make_sequence():
    assert os.path.isfile(MAKE_LOG), "run_qa.sh did not invoke make."
    with open(MAKE_LOG) as f:
        calls = [line.rstrip("\n") for line in f]
    assert "clean" in calls, f"run_qa.sh did not invoke 'make clean'; calls were {calls!r}"
    clean_index = calls.index("clean")
    assert "" in calls[clean_index + 1:], (
        f"run_qa.sh did not invoke plain 'make' after 'make clean'; calls were {calls!r}"
    )


def read_probe_records():
    assert os.path.isfile(PROBE_LOG), "The built processor was never executed."
    records = []
    with open(PROBE_LOG) as f:
        for line in f:
            parts = line.rstrip("\n").split("|", 5)
            assert len(parts) == 6, f"Malformed processor probe record: {line!r}"
            records.append({
                "length": int(parts[0]),
                "alnum": parts[1] == "1",
                "all_a": parts[2] == "1",
                "cfg_ok": parts[3] == "1",
                "hash": parts[4],
                "sample": parts[5],
            })
    return records


def test_final_state_and_qa_behavior():
    # Preserve the original verifier's Makefile assertions.
    assert os.path.isfile(MAKEFILE_PATH), f"Makefile {MAKEFILE_PATH} is missing."
    with open(MAKEFILE_PATH) as f:
        lines = f.readlines()
    for line in lines:
        if line.startswith("processor:"):
            deps = line.strip().split(':')[1].split()
            assert "processor" not in deps, "Makefile still contains circular dependency for 'processor'."
        if line.startswith("src/main.o:"):
            deps = line.strip().split(':')[1].split()
            assert "src/main.o" not in deps, "Makefile still contains circular dependency for 'src/main.o'."

    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} is missing."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

    with open(MAIN_PATH, "rb") as f:
        original_main = f.read()

    os.makedirs(WRAPPER_DIR, exist_ok=True)
    make_wrapper = os.path.join(WRAPPER_DIR, "make")
    with open(make_wrapper, "w") as f:
        f.write("#!/bin/bash\nprintf '%s\\n' \"$*\" >> /tmp/qa_make_calls.log\nexec /usr/bin/make \"$@\"\n")
    os.chmod(make_wrapper, 0o755)

    try:
        # Build an instrumented processor so executions and their actual stdin are
        # independently observable rather than inferred from qa_report.txt.
        with open(MAIN_PATH, "w") as f:
            f.write(PROBE_SOURCE)
        clear_build_artifacts()
        for path in (MOCK_CONFIG_PATH, QA_REPORT_PATH):
            remove_if_present(path)
        reset_probe()

        result = run_qa()
        assert result.returncode == 0, (
            f"run_qa.sh failed with exit code {result.returncode}.\n"
            f"Stdout:\n{result.stdout}\nStderr:\n{result.stderr}"
        )
        assert_make_sequence()

        # Preserve the original artifact assertions.
        assert os.path.isfile(MOCK_CONFIG_PATH), f"Mock config {MOCK_CONFIG_PATH} was not created."
        with open(MOCK_CONFIG_PATH) as f:
            content = f.read()
        assert content == "MULTIPLIER=5\n", f"Mock config content is incorrect. Got: {content!r}"

        assert os.path.isfile(QA_REPORT_PATH), f"QA report {QA_REPORT_PATH} was not created."
        with open(QA_REPORT_PATH) as f:
            report = f.read().strip()
        assert report == EXPECTED_REPORT, f"QA report content is incorrect. Got:\n{report}"

        assert os.path.isfile(PROCESSOR_PATH), f"Processor binary {PROCESSOR_PATH} was not built."
        assert os.access(PROCESSOR_PATH, os.X_OK), f"Processor binary {PROCESSOR_PATH} is not executable."

        records = read_probe_records()
        assert len(records) == 15, (
            f"Expected exactly 10 property executions and 5 benchmark executions, got {len(records)}."
        )
        properties = records[:10]
        benchmarks = records[10:]
        for i, rec in enumerate(properties, 1):
            assert 10 <= rec["length"] <= 50, f"Property input {i} has invalid length {rec['length']}."
            assert rec["alnum"], f"Property input {i} was not purely alphanumeric."
            assert rec["cfg_ok"], f"Property execution {i} did not use the required CONFIG_PATH."
        samples = [rec["sample"] for rec in properties]
        assert len(set(samples)) == 10, "The 10 property-test strings were not all different."

        for i, rec in enumerate(benchmarks, 1):
            assert rec["length"] == 100000, f"Benchmark input {i} had length {rec['length']}, not 100000."
            assert rec["all_a"], f"Benchmark input {i} was not exactly 100,000 copies of 'A'."
            assert rec["cfg_ok"], f"Benchmark execution {i} did not use the required CONFIG_PATH."

        # Force the first property execution to fail and independently verify that
        # the script propagates failure and suppresses the success report.
        remove_if_present(QA_REPORT_PATH)
        clear_build_artifacts()
        reset_probe(fail_at=1)
        failed = run_qa()
        assert failed.returncode != 0, "run_qa.sh ignored a failing property-test execution."
        assert not os.path.exists(QA_REPORT_PATH), (
            "run_qa.sh wrote the success report after a property test failed."
        )
        failure_records = read_probe_records()
        assert failure_records, "No processor execution occurred in the property-failure test."
        assert 10 <= failure_records[0]["length"] <= 50 and failure_records[0]["alnum"], (
            "The first tested execution was not a valid property-test input."
        )

        # Also ensure a real compilation failure cannot be hidden by directly
        # writing the self-reported success file.
        with open(MAIN_PATH, "w") as f:
            f.write("this is intentionally invalid C source\n")
        remove_if_present(QA_REPORT_PATH)
        clear_build_artifacts()
        reset_probe()
        build_failed = run_qa()
        assert build_failed.returncode != 0, "run_qa.sh did not propagate a compilation failure."
        assert not os.path.exists(QA_REPORT_PATH), (
            "run_qa.sh wrote the success report after compilation failed."
        )
        assert_make_sequence()
    finally:
        with open(MAIN_PATH, "wb") as f:
            f.write(original_main)
        for path in (PROBE_LOG, PROBE_COUNT, PROBE_FAIL, MAKE_LOG):
            remove_if_present(path)
        shutil.rmtree(WRAPPER_DIR, ignore_errors=True)
        subprocess.run(["/usr/bin/make", "clean"], cwd=WORKSPACE_DIR,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["/usr/bin/make"], cwd=WORKSPACE_DIR,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
