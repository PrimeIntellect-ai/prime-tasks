#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import glob
import json
import os
import random
import re
import shutil
import subprocess
import tempfile
import uuid


def run_videdit(args, cwd=None, env=None, timeout=30):
    return subprocess.run(
        ["/home/user/videdit/videdit"] + args,
        cwd=cwd,
        env=env,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def runtime_env(extra=None):
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = "/home/user/videdit:" + env.get("LD_LIBRARY_PATH", "")
    if extra:
        env.update(extra)
    return env


def test_videdit_executable_exists():
    videdit_path = "/home/user/videdit/videdit"
    assert os.path.isfile(videdit_path), f"Executable not found at {videdit_path}"
    assert os.access(videdit_path, os.X_OK), f"File at {videdit_path} is not executable"


def test_libvalidator_exists():
    lib_path = "/home/user/videdit/libvalidator.so"
    assert os.path.isfile(lib_path), f"Shared library not found at {lib_path}"


def test_required_sources_and_cgo_usage():
    validator_source = "/home/user/videdit/validator.c"
    main_source = "/home/user/videdit/main.go"
    assert os.path.isfile(validator_source), "validator.c is missing"
    assert os.path.isfile(main_source), "main.go is missing"

    c_text = open(validator_source, encoding="utf-8", errors="replace").read()
    assert re.search(r"\bint\s+validate_patch\s*\(\s*const\s+char\s*\*", c_text), \
        "validator.c does not define the required validate_patch ABI"

    go_text = "\n".join(
        open(path, encoding="utf-8", errors="replace").read()
        for path in glob.glob("/home/user/videdit/*.go")
    )
    assert re.search(r'import\s*(?:\(\s*)?"C"', go_text), "Go source does not use cgo"
    assert re.search(r"\bC\s*\.\s*validate_patch\b", go_text), \
        "Go source does not call the C validate_patch function"


def test_libvalidator_abi_and_random_content():
    lib = ctypes.CDLL("/home/user/videdit/libvalidator.so")
    validate = lib.validate_patch
    validate.argtypes = [ctypes.c_char_p]
    validate.restype = ctypes.c_int

    nonce = uuid.uuid4().hex
    cases = [
        ("--- a/file_[RESTRICTED]\n+++ b/file_[METADATA]\n@@ -1 +1 @@\n context\n", 1),
        (f"--- a/x\n+++ b/x\n@@ -1 +1 @@\n-old {nonce}\n+new {nonce}\n", 1),
        (f"--- a/x\n+++ b/x\n@@ -1 +1 @@\n-old {nonce} [RESTRICTED]\n+new\n", 0),
        (f"--- a/x\n+++ b/x\n@@ -1 +1 @@\n-old\n+new {nonce} [METADATA]\n", 0),
        ("--- a/x\n+++ b/x\n@@ -1 +1 @@\n [RESTRICTED] context only\n unchanged\n", 1),
    ]

    with tempfile.TemporaryDirectory() as td:
        for index, (content, expected) in enumerate(cases):
            path = os.path.join(td, f"case_{uuid.uuid4().hex}_{index}.patch")
            with open(path, "w", encoding="utf-8") as f:
                f.write(content)
            assert validate(os.fsencode(path)) == expected, \
                f"validate_patch returned the wrong result for generated case {index}"


def test_adversarial_corpus_check():
    videdit_path = "/home/user/videdit/videdit"
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    clean_patches = glob.glob(os.path.join(clean_dir, "*.patch"))
    evil_patches = glob.glob(os.path.join(evil_dir, "*.patch"))

    assert len(clean_patches) > 0, "No clean patches found to test against."
    assert len(evil_patches) > 0, "No evil patches found to test against."

    with tempfile.TemporaryDirectory() as temp_dir:
        for p in clean_patches + evil_patches:
            shutil.copy(p, temp_dir)

        result = subprocess.run(
            [videdit_path, "check", temp_dir],
            capture_output=True,
            text=True,
            env=runtime_env()
        )

        output_lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]

        results_map = {}
        for line in output_lines:
            if ":" in line:
                fname, status = line.split(":", 1)
                results_map[fname.strip()] = status.strip()

        clean_modified = []
        for p in clean_patches:
            basename = os.path.basename(p)
            if results_map.get(basename) != "CLEAN":
                clean_modified.append(basename)

        evil_bypassed = []
        for p in evil_patches:
            basename = os.path.basename(p)
            if results_map.get(basename) != "EVIL":
                evil_bypassed.append(basename)

        error_msgs = []
        if evil_bypassed:
            error_msgs.append(f"{len(evil_bypassed)} of {len(evil_patches)} evil bypassed: {', '.join(evil_bypassed)}")
        if clean_modified:
            error_msgs.append(f"{len(clean_modified)} of {len(clean_patches)} clean modified (rejected): {', '.join(clean_modified)}")

        assert not error_msgs, " | ".join(error_msgs)


