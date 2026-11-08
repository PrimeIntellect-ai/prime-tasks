#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import glob
import gzip
import secrets
import subprocess
import tempfile
import pytest

SANITIZER = "/home/user/sanitizer"
SOURCE = "/home/user/sanitize_logs.c"


def run(cmd, **kwargs):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)


def test_video_frames_extracted():
    frames_dir = "/home/user/frames"
    assert os.path.isdir(frames_dir), f"Directory {frames_dir} does not exist."

    frames = sorted(glob.glob(os.path.join(frames_dir, "frame_*.jpg")))
    assert len(frames) == 15, f"Expected 15 frames, found {len(frames)}."

    for i in range(1, 16):
        expected_name = f"frame_{i:03d}.jpg"
        assert os.path.basename(frames[i-1]) == expected_name, f"Expected frame name {expected_name}, found {os.path.basename(frames[i-1])}."

    with tempfile.TemporaryDirectory() as td:
        ref_pattern = os.path.join(td, "reference_%03d.jpg")
        result = run([
            "ffmpeg", "-v", "error", "-i", "/app/surveillance.mp4",
            "-vf", "fps=1", "-q:v", "2", ref_pattern
        ])
        assert result.returncode == 0, result.stderr.decode(errors="replace")
        references = sorted(glob.glob(os.path.join(td, "reference_*.jpg")))
        assert len(references) == 15, f"Reference extraction produced {len(references)} frames."

        for submitted, reference in zip(frames, references):
            assert os.path.isfile(submitted) and os.path.getsize(submitted) > 0, f"Empty frame: {submitted}"
            probe = run([
                "ffprobe", "-v", "error", "-select_streams", "v:0",
                "-show_entries", "stream=codec_name,width,height", "-of", "csv=p=0", submitted
            ])
            assert probe.returncode == 0, f"Frame is not decodable: {submitted}"
            fields = probe.stdout.decode().strip().split(",")
            assert fields == ["mjpeg", "640", "360"], f"Unexpected JPEG properties for {submitted}: {fields}"

            comparison = run([
                "ffmpeg", "-v", "info", "-i", reference, "-i", submitted,
                "-lavfi", "ssim", "-f", "null", "-"
            ])
            diagnostic = comparison.stderr.decode(errors="replace")
            assert comparison.returncode == 0, f"Could not compare {submitted}: {diagnostic}"
            matches = re.findall(r"All:([0-9.]+)", diagnostic)
            assert matches, f"No SSIM result for {submitted}"
            assert float(matches[-1]) >= 0.94, f"{submitted} does not match its source-video frame (SSIM {matches[-1]})."


def test_frame_count_file():
    count_file = "/home/user/frame_count.txt"
    assert os.path.isfile(count_file), f"File {count_file} does not exist."
    with open(count_file, "r") as f:
        content = f.read().strip()
    assert content == "15", f"Expected frame count to be '15', found '{content}'."


def test_sanitizer_executable_exists():
    assert os.path.isfile(SANITIZER), f"Executable {SANITIZER} does not exist."
    assert os.access(SANITIZER, os.X_OK), f"{SANITIZER} is not executable."
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} does not exist."
    assert os.path.getsize(SOURCE) > 0, f"Source file {SOURCE} is empty."


def get_records(text):
    records = []
    current_record = []
    in_record = False
    for line in text.splitlines(keepends=True):
        if line.strip() == "BEGIN_RECORD":
            in_record = True
            current_record = [line]
        elif line.strip() == "END_RECORD" and in_record:
            current_record.append(line)
            records.append("".join(current_record))
            in_record = False
            current_record = []
        elif in_record:
            current_record.append(line)
    return records


def test_sanitizer_clean_corpus():
    clean_files = glob.glob("/app/corpus/clean/*.log.gz")
    failed_files = []
    with tempfile.TemporaryDirectory() as tmpdir:
        for clean_file in clean_files:
            out_file = os.path.join(tmpdir, os.path.basename(clean_file).replace(".log.gz", ".log"))
            result = subprocess.run([SANITIZER, clean_file, out_file], capture_output=True)
            if result.returncode != 0:
                failed_files.append(f"{os.path.basename(clean_file)} (exit code {result.returncode})")
                continue
            with gzip.open(clean_file, "rt", encoding="utf-8") as f:
                expected_content = f.read()
            if not os.path.isfile(out_file):
                failed_files.append(f"{os.path.basename(clean_file)} (output file not created)")
                continue
            with open(out_file, "r", encoding="utf-8") as f:
                actual_content = f.read()
            if expected_content != actual_content:
                failed_files.append(f"{os.path.basename(clean_file)} (content mismatch)")
    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean modified or failed: " + ", ".join(failed_files)


