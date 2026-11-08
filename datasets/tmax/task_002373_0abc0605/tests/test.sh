#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import resource
import subprocess
import textwrap
import pytest

REPO = "/home/user/videod_repo"
EXE = os.path.join(REPO, "videod")
VIDEO = "/app/incident_stream.mp4"
LOG = "/home/user/processed_frames.log"


def test_executable_exists():
    assert os.path.isfile(EXE), f"Executable not found at {EXE}. Did you compile the code?"
    assert os.access(EXE, os.X_OK), f"File at {EXE} is not executable."
    with open(EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "videod must be a compiled ELF executable."


def test_processed_frames_log_exists():
    assert os.path.isfile(LOG), f"Output log file not found at {LOG}. Did you pipe the output?"


def test_sources_build_the_deployed_binary():
    result = subprocess.run(
        ["gcc", "-o", EXE, "main.c", "process.c", "-I.", "-Wall"],
        cwd=REPO,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"The submitted sources do not compile:\n{result.stderr}"
    assert os.path.isfile(EXE) and os.access(EXE, os.X_OK)


def test_binary_really_processes_and_releases_all_frames():
    interposer_source = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define FRAME_SIZE (1920UL * 1080UL * 3UL)
static void *tracked[512];
static int allocated_frames = 0;
static int freed_frames = 0;
static void *(*real_malloc)(size_t) = NULL;
static void (*real_free)(void *) = NULL;

void *malloc(size_t size) {
    if (!real_malloc)
        real_malloc = (void *(*)(size_t))dlsym(RTLD_NEXT, "malloc");
    void *p = real_malloc(size);
    if (p && size == FRAME_SIZE && allocated_frames < 512) {
        tracked[allocated_frames] = p;
        allocated_frames++;
    }
    return p;
}

void free(void *p) {
    if (!real_free)
        real_free = (void (*)(void *))dlsym(RTLD_NEXT, "free");
    if (p) {
        for (int i = 0; i < allocated_frames; i++) {
            if (tracked[i] == p) {
                tracked[i] = NULL;
                freed_frames++;
                break;
            }
        }
    }
    real_free(p);
}

__attribute__((destructor)) static void report_counts(void) {
    const char *path = getenv("VIDEOD_ALLOCATION_REPORT");
    if (!path) return;
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) return;
    char buf[80];
    int n = snprintf(buf, sizeof(buf), "%d %d\n", allocated_frames, freed_frames);
    if (n > 0) write(fd, buf, (size_t)n);
    close(fd);
}
'''
    source_path = "/tmp/videod_alloc_interposer.c"
    library_path = "/tmp/videod_alloc_interposer.so"
    report_path = "/tmp/videod_allocations.txt"
    with open(source_path, "w") as f:
        f.write(interposer_source)

    build = subprocess.run(
        ["gcc", "-shared", "-fPIC", "-o", library_path, source_path, "-ldl"],
        capture_output=True,
        text=True,
    )
    assert build.returncode == 0, build.stderr

    if os.path.exists(report_path):
        os.unlink(report_path)
    env = os.environ.copy()
    env["LD_PRELOAD"] = library_path
    env["VIDEOD_ALLOCATION_REPORT"] = report_path
    result = subprocess.run([EXE, VIDEO], capture_output=True, env=env, timeout=30)

    assert result.returncode == 0, (
        f"videod did not process the incident video successfully; exit code "
        f"was {result.returncode}, stderr was {result.stderr!r}"
    )
    assert os.path.isfile(report_path), "videod did not execute as the expected frame-processing program."
    with open(report_path) as f:
        fields = f.read().strip().split()
    assert len(fields) == 2, "Could not read videod frame allocation report."
    allocated, freed = map(int, fields)
    assert allocated == 300, f"videod processed {allocated} frames instead of the expected 300."
    assert freed == allocated, f"videod allocated {allocated} frames but released only {freed}."

    with open(LOG, "rb") as f:
        logged_output = f.read()
    assert logged_output == result.stdout, (
        "processed_frames.log is not the standard output produced by the fixed videod."
    )


def test_memory_leak_fixed():
    cmd = ['/usr/bin/time', '-f', '%M', EXE, VIDEO]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, (
        f"videod exited unsuccessfully with code {result.returncode}. Stderr was: {result.stderr}"
    )

    # /usr/bin/time writes the format string to stderr
    try:
        lines = result.stderr.strip().split('\n')
        memory_kb_str = lines[-1]
        memory_kb = int(memory_kb_str)
    except (ValueError, IndexError):
        pytest.fail(f"Could not parse memory output from /usr/bin/time. Stderr was: {result.stderr}")

    threshold = 15000
    assert memory_kb <= threshold, f"Memory exceeded threshold: {memory_kb} KB > {threshold} KB. The memory leak is not fully resolved."
    assert memory_kb < threshold, f"Peak RSS must be strictly below {threshold} KB, but was {memory_kb} KB."


def test_formula_corrected():
    process_c_path = os.path.join(REPO, "process.c")
    assert os.path.isfile(process_c_path), f"Source file not found at {process_c_path}"

    with open(process_c_path, "r") as f:
        content = f.read()

    # Preserve the original source assertions in addition to behavioral checks.
    assert "+ 0.114" in content, "The YUV Luma calculation formula typo was not corrected to use '+ 0.114'."
    assert "- 0.114" not in content, "The YUV Luma calculation formula still contains the buggy '- 0.114'."


def test_process_frame_formula_and_error_path_behavior():
    harness_source = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "process.h"

#define FRAME_SIZE (1920UL * 1080UL * 3UL)

static int run_case(unsigned char r, unsigned char g, unsigned char b) {
    unsigned char *frame = malloc(FRAME_SIZE);
    if (!frame) return 20;
    memset(frame, 0, FRAME_SIZE);
    frame[0] = r;
    frame[1] = g;
    frame[2] = b;

    double expected_y = 0.299 * r + 0.587 * g + 0.114 * b;
    int expected = expected_y < 10.0 ? -1 : 0;
    int actual = process_frame(frame, 1920, 1080);
    if (actual != expected) {
        fprintf(stderr, "RGB(%u,%u,%u): expected %d, got %d\n",
                r, g, b, expected, actual);
        return 21;
    }
    return 0;
}

int main(void) {
    /* These include blue-dominant inputs that distinguish +0.114 from -0.114. */
    const unsigned char cases[][3] = {
        {0, 0, 88}, {0, 0, 87}, {20, 0, 40}, {0, 18, 0},
        {10, 10, 20}, {255, 0, 255}, {0, 255, 255}, {255, 255, 255}
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        int rc = run_case(cases[i][0], cases[i][1], cases[i][2]);
        if (rc) return rc;
    }

    /* Repeated dark frames force the anomaly/error path. Each allocation is
       fully touched so a missing free exhausts the imposed address-space limit. */
    for (int i = 0; i < 40; i++) {
        int rc = run_case(0, 0, 0);
        if (rc) return rc;
    }
    return 0;
}
'''
    harness_c = "/tmp/process_behavior.c"
    harness_exe = "/tmp/process_behavior"
    with open(harness_c, "w") as f:
        f.write(harness_source)

    build = subprocess.run(
        ["gcc", "-o", harness_exe, harness_c, os.path.join(REPO, "process.c"),
         "-I", REPO, "-Wall"],
        capture_output=True,
        text=True,
    )
    assert build.returncode == 0, f"Could not build process_frame test harness:\n{build.stderr}"

    def limit_memory():
        limit = 128 * 1024 * 1024
        resource.setrlimit(resource.RLIMIT_AS, (limit, limit))

    result = subprocess.run(
        [harness_exe], capture_output=True, text=True, timeout=30,
        preexec_fn=limit_memory,
    )
    assert result.returncode == 0, (
        "process_frame failed formula or error-path resource tests. "
        f"Exit code: {result.returncode}; stderr: {result.stderr}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
