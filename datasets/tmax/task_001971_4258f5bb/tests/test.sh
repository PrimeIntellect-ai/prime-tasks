#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import struct
import subprocess
import tempfile
import textwrap
import time

import pytest

APP = "/app/fast-pcap-extract-1.2"
BINARY = os.path.join(APP, "pcap_extract")


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def test_makefile_builds_real_executable():
    result = run(["make", "clean"], cwd=APP)
    assert result.returncode == 0, result.stdout + result.stderr
    result = run(["make"], cwd=APP, timeout=60)
    assert result.returncode == 0, f"make failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(BINARY), f"Binary not found at {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Binary at {BINARY} is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "pcap_extract is not a compiled ELF executable"

    makefile = open(os.path.join(APP, "Makefile"), encoding="utf-8").read()
    assert re.search(r"(?:^|\s)-O(?:2|3|fast)(?:\s|$)", makefile, re.M), \
        "Makefile does not enable an appropriate compiler optimization level"


def test_binary_executes_and_handles_empty_pcap_securely():
    with tempfile.TemporaryDirectory(prefix="pcap_verify_") as td:
        pcap = os.path.join(td, "empty.pcap")
        outdir = os.path.join(td, "output")
        # Valid little-endian PCAP containing no packets. Its correct extraction is empty.
        with open(pcap, "wb") as f:
            f.write(struct.pack("<IHHIIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, 1))

        old_umask = os.umask(0)
        try:
            result = run([BINARY, pcap, outdir], cwd=APP, timeout=30)
        finally:
            os.umask(old_umask)

        assert result.returncode == 0, \
            f"pcap_extract failed on a valid PCAP:\n{result.stdout}\n{result.stderr}"
        assert os.path.isdir(outdir), "pcap_extract did not create its output directory"
        assert stat.S_IMODE(os.stat(outdir).st_mode) == 0o700

        hashes = os.path.join(outdir, "hashes.txt")
        assert os.path.isfile(hashes), "pcap_extract did not create hashes.txt"
        assert stat.S_IMODE(os.stat(hashes).st_mode) == 0o600
        assert open(hashes, "rb").read().strip() == b"", \
            "An empty PCAP must produce an empty hashes.txt"
        assert sorted(os.listdir(outdir)) == ["hashes.txt"], \
            "An empty PCAP unexpectedly produced extracted payload files"


def test_output_directory_permissions():
    out_dir = "/home/user/extracted_payloads"
    assert os.path.isdir(out_dir), f"Output directory {out_dir} does not exist. Did the tool run successfully?"
    perms = stat.S_IMODE(os.stat(out_dir).st_mode)
    assert perms == 0o700, f"Output directory permissions are {oct(perms)}, expected 0o700."


def test_output_file_permissions():
    out_dir = "/home/user/extracted_payloads"
    assert os.path.isdir(out_dir), f"Output directory {out_dir} does not exist."
    hashes_file = os.path.join(out_dir, "hashes.txt")
    assert os.path.isfile(hashes_file), f"hashes.txt not found in {out_dir}"
    for filename in os.listdir(out_dir):
        filepath = os.path.join(out_dir, filename)
        if os.path.isfile(filepath):
            perms = stat.S_IMODE(os.stat(filepath).st_mode)
            assert perms == 0o600, f"File {filepath} has permissions {oct(perms)}, expected 0o600."


def test_writer_function_enforces_permissions():
    harness = r'''
#include <stdio.h>
void write_payload(const char *filepath, const char *outdir);
int main(int argc, char **argv) {
    if (argc != 3) return 2;
    write_payload(argv[2], argv[1]);
    return 0;
}
'''
    with tempfile.TemporaryDirectory(prefix="writer_verify_") as td:
        src = os.path.join(td, "harness.c")
        exe = os.path.join(td, "harness")
        outdir = os.path.join(td, "created")
        payload = os.path.join(outdir, "payload.bin")
        open(src, "w").write(harness)
        result = run(["gcc", "-Wall", "-Werror", src, os.path.join(APP, "writer.c"), "-o", exe])
        assert result.returncode == 0, f"Could not test writer.c:\n{result.stdout}\n{result.stderr}"
        old_umask = os.umask(0)
        try:
            result = run([exe, outdir, payload], timeout=10)
        finally:
            os.umask(old_umask)
        assert result.returncode == 0, result.stdout + result.stderr
        assert os.path.isdir(outdir), "write_payload did not create the output directory"
        assert os.path.isfile(payload), "write_payload did not create the requested file"
        assert stat.S_IMODE(os.stat(outdir).st_mode) == 0o700
        assert stat.S_IMODE(os.stat(payload).st_mode) == 0o600


def test_parser_has_no_header_buffer_overflow():
    harness = r'''
#include <stdlib.h>
#include <string.h>
void parse_packet(char *pkt_data);
int main(void) {
    char *p = malloc(8192);
    if (!p) return 2;
    memset(p, 'A', 8191);
    p[8191] = '\0';
    parse_packet(p);
    free(p);
    return 0;
}
'''
    with tempfile.TemporaryDirectory(prefix="parser_verify_") as td:
        src = os.path.join(td, "harness.c")
        exe = os.path.join(td, "harness")
        open(src, "w").write(harness)
        result = run([
            "gcc", "-g", "-O1", "-fno-omit-frame-pointer",
            "-fsanitize=address", src, os.path.join(APP, "parser.c"), "-o", exe
        ])
        assert result.returncode == 0, f"Could not test parser.c:\n{result.stdout}\n{result.stderr}"
        env = os.environ.copy()
        env["ASAN_OPTIONS"] = "detect_leaks=0:halt_on_error=1"
        result = run([exe], env=env, timeout=10)
        assert result.returncode == 0, \
            f"parser.c still overflows its header buffer:\n{result.stdout}\n{result.stderr}"


def test_matcher_correctness_and_three_x_speedup():
    harness = r'''
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

int match_payload(const char *payload, int plen, const char *pattern, int patlen);
static volatile int sink;

__attribute__((noinline,optimize("O0")))
static int naive(const char *payload, int plen, const char *pattern, int patlen) {
    for (int i = 0; i <= plen - patlen; i++) {
        int match = 1;
        for (int j = 0; j < patlen; j++) {
            if (payload[i+j] != pattern[j]) match = 0;
        }
        if (match) return 1;
    }
    return 0;
}

static int expected(const unsigned char *p, int n, const unsigned char *q, int m) {
    if (m <= 0) return 1;
    if (n < m) return 0;
    for (int i = 0; i <= n-m; i++) if (!memcmp(p+i, q, m)) return 1;
    return 0;
}

static uint32_t rng_state = 0x91e10da5u;
static uint32_t rnd(void) {
    rng_state ^= rng_state << 13;
    rng_state ^= rng_state >> 17;
    rng_state ^= rng_state << 5;
    return rng_state;
}

static double now(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1000000000.0;
}

int main(void) {
    unsigned char p[4096], q[160];
    for (int t = 0; t < 300; t++) {
        int n = 1 + (int)(rnd() % sizeof(p));
        int m = 1 + (int)(rnd() % sizeof(q));
        for (int i = 0; i < n; i++) p[i] = (unsigned char)rnd();
        for (int i = 0; i < m; i++) q[i] = (unsigned char)rnd();
        if ((t & 1) && m <= n) {
            int at = (int)(rnd() % (unsigned)(n-m+1));
            memcpy(p+at, q, m);
        }
        int got = match_payload((char *)p, n, (char *)q, m);
        int want = expected(p, n, q, m);
        if (!!got != !!want) {
            fprintf(stderr, "matcher incorrect on case %d (got %d, expected %d)\n", t, got, want);
            return 10;
        }
    }

    const int n = 262144, m = 192, reps = 4;
    unsigned char *hay = malloc(n), *pat = malloc(m);
    if (!hay || !pat) return 11;
    memset(hay, 'A', n);
    memset(pat, 'A', m);
    pat[m-1] = 'B';
    hay[n-1] = 'B';
    if (!match_payload((char *)hay, n, (char *)pat, m)) return 12;

    double a = now();
    for (int r = 0; r < reps; r++) sink ^= naive((char *)hay, n, (char *)pat, m);
    double naive_time = now() - a;
    a = now();
    for (int r = 0; r < reps; r++) sink ^= match_payload((char *)hay, n, (char *)pat, m);
    double fast_time = now() - a;
    fprintf(stderr, "naive=%f optimized=%f speedup=%f\n", naive_time, fast_time, naive_time/fast_time);
    free(hay); free(pat);
    if (fast_time <= 0.0 || naive_time / fast_time < 3.0) return 13;
    return 0;
}
'''
    with tempfile.TemporaryDirectory(prefix="matcher_verify_") as td:
        src = os.path.join(td, "benchmark.c")
        exe = os.path.join(td, "benchmark")
        open(src, "w").write(harness)
        result = run(["gcc", "-O3", src, os.path.join(APP, "matcher.c"), "-o", exe])
        assert result.returncode == 0, f"Could not test matcher.c:\n{result.stdout}\n{result.stderr}"
        result = run([exe], timeout=30)
        assert result.returncode == 0, \
            f"Matcher is incorrect or did not achieve the required 3.0x speedup:\n{result.stdout}\n{result.stderr}"


def test_vulnerability_remediation_source():
    writer_c = os.path.join(APP, "writer.c")
    assert os.path.isfile(writer_c), f"Source file {writer_c} missing."
    content = open(writer_c, encoding="utf-8").read()
    assert "0666" not in content, "Insecure file permissions (0666) still found in writer.c"
    assert "0777" not in content, "Insecure directory permissions (0777) still found in writer.c"


def test_performance_optimization_source():
    matcher_c = os.path.join(APP, "matcher.c")
    assert os.path.isfile(matcher_c), f"Source file {matcher_c} missing."
    content = open(matcher_c, encoding="utf-8").read()
    has_memmem = "memmem" in content
    has_kmp = "kmp" in content.lower()
    has_opt = has_memmem or has_kmp or ("O3" in open(os.path.join(APP, "Makefile")).read())
    # The behavioral benchmark above is authoritative; retain this original indicator check.


def test_verifier_script_if_present():
    verifier_script = "/opt/verifier/evaluate_speedup.py"
    if os.path.isfile(verifier_script):
        result = run(["python3", verifier_script], timeout=60)
        assert result.returncode == 0, f"Verifier script failed:\n{result.stdout}\n{result.stderr}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
