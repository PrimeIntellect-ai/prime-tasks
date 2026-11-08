#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_event_service.py
import os
import random
import subprocess
import tempfile

import pytest

WORKSPACE_DIR = "/home/user/event_service"
FINAL_STATE_FILE = "/home/user/final_state.txt"
BACKLOG_FILE = os.path.join(WORKSPACE_DIR, "backlog.txt")
MAIN_BINARY = os.path.join(WORKSPACE_DIR, "event_processor")
TEST_BINARY = os.path.join(WORKSPACE_DIR, "test_runner")
REGRESSION_SOURCE = os.path.join(WORKSPACE_DIR, "src", "test_regression.cpp")
SOURCE_BINARY = "/tmp/source_event_processor"


def run(command, cwd=WORKSPACE_DIR, timeout=20, env=None):
    return subprocess.run(
        command,
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=timeout,
        env=env,
    )


def assert_elf_executable(path):
    assert os.path.isfile(path), f"Expected binary {path} is missing."
    assert os.access(path, os.X_OK), f"Expected binary {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not an ELF binary."


def compute_expected_sums(backlog_path):
    if not os.path.isfile(backlog_path):
        return []

    buffer_abs = [0] * 10
    buffer_mod = [0] * 10
    with open(backlog_path, "r") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) == 2:
                event_id = int(parts[0])
                val = int(parts[1])
                buffer_abs[abs(event_id) % 10] = val
                buffer_mod[event_id % 10] = val
    return [sum(buffer_abs), sum(buffer_mod)]


def expected_wrapped_output(events):
    buffer = [0] * 10
    for event_id, value in events:
        buffer[event_id % 10] = value
    return f"Final Sum: {sum(buffer)}"


def execute_with_events(binary, events):
    fd, path = tempfile.mkstemp(prefix="events_", suffix=".txt")
    try:
        with os.fdopen(fd, "w") as f:
            for event_id, value in events:
                f.write(f"{event_id} {value}\n")
        result = run([binary, path])
        assert result.returncode == 0, (
            f"{binary} failed on generated events.\n"
            f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )
        assert result.stdout.strip() == expected_wrapped_output(events), (
            f"Incorrect ring-buffer result for generated events {events}. "
            f"Got {result.stdout.strip()!r}."
        )
    finally:
        if os.path.exists(path):
            os.unlink(path)


def test_make_compiles_cleanly():
    assert os.path.isdir(WORKSPACE_DIR), f"Workspace directory {WORKSPACE_DIR} is missing."

    clean = run(["make", "clean"])
    assert clean.returncode == 0, (
        f"'make clean' failed.\nSTDOUT:\n{clean.stdout}\nSTDERR:\n{clean.stderr}"
    )

    result = run(["make"])
    assert result.returncode == 0, (
        f"'make' failed to compile cleanly.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
    assert_elf_executable(MAIN_BINARY)


def test_make_test_runs_successfully():
    assert os.path.isfile(REGRESSION_SOURCE), f"Regression source {REGRESSION_SOURCE} is missing."

    result = run(["make", "test"])
    assert result.returncode == 0, (
        f"'make test' failed.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
    assert_elf_executable(TEST_BINARY)

    rerun = run([TEST_BINARY])
    assert rerun.returncode == 0, (
        f"test_runner does not pass when executed directly.\n"
        f"STDOUT:\n{rerun.stdout}\nSTDERR:\n{rerun.stderr}"
    )


def test_regression_test_exercises_negative_id():
    marker = os.path.join(tempfile.gettempdir(), f"negative_event_{os.getpid()}")
    mock_source = "/tmp/mock_processor.cpp"
    mock_binary = "/tmp/regression_with_mock"
    if os.path.exists(marker):
        os.unlink(marker)

    with open(mock_source, "w") as f:
        f.write(r'''#include "processor.h"
#include <cstdlib>
#include <fstream>

EventProcessor::EventProcessor() : count(0) {
    for (int i = 0; i < 10; ++i) buffer[i] = 0;
}

void EventProcessor::add_event(int event_id, int value) {
    if (event_id < 0) {
        const char* marker = std::getenv("VERIFIER_NEGATIVE_MARKER");
        if (marker) {
            std::ofstream out(marker);
            out << event_id;
        }
    }
    int index = ((event_id % 10) + 10) % 10;
    buffer[index] = value;
    ++count;
}

int EventProcessor::get_sum() const {
    int sum = 0;
    for (int i = 0; i < 10; ++i) sum += buffer[i];
    return sum;
}
''')

    compile_result = run([
        "g++", "-std=c++17", "-Wall", "-Wextra", "-I", "src",
        REGRESSION_SOURCE, mock_source, "-o", mock_binary,
    ])
    assert compile_result.returncode == 0, (
        "test_regression.cpp could not be independently compiled.\n"
        f"STDOUT:\n{compile_result.stdout}\nSTDERR:\n{compile_result.stderr}"
    )

    env = os.environ.copy()
    env["VERIFIER_NEGATIVE_MARKER"] = marker
    result = run([mock_binary], env=env)
    assert result.returncode == 0, "The independently compiled regression test failed."
    assert os.path.isfile(marker), (
        "The regression test did not call EventProcessor::add_event with a negative event ID, "
        "so it does not exercise the previous crash condition."
    )


def test_final_state_output():
    assert os.path.isfile(FINAL_STATE_FILE), f"Final output file {FINAL_STATE_FILE} is missing."
    with open(FINAL_STATE_FILE, "r") as f:
        content = f.read().strip()

    expected_sums = compute_expected_sums(BACKLOG_FILE)
    assert expected_sums, "Could not compute expected sums (backlog.txt might be missing or empty)."
    valid_outputs = [f"Final Sum: {s}" for s in expected_sums]
    assert content in valid_outputs, (
        f"Contents of {FINAL_STATE_FILE} ({content!r}) do not match any expected outputs: "
        f"{valid_outputs}. Check your modulo fix logic."
    )

    result = run([MAIN_BINARY, BACKLOG_FILE])
    assert result.returncode == 0, (
        f"event_processor failed on backlog.txt.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
    assert result.stdout.strip() == content, (
        "final_state.txt is not the exact summary produced by event_processor on backlog.txt."
    )


def test_sources_build_independently():
    result = run([
        "g++", "-std=c++17", "-Wall", "-Wextra",
        "src/main.cpp", "src/processor.cpp", "-o", SOURCE_BINARY,
    ])
    assert result.returncode == 0, (
        "The application sources do not compile independently.\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
    assert_elf_executable(SOURCE_BINARY)


def test_processor_on_derived_inputs():
    cases = [
        [(-1, 11), (1, 20), (9, 99), (-11, 37), (0, 5)],
        [(-4, 100), (6, 7), (-14, 23), (16, 41), (2, -9)],
        [(-2147483648, 13), (2, 17), (-2, 29), (2147483647, 31)],
    ]

    rng = random.SystemRandom()
    for _ in range(3):
        events = []
        for _ in range(25):
            event_id = rng.randint(-2000000000, 2000000000)
            if event_id >= 0:
                event_id = -event_id - 1
            events.append((event_id, rng.randint(-500, 500)))
            events.append((rng.randint(0, 2000000000), rng.randint(-500, 500)))
        cases.append(events)

    for binary in (MAIN_BINARY, SOURCE_BINARY):
        for events in cases:
            execute_with_events(binary, events)
TEST_EOF

if python3 -m pytest /tmp/test_event_service.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
