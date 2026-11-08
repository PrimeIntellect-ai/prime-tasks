#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import re
import shutil
import struct
import subprocess
import time
import wave

import pytest

ARCHIVE_PATH = "/home/user/release_v2.tar.gz"
EXTRACT_DIR = "/tmp/release_test"
INPUT_WAV = "/app/release_sample.wav"
OUTPUT_WAV = "/tmp/output.wav"
BASELINE_TIME = 12.0
TARGET_SPEEDUP = 4.0


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, **kwargs)


@pytest.fixture(scope="session", autouse=True)
def setup_extraction():
    if os.path.exists(EXTRACT_DIR):
        shutil.rmtree(EXTRACT_DIR)
    os.makedirs(EXTRACT_DIR, exist_ok=True)

    assert os.path.exists(ARCHIVE_PATH), f"Release archive not found at {ARCHIVE_PATH}"
    subprocess.run(["tar", "-xzf", ARCHIVE_PATH, "-C", EXTRACT_DIR], check=True)
    yield
    if os.path.exists(EXTRACT_DIR):
        shutil.rmtree(EXTRACT_DIR)


def paths():
    return (
        os.path.join(EXTRACT_DIR, "bin", "audiotool"),
        os.path.join(EXTRACT_DIR, "lib", "libaudiofilter.so.2.0.1"),
        os.path.join(EXTRACT_DIR, "lib", "libaudiofilter.so.2"),
        os.path.join(EXTRACT_DIR, "lib", "libaudiofilter.so"),
    )


