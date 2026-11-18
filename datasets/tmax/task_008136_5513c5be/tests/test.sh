#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import shutil
import subprocess
import tempfile

WORKSPACE = "/home/user/workspace"
SOURCE = os.path.join(WORKSPACE, "process.c")
INPUT = os.path.join(WORKSPACE, "sensor_readings.csv")
OUTPUT = os.path.join(WORKSPACE, "metrics.csv")


def test_sensor_readings_copied():
    path = INPUT
    assert os.path.isfile(path), f"File {path} does not exist. Did you copy it from /tmp/remote_data/?"


def test_c_program_exists_and_parallel():
    path = SOURCE
    assert os.path.isfile(path), f"C program source {path} does not exist."

    with open(path, 'r') as f:
        content = f.read()

    # Preserve the original source-level check for OpenMP or pthreads usage.
    has_omp = "omp.h" in content or "#pragma omp" in content
    has_pthread = "pthread.h" in content or "pthread_create" in content

    assert has_omp or has_pthread, "The C program does not appear to use OpenMP or pthreads for parallelization."


def test_metrics_output_correctness():
    path = OUTPUT
    assert os.path.isfile(path), f"Output file {path} does not exist."

    # Calculate expected values for the original fixture.
    expected = {}
    for t in range(10):
        total = 0.0
        for i in range(1, 10001):
            val = (i % 100) + t * 2.5
            total += val * val
        expected[f"T{t}"] = f"{total:.2f}"

    with open(path, 'r', newline='') as f:
        reader = list(csv.reader(f))

    assert len(reader) > 0, f"File {path} is empty."

    header = reader[0]
    assert header == ['TimeStep', 'SumOfSquares'], f"Header is incorrect. Expected ['TimeStep', 'SumOfSquares'], got {header}"

    data_rows = reader[1:]
    assert len(data_rows) == 10, f"Expected 10 data rows, got {len(data_rows)}"

    for t in range(10):
        ts = f"T{t}"
        row = data_rows[t]
        assert len(row) == 2, f"Row {t+1} does not have exactly 2 columns: {row}"
        assert row[0] == ts, f"Expected TimeStep {ts} at row {t+1}, got {row[0]}. Ensure the output is sorted."
        assert row[1] == expected[ts], f"Incorrect SumOfSquares for {ts}. Expected {expected[ts]}, got {row[1]}."


def test_compiled_program_processes_fresh_input_in_parallel():
    build_dir = tempfile.mkdtemp(prefix="process_verify_")
    executable = os.path.join(build_dir, "process_verified")
    monitor_source = os.path.join(build_dir, "parallel_monitor.c")
    monitor_library = os.path.join(build_dir, "parallel_monitor.so")
    marker = os.path.join(build_dir, "thread_created")
    input_backup = os.path.join(build_dir, "sensor_readings.csv.backup")
    output_backup = os.path.join(build_dir, "metrics.csv.backup")
    had_output = os.path.isfile(OUTPUT)

    try:
        compiled = subprocess.run(
            ["gcc", "-O2", "-fopenmp", "-pthread", SOURCE, "-lm", "-o", executable],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert compiled.returncode == 0, f"process.c did not compile successfully:\n{compiled.stderr}"
        assert os.path.isfile(executable) and os.access(executable, os.X_OK), "Compilation did not produce an executable."

        # Interpose pthread_create. GCC's OpenMP runtime also creates its worker
        # threads through pthread_create, so this observes both allowed models.
        with open(monitor_source, "w") as f:
            f.write(r'''#define _GNU_SOURCE
#include <pthread.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>

typedef int (*create_fn)(pthread_t *, const pthread_attr_t *, void *(*)(void *), void *);

int pthread_create(pthread_t *thread, const pthread_attr_t *attr,
                   void *(*start_routine)(void *), void *arg) {
    static create_fn real_create = 0;
    if (!real_create)
        real_create = (create_fn)dlsym(RTLD_NEXT, "pthread_create");
    if (!real_create)
        return EAGAIN;
    int rc = real_create(thread, attr, start_routine, arg);
    if (rc == 0) {
        const char *path = getenv("PARALLEL_MARKER");
        if (path) {
            int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
            if (fd >= 0) {
                (void)write(fd, "1", 1);
                close(fd);
            }
        }
    }
    return rc;
}
''')
        monitor_compile = subprocess.run(
            ["gcc", "-shared", "-fPIC", monitor_source, "-ldl", "-pthread", "-o", monitor_library],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert monitor_compile.returncode == 0, f"Could not build parallelism monitor:\n{monitor_compile.stderr}"

        shutil.copy2(INPUT, input_backup)
        if had_output:
            shutil.copy2(OUTPUT, output_backup)

        # Replace the fixed fixture with fresh values while retaining its 10,000-row shape.
        os.unlink(INPUT)
        expected_totals = [0.0] * 10
        with open(INPUT, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["DeviceID"] + [f"T{t}" for t in range(10)])
            for i in range(1, 10001):
                row = [i]
                for t in range(10):
                    base = ((i * (t + 3) + t * 7) % 61) - 30
                    value = base + (0.5 if (i + t) % 2 else 0.0)
                    row.append(value)
                    expected_totals[t] += value * value
                writer.writerow(row)

        if os.path.lexists(OUTPUT):
            os.unlink(OUTPUT)

        env = os.environ.copy()
        env["LD_PRELOAD"] = monitor_library
        env["PARALLEL_MARKER"] = marker
        env["OMP_NUM_THREADS"] = "4"
        env["OMP_DYNAMIC"] = "FALSE"
        run = subprocess.run(
            [executable],
            cwd=WORKSPACE,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert run.returncode == 0, f"Compiled process.c failed on fresh input:\nstdout:\n{run.stdout}\nstderr:\n{run.stderr}"
        assert os.path.isfile(marker) and os.path.getsize(marker) > 0, "The executed program did not create worker threads through OpenMP or pthreads."
        assert os.path.isfile(OUTPUT), "The executed program did not generate metrics.csv."

        with open(OUTPUT, "r", newline="") as f:
            rows = list(csv.reader(f))

        assert rows and rows[0] == ["TimeStep", "SumOfSquares"], "Generated metrics.csv has an incorrect header."
        assert len(rows) == 11, f"Generated metrics.csv must contain exactly 10 data rows, got {len(rows) - 1}."
        for t in range(10):
            expected_row = [f"T{t}", f"{expected_totals[t]:.2f}"]
            assert rows[t + 1] == expected_row, f"Fresh-input result for T{t} is incorrect: expected {expected_row}, got {rows[t + 1]}."
    finally:
        if os.path.isfile(input_backup):
            if os.path.lexists(INPUT):
                os.unlink(INPUT)
            shutil.copy2(input_backup, INPUT)
        if os.path.lexists(OUTPUT):
            os.unlink(OUTPUT)
        if had_output and os.path.isfile(output_backup):
            shutil.copy2(output_backup, OUTPUT)
        shutil.rmtree(build_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
