#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import struct
import subprocess
import tarfile
import tempfile
from collections import defaultdict

SCRIPT_PATH = "/home/user/pipeline.sh"
CPP_PATH = "/home/user/aggregate.cpp"
TARBALL_PATH = "/home/user/remote_sync/results.tar.gz"


def read_csv_from_tarball(tarball_path):
    assert os.path.isfile(tarball_path), f"Tarball {tarball_path} does not exist."
    with tempfile.TemporaryDirectory() as tmpdir:
        with tarfile.open(tarball_path, "r:gz") as tar:
            tar.extractall(path=tmpdir)

        csv_path = None
        for root, _, files in os.walk(tmpdir):
            for filename in files:
                if filename.endswith(".csv"):
                    csv_path = os.path.join(root, filename)
                    break
            if csv_path:
                break

        assert csv_path is not None, "No CSV file found in the extracted tarball."
        with open(csv_path, "r") as f:
            return f.read().strip().splitlines()


def generate_dataset(directory, file_count=10, records_per_file=1200):
    os.makedirs(directory, exist_ok=True)
    rng = random.SystemRandom()
    sensor_ids = sorted(rng.sample(range(-80, 121), 17))
    totals_in_quarters = defaultdict(int)

    for file_index in range(file_count):
        path = os.path.join(directory, f"challenge_{file_index}.bin")
        with open(path, "wb") as f:
            for _ in range(records_per_file):
                sensor_id = rng.choice(sensor_ids)
                quarter_units = rng.randint(-4000, 8000)
                totals_in_quarters[sensor_id] += quarter_units
                f.write(struct.pack("<id", sensor_id, quarter_units / 4.0))

    with open(os.path.join(directory, "ignored.txt"), "wb") as f:
        f.write(struct.pack("<id", 999999, 123456.0))

    expected = ["id,total_value"]
    for sensor_id in sorted(totals_in_quarters):
        expected.append(f"{sensor_id},{totals_in_quarters[sensor_id] / 4.0:.2f}")
    return expected


def test_pipeline_script_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_pipeline_execution_and_results():
    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, (
        f"Pipeline script failed with return code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )

    content = read_csv_from_tarball(TARBALL_PATH)
    expected_content = [
        "id,total_value",
        "1,145.00",
        "2,245.00",
        "3,345.00",
        "4,445.00",
        "5,545.00",
    ]
    assert content == expected_content, (
        f"CSV content does not match expected.\n"
        f"Expected: {expected_content}\nGot: {content}"
    )


def test_cpp_source_code():
    assert os.path.isfile(CPP_PATH), f"C++ source file {CPP_PATH} does not exist."
    with open(CPP_PATH, "r") as f:
        content = f.read()

    has_thread = "<thread>" in content or "std::thread" in content
    has_future = (
        "<future>" in content
        or "std::async" in content
        or "std::promise" in content
        or "std::packaged_task" in content
    )
    assert has_thread or has_future, (
        "C++ program does not appear to use <thread> or <future> for parallel execution."
    )


def test_pipeline_on_unpredictable_dataset():
    sensor_dir = "/home/user/sensor_data"
    for name in os.listdir(sensor_dir):
        path = os.path.join(sensor_dir, name)
        if os.path.isfile(path) or os.path.islink(path):
            os.unlink(path)

    expected = generate_dataset(sensor_dir)
    for stale in (TARBALL_PATH, "/home/user/aggregated_results.csv"):
        if os.path.lexists(stale):
            os.unlink(stale)

    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True, timeout=90)
    assert result.returncode == 0, (
        f"Pipeline failed on generated data.\nStdout: {result.stdout}\n"
        f"Stderr: {result.stderr}"
    )
    content = read_csv_from_tarball(TARBALL_PATH)
    assert content == expected, (
        f"Pipeline did not aggregate the generated binary files correctly.\n"
        f"Expected: {expected}\nGot: {content}"
    )


def test_compiled_program_processes_arguments_and_creates_threads():
    with tempfile.TemporaryDirectory() as tmpdir:
        executable = os.path.join(tmpdir, "aggregator_under_test")
        compile_result = subprocess.run(
            ["g++", "-std=c++17", "-pthread", CPP_PATH, "-o", executable],
            capture_output=True,
            text=True,
            timeout=90,
        )
        assert compile_result.returncode == 0, (
            f"aggregate.cpp could not be compiled as C++17 with threading support.\n"
            f"Stdout: {compile_result.stdout}\nStderr: {compile_result.stderr}"
        )
        assert os.path.isfile(executable) and os.access(executable, os.X_OK)

        input_dir = os.path.join(tmpdir, "input")
        expected = generate_dataset(input_dir, file_count=10, records_per_file=1400)
        output_csv = os.path.join(tmpdir, "output.csv")

        tracer_source = os.path.join(tmpdir, "thread_trace.c")
        tracer_library = os.path.join(tmpdir, "thread_trace.so")
        trace_file = os.path.join(tmpdir, "threads.log")
        with open(tracer_source, "w") as f:
            f.write(r'''#define _GNU_SOURCE
#include <pthread.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>

typedef int (*real_pthread_create_t)(pthread_t *, const pthread_attr_t *,
                                     void *(*)(void *), void *);

int pthread_create(pthread_t *thread, const pthread_attr_t *attr,
                   void *(*start_routine)(void *), void *arg) {
    static real_pthread_create_t real_create = 0;
    if (!real_create)
        real_create = (real_pthread_create_t)dlsym(RTLD_NEXT, "pthread_create");
    int result = real_create(thread, attr, start_routine, arg);
    if (result == 0) {
        const char *path = getenv("THREAD_TRACE_FILE");
        if (path) {
            int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0666);
            if (fd >= 0) {
                write(fd, "1\n", 2);
                close(fd);
            }
        }
    }
    return result;
}
''')

        tracer_compile = subprocess.run(
            ["gcc", "-shared", "-fPIC", tracer_source, "-o", tracer_library, "-ldl", "-pthread"],
            capture_output=True,
            text=True,
        )
        assert tracer_compile.returncode == 0, tracer_compile.stderr

        env = os.environ.copy()
        env["LD_PRELOAD"] = tracer_library
        env["THREAD_TRACE_FILE"] = trace_file
        run_result = subprocess.run(
            [executable, input_dir, output_csv],
            capture_output=True,
            text=True,
            env=env,
            timeout=90,
        )
        assert run_result.returncode == 0, (
            f"Compiled aggregator failed on generated input.\n"
            f"Stdout: {run_result.stdout}\nStderr: {run_result.stderr}"
        )
        assert os.path.isfile(output_csv), "Compiled aggregator did not create its requested output file."
        with open(output_csv, "r") as f:
            actual = f.read().strip().splitlines()
        assert actual == expected, (
            f"Compiled aggregate.cpp produced incorrect results.\n"
            f"Expected: {expected}\nGot: {actual}"
        )

        assert os.path.isfile(trace_file), (
            "The compiled aggregator did not create any worker thread while processing multiple files."
        )
        with open(trace_file, "r") as f:
            thread_creations = [line for line in f if line.strip()]
        assert len(thread_creations) >= 1, (
            "The compiled aggregator did not use runtime thread creation for parallel processing."
        )


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