def test_randomized_check_uses_shared_library_and_runs_concurrently():
    mock_source = r'''
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdatomic.h>

static atomic_int active = 0;
static atomic_int maximum = 0;

int validate_patch(const char *filepath) {
    int now = atomic_fetch_add(&active, 1) + 1;
    int seen = atomic_load(&maximum);
    while (now > seen && !atomic_compare_exchange_weak(&maximum, &seen, now)) { }
    usleep(120000);

    FILE *f = fopen(filepath, "r");
    int clean = 1;
    char *line = NULL;
    size_t cap = 0;
    if (!f) clean = 0;
    while (f && getline(&line, &cap, f) != -1) {
        if ((line[0] == '+' && strncmp(line, "+++", 3) != 0) ||
            (line[0] == '-' && strncmp(line, "---", 3) != 0)) {
            if (strstr(line, "[RESTRICTED]") || strstr(line, "[METADATA]")) clean = 0;
        }
    }
    free(line);
    if (f) fclose(f);
    atomic_fetch_sub(&active, 1);
    return clean;
}

__attribute__((destructor)) static void report_maximum(void) {
    const char *path = getenv("VIDEDIT_CONCURRENCY_MARKER");
    if (path) {
        FILE *f = fopen(path, "w");
        if (f) { fprintf(f, "%d\n", atomic_load(&maximum)); fclose(f); }
    }
}
'''
    with tempfile.TemporaryDirectory() as td:
        mock_c = os.path.join(td, "mock.c")
        mock_so = os.path.join(td, "libvalidator.so")
        marker = os.path.join(td, "maximum.txt")
        patch_dir = os.path.join(td, "patches")
        os.mkdir(patch_dir)
        with open(mock_c, "w") as f:
            f.write(mock_source)
        subprocess.run(
            ["gcc", "-shared", "-fPIC", "-O2", "-o", mock_so, mock_c],
            check=True, capture_output=True, text=True
        )

        expected = {}
        token = uuid.uuid4().hex
        for i in range(12):
            name = f"generated_{token}_{random.randrange(10**8)}_{i}.patch"
            evil = i % 3 != 0
            marker_text = "[RESTRICTED]" if i % 2 else "[METADATA]"
            changed = f"+random payload {token} {i}" + (f" {marker_text}" if evil else "")
            content = f"--- a/{token}_{i}\n+++ b/{token}_{i}\n@@ -1 +1 @@\n-old value {i}\n{changed}\n"
            with open(os.path.join(patch_dir, name), "w") as f:
                f.write(content)
            expected[name] = "EVIL" if evil else "CLEAN"

        env = os.environ.copy()
        env["LD_LIBRARY_PATH"] = td + ":/home/user/videdit:" + env.get("LD_LIBRARY_PATH", "")
        env["VIDEDIT_CONCURRENCY_MARKER"] = marker
        result = run_videdit(["check", patch_dir], env=env, timeout=20)
        assert result.returncode == 0, result.stderr

        lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
        assert len(lines) == len(expected), "check must emit exactly one result per generated patch"
        actual = {}
        for line in lines:
            match = re.fullmatch(r"([^:]+): (CLEAN|EVIL)", line)
            assert match, f"Output line has the wrong format: {line!r}"
            assert match.group(1) not in actual, f"Duplicate result for {match.group(1)}"
            actual[match.group(1)] = match.group(2)
        assert actual == expected, "Generated patch contents were not classified correctly"
        assert os.path.isfile(marker), "videdit did not call the dynamically linked validate_patch ABI"
        maximum = int(open(marker).read().strip())
        assert maximum >= 2, "Patch validation calls did not overlap; processing appears sequential"


def test_thumbnail_extraction():
    videdit_path = "/home/user/videdit/videdit"
    video_path = "/app/video.mp4"

    with tempfile.TemporaryDirectory() as temp_dir:
        result = subprocess.run(
            [videdit_path, "thumb", video_path],
            cwd=temp_dir,
            capture_output=True,
            text=True,
            env=runtime_env()
        )

        assert "Thumbnail extracted" in result.stdout, "Expected 'Thumbnail extracted' in stdout"

        thumb_path = os.path.join(temp_dir, "thumb.jpg")
        assert os.path.isfile(thumb_path), "thumb.jpg was not created in the working directory"

        with open(thumb_path, "rb") as f:
            header = f.read(2)
            assert header == b"\xff\xd8", "Extracted thumb.jpg is not a valid JPEG file"