def test_sanitizer_evil_corpus():
    evil_files = glob.glob("/app/corpus/evil/*.log.gz")
    failed_files = []
    with tempfile.TemporaryDirectory() as tmpdir:
        for evil_file in evil_files:
            out_file = os.path.join(tmpdir, os.path.basename(evil_file).replace(".log.gz", ".log"))
            result = subprocess.run([SANITIZER, evil_file, out_file], capture_output=True)
            if result.returncode != 1:
                failed_files.append(f"{os.path.basename(evil_file)} (exit code {result.returncode} instead of 1)")
                continue
            with gzip.open(evil_file, "rt", encoding="utf-8") as f:
                original_content = f.read()
            expected_content = "".join(r for r in get_records(original_content) if "../" not in r and "MALICIOUS" not in r)
            if not os.path.isfile(out_file):
                failed_files.append(f"{os.path.basename(evil_file)} (output file not created)")
                continue
            with open(out_file, "r", encoding="utf-8") as f:
                actual_content = f.read()
            if expected_content != actual_content:
                failed_files.append(f"{os.path.basename(evil_file)} (content mismatch)")
    assert not failed_files, f"{len(failed_files)} of {len(evil_files)} evil bypassed or failed: " + ", ".join(failed_files)


@pytest.fixture(scope="session")
def rebuilt_sanitizer(tmp_path_factory):
    td = tmp_path_factory.mktemp("rebuilt")
    binary = td / "sanitizer_from_source"
    result = run(["gcc", "-O2", "-Wall", "-Wextra", SOURCE, "-o", str(binary), "-lz"])
    assert result.returncode == 0, "sanitize_logs.c did not compile:\n" + result.stderr.decode(errors="replace")
    return str(binary)


def assert_direct_gzip(binary):
    symbols = run(["nm", "-D", binary])
    assert symbols.returncode == 0, f"Could not inspect {binary}"
    text = symbols.stdout.decode(errors="replace")
    assert re.search(r"\b(gzopen64?|gzdopen|gzread|gzgets|gzgetc|inflate)\b", text), \
        f"{binary} does not directly use a zlib gzip/inflate API"


def test_source_builds_and_uses_direct_gzip(rebuilt_sanitizer):
    assert_direct_gzip(rebuilt_sanitizer)
    assert_direct_gzip(SANITIZER)


