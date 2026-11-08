#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import time
import shutil
import resource
import secrets
import subprocess

TOOLKIT = "/home/user/video_toolkit"
PROCESSOR = os.path.join(TOOLKIT, "processor")
PROBE_LOG = "/tmp/processor_probe.log"
PROBE_MODE = "/tmp/probe_mode"


def run(cmd, **kwargs):
    return subprocess.run(cmd, **kwargs)


def install_processor_probe(nonce):
    source = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <sys/stat.h>
#include <time.h>

static uint64_t hash_file(const char *path) {
    FILE *f = fopen(path, "rb");
    uint64_t h = 1469598103934665603ULL;
    int c;
    if (!f) return 0;
    while ((c = fgetc(f)) != EOF) {
        h ^= (unsigned char)c;
        h *= 1099511628211ULL;
    }
    fclose(f);
    return h;
}

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    char mode[32] = {0};
    FILE *mf = fopen("/tmp/probe_mode", "r");
    if (mf) { fscanf(mf, "%31s", mode); fclose(mf); }

    struct stat st;
    if (stat(argv[1], &st) != 0) return 1;
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    double now = ts.tv_sec + ts.tv_nsec / 1000000000.0;

    FILE *log = fopen("/tmp/processor_probe.log", "a");
    if (!log) return 2;
    if (strcmp(mode, "prop") == 0) {
        fprintf(log, "%.9f\t%lld\t%016llx\t%s\n", now,
                (long long)st.st_size,
                (unsigned long long)hash_file(argv[1]), argv[1]);
        fclose(log);
        return (st.st_size % 7 == 0) ? 139 : 0;
    }
    fprintf(log, "%.9f\t%lld\t%s\n", now, (long long)st.st_size, argv[1]);
    fclose(log);
    printf("PROCESSED_NONCE %s\n", argv[1]);
    return 0;
}
'''
    source = source.replace("PROCESSED_NONCE", "PROCESSED_" + nonce)
    with open("/tmp/processor_probe.c", "w") as f:
        f.write(source)
    result = run(["gcc", "-O2", "-o", PROCESSOR, "/tmp/processor_probe.c"],
                 capture_output=True, text=True)
    assert result.returncode == 0, result.stderr


def read_probe_lines():
    if not os.path.exists(PROBE_LOG):
        return []
    with open(PROBE_LOG) as f:
        return [line.rstrip("\n") for line in f if line.strip()]


def test_scripts_exist_and_executable():
    scripts = [
        "/home/user/video_toolkit/build.sh",
        "/home/user/pipeline.sh",
        "/home/user/prop_test.sh",
    ]
    for script in scripts:
        assert os.path.isfile(script), f"Script {script} does not exist."
        st = os.stat(script)
        assert bool(st.st_mode & stat.S_IXUSR), f"Script {script} is not executable."


def test_build_compiles_and_links_optimized_library():
    if os.path.lexists(PROCESSOR):
        os.remove(PROCESSOR)
    result = run([os.path.join(TOOLKIT, "build.sh")], cwd=TOOLKIT,
                 capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, (
        f"build.sh failed with exit code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    assert os.path.isfile(PROCESSOR), "build.sh did not create processor."
    assert os.access(PROCESSOR, os.X_OK), "processor is not executable."
    with open(PROCESSOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", "processor must be the compiled ELF executable."

    linked = run(["ldd", PROCESSOR], cwd=TOOLKIT, capture_output=True, text=True)
    linkage = linked.stdout + linked.stderr
    assert linked.returncode == 0, f"processor is not dynamically linked:\n{linkage}"
    assert "libprocess_v2_opt.so" in linkage, (
        "processor is not dynamically linked to libprocess_v2_opt.so."
    )
    assert "not found" not in linkage, f"processor has unresolved libraries:\n{linkage}"
    assert "libprocess_v1.so" not in linkage, "processor links the unoptimized library."

    sample = "/tmp/build_sample.bin"
    with open(sample, "wb") as f:
        f.write(b"x" * 1025)
    t0 = time.monotonic()
    executed = run([PROCESSOR, sample], cwd=TOOLKIT,
                   capture_output=True, text=True, timeout=3)
    elapsed = time.monotonic() - t0
    assert executed.returncode == 0, (
        f"Built processor did not run successfully:\n{executed.stderr}"
    )
    assert "Processed" in executed.stdout, "Built processor produced no processing output."
    assert elapsed < 0.15, (
        f"processor took {elapsed:.3f}s; the optimized library does not appear active."
    )


def test_prop_test_report_is_derived_from_real_invocations():
    prop_script = "/home/user/prop_test.sh"
    with open(prop_script, errors="replace") as f:
        prop_source = f.read()
    assert re.search(r"\bdd\b", prop_source), "prop_test.sh does not use dd."
    assert "/dev/urandom" in prop_source, "prop_test.sh does not use /dev/urandom."

    nonce = secrets.token_hex(8)
    install_processor_probe(nonce)
    open(PROBE_LOG, "w").close()
    with open(PROBE_MODE, "w") as f:
        f.write("prop\n")
    report_path = "/home/user/test_report.txt"
    if os.path.exists(report_path):
        os.remove(report_path)

    result = run([prop_script], cwd="/home/user", capture_output=True,
                 text=True, timeout=90)
    assert result.returncode == 0, (
        f"prop_test.sh failed with exit code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    records = read_probe_lines()
    assert len(records) == 100, f"Expected 100 processor invocations, got {len(records)}."

    sizes = []
    hashes = []
    for line in records:
        fields = line.split("\t", 3)
        assert len(fields) == 4, f"Malformed processor probe record: {line!r}"
        sizes.append(int(fields[1]))
        hashes.append(fields[2])
    assert all(1024 <= size <= 50 * 1024 for size in sizes), (
        "Generated property-test files were not all between 1KB and 50KB."
    )
    assert len(set(sizes)) >= 20, "Property-test file sizes do not vary sufficiently."
    assert len(set(hashes)) >= 95, "Property-test inputs are not independently random."

    expected_segfaults = sum(size % 7 == 0 for size in sizes)
    expected_successes = 100 - expected_segfaults
    assert os.path.isfile(report_path), f"Report file {report_path} was not created."
    with open(report_path) as f:
        content = f.read().strip()
    match = re.fullmatch(r"Success:\s*(\d+),\s*Segfaults:\s*(\d+)", content)
    assert match is not None, (
        f"Report content {content!r} does not match 'Success: X, Segfaults: Y'."
    )
    successes, segfaults = map(int, match.groups())
    assert successes + segfaults == 100, (
        f"Expected 100 total tests, got {successes + segfaults}."
    )
    assert (successes, segfaults) == (expected_successes, expected_segfaults), (
        "Report counts do not match the observed processor exit statuses."
    )


def test_pipeline_execution_validation_content_and_cadence():
    pipeline_script = "/home/user/pipeline.sh"
    frames_dir = "/home/user/frames"
    log_path = "/home/user/processing.log"
    nonce = secrets.token_hex(8)

    with open(pipeline_script, errors="replace") as f:
        pipeline_source = f.read()
    assert re.search(r"\bffmpeg\b", pipeline_source), "pipeline.sh does not invoke ffmpeg."
    assert re.search(r"\bffprobe\b", pipeline_source), (
        "pipeline.sh does not use ffprobe to validate MP4 input."
    )

    install_processor_probe(nonce)
    with open(PROBE_MODE, "w") as f:
        f.write("pipeline\n")
    open(PROBE_LOG, "w").close()

    invalid = "/tmp/not_a_video.mp4"
    with open(invalid, "wb") as f:
        f.write(b"not an mp4 video")
    for bad_path in (invalid, "/tmp/definitely_missing_video.mp4"):
        bad = run([pipeline_script, bad_path], capture_output=True, text=True, timeout=10)
        assert bad.returncode == 1, (
            f"Pipeline must exit 1 for invalid input {bad_path!r}; got {bad.returncode}."
        )
    assert read_probe_lines() == [], "processor was invoked for invalid video input."

    video_path = f"/tmp/verification_{nonce}.mp4"
    made = run([
        "ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
        "testsrc2=duration=6:size=320x240:rate=10", "-c:v", "mpeg4",
        "-pix_fmt", "yuv420p", video_path,
    ], capture_output=True, text=True, timeout=30)
    assert made.returncode == 0, made.stderr

    expected = run([
        "ffmpeg", "-v", "error", "-i", video_path, "-frames:v", "50",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1",
    ], capture_output=True, timeout=30)
    assert expected.returncode == 0, expected.stderr.decode(errors="replace")
    frame_bytes = 320 * 240 * 3
    assert len(expected.stdout) == 50 * frame_bytes

    if os.path.exists(frames_dir):
        shutil.rmtree(frames_dir)
    if os.path.exists(log_path):
        os.remove(log_path)
    os.makedirs(frames_dir, exist_ok=True)
    open(PROBE_LOG, "w").close()

    ru_before = resource.getrusage(resource.RUSAGE_CHILDREN)
    t0 = time.time()
    result = run([pipeline_script, video_path], capture_output=True,
                 text=True, timeout=30)
    t1 = time.time()
    ru_after = resource.getrusage(resource.RUSAGE_CHILDREN)

    assert result.returncode == 0, (
        f"Pipeline failed with exit code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    wall_clock_time = t1 - t0
    total_cpu_time = ((ru_after.ru_utime - ru_before.ru_utime) +
                      (ru_after.ru_stime - ru_before.ru_stime))
    assert total_cpu_time <= 1.0, (
        f"Total CPU time {total_cpu_time:.3f}s exceeded threshold of 1.0s."
    )
    assert wall_clock_time >= 9.0, (
        f"Wall-clock time {wall_clock_time:.3f}s is too fast for 5 FPS."
    )
    assert wall_clock_time <= 13.0, (
        f"Wall-clock time {wall_clock_time:.3f}s is too slow for exactly 5 FPS."
    )

    records = read_probe_lines()
    assert len(records) == 50, f"Expected 50 processor invocations, got {len(records)}."
    parsed = [line.split("\t", 2) for line in records]
    assert all(len(fields) == 3 for fields in parsed), "Malformed invocation records."
    timestamps = [float(fields[0]) for fields in parsed]
    invoked_paths = [os.path.realpath(fields[2]) for fields in parsed]
    intervals = [b - a for a, b in zip(timestamps, timestamps[1:])]
    assert all(0.15 <= gap <= 0.45 for gap in intervals), (
        f"Processor calls were not evenly rate-limited to 5 FPS: {intervals}"
    )
    assert 9.2 <= timestamps[-1] - timestamps[0] <= 11.5, (
        "Observed processor invocation rate was not 5 frames per second."
    )

    assert os.path.isfile(log_path), f"Log file {log_path} was not created."
    with open(log_path) as f:
        lines = [line for line in f.read().splitlines() if line.strip()]
    assert len(lines) == 50, f"Expected 50 log lines, got {len(lines)}."
    expected_log = [f"PROCESSED_{nonce} {fields[2]}" for fields in parsed]
    assert lines == expected_log, "processing.log is not the appended processor stdout."

    frames_created = [
        os.path.realpath(os.path.join(frames_dir, name))
        for name in os.listdir(frames_dir) if name.lower().endswith(".jpg")
    ]
    assert len(frames_created) == 50, (
        f"Expected 50 JPEG frames in {frames_dir}, got {len(frames_created)}."
    )
    assert len(set(invoked_paths)) == 50, "The same frame was processed more than once."
    assert set(invoked_paths) == set(frames_created), (
        "processor was not invoked once for every extracted JPEG frame."
    )

    for index, path in enumerate(invoked_paths):
        with open(path, "rb") as f:
            data = f.read()
        assert data.startswith(b"\xff\xd8") and data.endswith(b"\xff\xd9"), (
            f"{path} is not a nonempty JPEG image."
        )
        decoded = run([
            "ffmpeg", "-v", "error", "-i", path, "-frames:v", "1",
            "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1",
        ], capture_output=True, timeout=10)
        assert decoded.returncode == 0, f"Could not decode extracted frame {path}."
        assert len(decoded.stdout) == frame_bytes, f"Wrong dimensions for frame {path}."
        reference = expected.stdout[index * frame_bytes:(index + 1) * frame_bytes]
        positions = range(0, frame_bytes, 251)
        error = sum(abs(decoded.stdout[p] - reference[p]) for p in positions) / len(positions)
        assert error < 22.0, (
            f"Frame {index + 1} does not match the corresponding input-video frame "
            f"(sampled mean error {error:.2f})."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