def assert_valid_matching_wav(input_path, output_path, max_sample_error=2):
    with wave.open(input_path, "rb") as src, wave.open(output_path, "rb") as dst:
        assert dst.getparams()[:4] == src.getparams()[:4], "Output WAV format or frame count changed"
        assert src.getsampwidth() == 2, "Test fixture must be 16-bit PCM"
        source_data = src.readframes(src.getnframes())
        output_data = dst.readframes(dst.getnframes())
    assert len(source_data) == len(output_data)
    source_samples = struct.unpack("<%dh" % (len(source_data) // 2), source_data)
    output_samples = struct.unpack("<%dh" % (len(output_data) // 2), output_data)
    error = max(abs(a - b) for a, b in zip(source_samples, output_samples))
    assert error <= max_sample_error, f"Filter output differs from the legacy mathematical result (max error {error})"


def test_archive_contents():
    tool_path, lib_real, lib_sym1, lib_sym2 = paths()

    assert os.path.isfile(tool_path), f"Missing executable: {tool_path}"
    assert os.access(tool_path, os.X_OK), f"Not executable: {tool_path}"
    assert os.path.isfile(lib_real), f"Missing shared library: {lib_real}"
    assert os.path.islink(lib_sym1), f"Missing symlink: {lib_sym1}"
    assert os.path.islink(lib_sym2), f"Missing symlink: {lib_sym2}"
    assert os.readlink(lib_sym1) == "libaudiofilter.so.2.0.1"
    assert os.readlink(lib_sym2) == "libaudiofilter.so.2"


def test_elf_linkage_soname_rpath_and_symbol():
    tool_path, lib_real, _, _ = paths()
    tool_dynamic = run(["readelf", "-d", tool_path], text=True).stdout
    lib_dynamic = run(["readelf", "-d", lib_real], text=True).stdout
    lib_symbols = run(["readelf", "-Ws", lib_real], text=True).stdout

    assert re.search(r"\(NEEDED\).*\[libaudiofilter\.so\.2\]", tool_dynamic), \
        "audiotool is not dynamically linked against the versioned audio-filter ABI"
    assert re.search(r"\((?:RUNPATH|RPATH)\).*\[.*\$ORIGIN/\.\./lib/?(?:[:\]]|$)", tool_dynamic), \
        "audiotool lacks an $ORIGIN/../lib rpath/runpath"
    assert re.search(r"\(SONAME\).*\[libaudiofilter\.so\.2\]", lib_dynamic), \
        "Shared library has the wrong SONAME"
    assert re.search(r"\bGLOBAL\b.*\bapply_filter\b", lib_symbols), \
        "Shared library does not export apply_filter"

    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    linked = run(["ldd", tool_path], env=env, text=True).stdout
    assert os.path.join(EXTRACT_DIR, "lib", "libaudiofilter.so.2") in linked, \
        "The packaged binary does not resolve its packaged library through rpath"


def test_filter_abi_and_mathematics():
    _, lib_real, _, _ = paths()
    lib = ctypes.CDLL(lib_real)
    fn = lib.apply_filter
    fn.argtypes = [ctypes.POINTER(ctypes.c_float), ctypes.c_size_t]
    fn.restype = None
    original = [-1000.25, -3.5, -0.125, 0.0, 0.125, 3.5, 1000.25]
    values = (ctypes.c_float * len(original))(*original)
    fn(values, len(original))
    for before, after in zip(original, values):
        tolerance = max(2e-6, abs(before) * 2e-6)
        assert abs(after - before) <= tolerance, \
            f"apply_filter produced {after} for {before}, not the legacy mathematical result"


def test_source_uses_goroutines_and_channels():
    source_path = "/home/user/src/main.go"
    assert os.path.isfile(source_path), "Modified Go source is missing"
    source = open(source_path, "r", encoding="utf-8").read()
    source_without_comments = re.sub(r"//.*?$|/\*.*?\*/", "", source, flags=re.M | re.S)
    assert re.search(r"\bgo\s+(?:func\s*\(|[A-Za-z_]\w*\s*\()", source_without_comments), \
        "main.go does not launch goroutines"
    assert re.search(r"\bchan\b|\bmake\s*\(\s*chan\b", source_without_comments), \
        "main.go does not use channels"


def test_execution_speedup_and_audio_result():
    tool_path, _, _, _ = paths()
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = os.path.join(EXTRACT_DIR, "lib") + ":" + env.get("LD_LIBRARY_PATH", "")

    if os.path.exists(OUTPUT_WAV):
        os.remove(OUTPUT_WAV)

    start_time = time.time()
    res = subprocess.run([tool_path, INPUT_WAV, OUTPUT_WAV], env=env, capture_output=True)
    end_time = time.time()

    assert res.returncode == 0, f"Tool execution failed with return code {res.returncode}. stderr: {res.stderr.decode()}"
    assert os.path.exists(OUTPUT_WAV), "Output WAV file was not created."

    optimized_time = end_time - start_time
    assert optimized_time > 0, "Execution time must be positive."
    speedup = BASELINE_TIME / optimized_time
    assert speedup >= TARGET_SPEEDUP, f"Speedup {speedup:.2f}x is below the target threshold of {TARGET_SPEEDUP}x. (Optimized time: {optimized_time:.2f}s)"
    assert_valid_matching_wav(INPUT_WAV, OUTPUT_WAV)


def test_measured_unoptimized_baseline_speedup():
    tool_path, _, _, _ = paths()
    sample_count = 500000
    bench_wav = "/tmp/speed_input.wav"
    bench_out = "/tmp/speed_output.wav"
    with wave.open(bench_wav, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(44100)
        block = struct.pack("<1000h", *[((i * 97) % 60001) - 30000 for i in range(1000)])
        wav.writeframes(block * (sample_count // 1000))

    baseline_c = r'''#include <stdio.h>
#include <stdlib.h>
#include <stddef.h>
void apply_filter(float* data, size_t length) {
    for (size_t i = 0; i < length; i++) {
        float sum = 0;
        for (size_t j = 0; j < 1000; j++) sum += 0.000001f * data[i];
        data[i] = data[i] * 0.999f + sum;
    }
}
int main(int argc, char **argv) {
    size_t n = (size_t)strtoull(argv[1], 0, 10);
    float *p = malloc(n * sizeof(float));
    if (!p) return 2;
    for (size_t i=0; i<n; i++) p[i] = (float)((int)(i%101)-50) / 50.0f;
    apply_filter(p, n);
    volatile float result = p[n/2];
    printf("%f\n", result);
    free(p);
    return 0;
}
'''
    open("/tmp/legacy_benchmark.c", "w").write(baseline_c)
    run(["gcc", "-O0", "/tmp/legacy_benchmark.c", "-o", "/tmp/legacy_benchmark"])
    start = time.perf_counter()
    run(["/tmp/legacy_benchmark", str(sample_count)])
    baseline_elapsed = time.perf_counter() - start

    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    start = time.perf_counter()
    result = subprocess.run([tool_path, bench_wav, bench_out], env=env, capture_output=True)
    optimized_elapsed = time.perf_counter() - start
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    assert os.path.exists(bench_out)
    assert baseline_elapsed / optimized_elapsed >= TARGET_SPEEDUP, \
        f"Measured legacy speedup was only {baseline_elapsed / optimized_elapsed:.2f}x"
    assert_valid_matching_wav(bench_wav, bench_out)


def test_four_parallel_c_calls_and_results_are_used():
    tool_path, lib_real, _, _ = paths()
    probe_c = r'''#define _GNU_SOURCE
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdatomic.h>
static _Atomic int active = 0;
static _Atomic int maximum = 0;
static _Atomic unsigned long long total = 0;
void apply_filter(float *data, size_t length) {
    int now = atomic_fetch_add(&active, 1) + 1;
    int old = atomic_load(&maximum);
    while (now > old && !atomic_compare_exchange_weak(&maximum, &old, now)) { }
    atomic_fetch_add(&total, (unsigned long long)length);
    for (size_t i=0; i<length; i++) data[i] = 0.0f;
    usleep(150000);
    atomic_fetch_sub(&active, 1);
}
__attribute__((destructor)) static void report(void) {
    const char *path = getenv("AUDIOFILTER_PROBE_LOG");
    if (!path) return;
    FILE *f = fopen(path, "w");
    if (f) { fprintf(f, "%d %llu\n", atomic_load(&maximum), atomic_load(&total)); fclose(f); }
}
'''
    open("/tmp/probe.c", "w").write(probe_c)
    run(["gcc", "-shared", "-fPIC", "-O2", "-Wl,-soname,libaudiofilter.so.2",
         "/tmp/probe.c", "-o", "/tmp/probe.so"])

    probe_input = "/tmp/probe_input.wav"
    probe_output = "/tmp/probe_output.wav"
    probe_log = "/tmp/probe.log"
    sample_count = 400000
    with wave.open(probe_input, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(44100)
        block = struct.pack("<1000h", *[1000 + (i % 20000) for i in range(1000)])
        wav.writeframes(block * (sample_count // 1000))

    backup = lib_real + ".real-backup"
    os.rename(lib_real, backup)
    shutil.copy2("/tmp/probe.so", lib_real)
    try:
        env = os.environ.copy()
        env.pop("LD_LIBRARY_PATH", None)
        env["AUDIOFILTER_PROBE_LOG"] = probe_log
        result = subprocess.run([tool_path, probe_input, probe_output], env=env,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
        assert result.returncode == 0, result.stderr.decode(errors="replace")
        assert os.path.isfile(probe_log), "Dynamically loaded apply_filter was not called"
        maximum, total = map(int, open(probe_log).read().split())
        assert maximum >= 4, f"Only {maximum} concurrent C filter calls were observed; at least 4 are required"
        assert total == sample_count, f"Filter received {total} samples instead of all {sample_count} audio samples"
        with wave.open(probe_output, "rb") as wav:
            assert wav.getnchannels() == 1 and wav.getsampwidth() == 2
            assert wav.getnframes() == sample_count
            audio = wav.readframes(sample_count)
        assert audio == b"\x00\x00" * sample_count, \
            "The tool ignored the samples returned by the dynamically linked filter"
    finally:
        if os.path.exists(lib_real):
            os.remove(lib_real)
        os.rename(backup, lib_real)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