@pytest.fixture(scope="session")
def atomic_tracer(tmp_path_factory):
    td = tmp_path_factory.mktemp("tracer")
    source = td / "trace.c"
    library = td / "trace.so"
    source.write_text(r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>

static void note(const char *kind, unsigned long long ino, const char *a, const char *b) {
    const char *p = getenv("SANITIZER_TRACE");
    if (!p) return;
    char buf[4096];
    int n = snprintf(buf, sizeof(buf), "%s|%llu|%s|%s\n", kind, ino, a ? a : "", b ? b : "");
    int fd = syscall(SYS_openat, AT_FDCWD, p, O_WRONLY|O_CREAT|O_APPEND, 0600);
    if (fd >= 0) { syscall(SYS_write, fd, buf, n); syscall(SYS_close, fd); }
}
int fflush(FILE *f) {
    static int (*real_fn)(FILE *);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "fflush");
    int rc = real_fn(f);
    if (f && rc == 0) { struct stat st; if (fstat(fileno(f), &st) == 0) note("F", st.st_ino, "", ""); }
    return rc;
}
int fsync(int fd) {
    static int (*real_fn)(int);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "fsync");
    int rc = real_fn(fd);
    if (rc == 0) { struct stat st; if (fstat(fd, &st) == 0) note("S", st.st_ino, "", ""); }
    return rc;
}
int fdatasync(int fd) {
    static int (*real_fn)(int);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "fdatasync");
    int rc = real_fn(fd);
    if (rc == 0) { struct stat st; if (fstat(fd, &st) == 0) note("S", st.st_ino, "", ""); }
    return rc;
}
int rename(const char *oldp, const char *newp) {
    static int (*real_fn)(const char *, const char *);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "rename");
    struct stat st; unsigned long long ino = stat(oldp, &st) == 0 ? st.st_ino : 0;
    int rc = real_fn(oldp, newp);
    if (rc == 0) note("R", ino, oldp, newp);
    return rc;
}
''')
    result = run(["gcc", "-shared", "-fPIC", str(source), "-o", str(library), "-ldl"])
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    return str(library)


def verify_atomic_trace(trace_path, output_path):
    events = []
    with open(trace_path, encoding="utf-8") as f:
        for line in f:
            kind, inode, old, new = line.rstrip("\n").split("|", 3)
            events.append((kind, int(inode), old, new))
    destination = os.path.abspath(output_path)
    renames = [(i, e) for i, e in enumerate(events) if e[0] == "R" and os.path.abspath(e[3]) == destination]
    assert renames, "Output was not installed with rename()."
    rename_index, rename_event = renames[-1]
    inode = rename_event[1]
    assert inode != 0 and os.path.abspath(rename_event[2]) != destination, "rename() did not move a temporary file into place."
    flushes = [i for i, e in enumerate(events[:rename_index]) if e[0] == "F" and e[1] == inode]
    syncs = [i for i, e in enumerate(events[:rename_index]) if e[0] == "S" and e[1] == inode]
    assert flushes, "Temporary output was not flushed before rename()."
    assert syncs, "Temporary output was not fsync/fdatasync'd before rename()."
    assert any(f < s for f in flushes for s in syncs), "Output must be flushed before it is synced and renamed."


def exercise_dynamic(binary, tracer, malicious):
    nonce = secrets.token_hex(16)
    records = [
        f"BEGIN_RECORD\nclean alpha {nonce}\nvalue={secrets.token_hex(11)}\nEND_RECORD\n",
        f"BEGIN_RECORD\nclean beta {secrets.token_hex(13)}\nEND_RECORD\n",
        f"BEGIN_RECORD\nclean gamma {secrets.token_hex(15)}\nEND_RECORD\n",
    ]
    if malicious:
        records.insert(1, f"BEGIN_RECORD\nprivate/{nonce}/../../secret\nEND_RECORD\n")
        records.append(f"BEGIN_RECORD\ntag-{nonce}-MALICIOUS-payload\nEND_RECORD\n")
    text = "".join(records)
    expected = "".join(r for r in get_records(text) if "../" not in r and "MALICIOUS" not in r)

    with tempfile.TemporaryDirectory(prefix="unpredictable_sanitizer_case_") as td:
        input_path = os.path.join(td, secrets.token_hex(12) + ".log.gz")
        output_path = os.path.join(td, secrets.token_hex(12) + ".txt")
        trace_path = os.path.join(td, "trace-" + secrets.token_hex(8))
        with gzip.open(input_path, "wt", encoding="utf-8") as f:
            f.write(text)
        with open(output_path, "w", encoding="utf-8") as f:
            f.write("PREEXISTING SENTINEL " + secrets.token_hex(8))

        env = os.environ.copy()
        env["LD_PRELOAD"] = tracer
        env["SANITIZER_TRACE"] = trace_path
        result = subprocess.run([binary, input_path, output_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        assert result.returncode == (1 if malicious else 0), \
            f"Unexpected exit {result.returncode} for randomized {'evil' if malicious else 'clean'} input"
        assert os.path.isfile(output_path), "Randomized output was not created."
        with open(output_path, encoding="utf-8") as f:
            assert f.read() == expected, "Randomized sanitized content was incorrect."
        assert os.path.isfile(trace_path), "No atomic-write trace was produced."
        verify_atomic_trace(trace_path, output_path)


def test_randomized_clean_and_evil_inputs(rebuilt_sanitizer, atomic_tracer):
    for binary in (SANITIZER, rebuilt_sanitizer):
        exercise_dynamic(binary, atomic_tracer, False)
        exercise_dynamic(binary, atomic_tracer, True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