def test_thumbnail_is_ffmpeg_frame_at_five_seconds():
    with tempfile.TemporaryDirectory() as td:
        work = os.path.join(td, "work")
        bindir = os.path.join(td, "bin")
        os.mkdir(work)
        os.mkdir(bindir)
        video = os.path.join(td, "generated.mkv")
        log = os.path.join(td, "ffmpeg_calls.jsonl")

        before = tuple(random.randint(30, 90) for _ in range(3))
        after = tuple(random.randint(165, 225) for _ in range(3))
        c1 = ''.join(f'{x:02x}' for x in before)
        c2 = ''.join(f'{x:02x}' for x in after)
        graph = (
            f"color=c=0x{c1}:s=160x90:r=2:d=5[a];"
            f"color=c=0x{c2}:s=160x90:r=2:d=3[b];"
            "[a][b]concat=n=2:v=1:a=0[v]"
        )
        subprocess.run(
            ["/usr/bin/ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
             "-filter_complex", graph, "-map", "[v]", "-c:v", "ffv1", video],
            check=True
        )

        wrapper = os.path.join(bindir, "ffmpeg")
        with open(wrapper, "w") as f:
            f.write("""#!/usr/bin/python3
import json, os, sys
with open(os.environ['FFMPEG_CALL_LOG'], 'a') as out:
    out.write(json.dumps(sys.argv[1:]) + '\\n')
os.execv('/usr/bin/ffmpeg', ['/usr/bin/ffmpeg'] + sys.argv[1:])
""")
        os.chmod(wrapper, 0o755)

        env = runtime_env({
            "PATH": bindir + ":" + os.environ.get("PATH", ""),
            "FFMPEG_CALL_LOG": log,
        })
        result = run_videdit(["thumb", video], cwd=work, env=env, timeout=30)
        assert result.returncode == 0, result.stderr
        assert "Thumbnail extracted" in result.stdout
        thumb = os.path.join(work, "thumb.jpg")
        assert os.path.isfile(thumb), "thumb.jpg was not created"

        assert os.path.isfile(log), "The thumb command did not invoke ffmpeg from PATH"
        calls = [json.loads(line) for line in open(log) if line.strip()]

        def is_required_extraction(args):
            if video not in args:
                return False
            outputs_thumb = any(
                arg == "thumb.jpg" or os.path.abspath(os.path.join(work, arg)) == thumb
                for arg in args if not arg.startswith("-")
            )
            if not outputs_thumb:
                return False
            seek_ok = False
            frame_ok = False
            for i, arg in enumerate(args[:-1]):
                if arg == "-ss":
                    value = args[i + 1]
                    try:
                        seconds = float(value)
                    except ValueError:
                        parts = value.split(":")
                        try:
                            seconds = sum(float(v) * (60 ** p) for p, v in enumerate(reversed(parts)))
                        except ValueError:
                            continue
                    seek_ok = abs(seconds - 5.0) < 0.001
                if arg in ("-frames:v", "-vframes", "-frames") and args[i + 1] == "1":
                    frame_ok = True
            return seek_ok and frame_ok

        assert any(is_required_extraction(call) for call in calls), \
            "ffmpeg was not invoked for the input at 5 seconds with exactly one output frame"

        probe = subprocess.run(
            ["/usr/bin/ffprobe", "-v", "error", "-count_frames", "-select_streams", "v:0",
             "-show_entries", "stream=nb_read_frames", "-of", "default=nw=1:nk=1", thumb],
            check=True, capture_output=True, text=True
        )
        assert probe.stdout.strip() == "1", "thumb.jpg does not contain exactly one frame"

        decoded = subprocess.run(
            ["/usr/bin/ffmpeg", "-v", "error", "-i", thumb, "-vf", "scale=1:1",
             "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
            check=True, capture_output=True
        ).stdout
        assert len(decoded) >= 3, "Could not decode generated thumbnail"
        observed = tuple(decoded[:3])
        assert all(abs(observed[i] - after[i]) <= 35 for i in range(3)), \
            f"Thumbnail is not the generated video's frame at 5 seconds: {observed} vs {after}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
