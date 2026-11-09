#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'HOOK_EOF' > /tmp/rename_hook.c
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>

static void record_rename(const char *oldpath, const char *newpath) {
    const char *logpath = getenv("RENAME_LOG");
    if (!logpath) return;
    FILE *f = fopen(logpath, "a");
    if (f) {
        fprintf(f, "R\t%s\t%s\n", oldpath ? oldpath : "", newpath ? newpath : "");
        fclose(f);
    }
}

int rename(const char *oldpath, const char *newpath) {
    static int (*real_fn)(const char *, const char *) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "rename");
    record_rename(oldpath, newpath);
    return real_fn(oldpath, newpath);
}

int renameat(int olddirfd, const char *oldpath, int newdirfd, const char *newpath) {
    static int (*real_fn)(int, const char *, int, const char *) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "renameat");
    record_rename(oldpath, newpath);
    return real_fn(olddirfd, oldpath, newdirfd, newpath);
}

int renameat2(int olddirfd, const char *oldpath, int newdirfd, const char *newpath, unsigned int flags) {
    static int (*real_fn)(int, const char *, int, const char *, unsigned int) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "renameat2");
    record_rename(oldpath, newpath);
    return real_fn(olddirfd, oldpath, newdirfd, newpath, flags);
}
HOOK_EOF
cc -shared -fPIC -o /tmp/rename_hook.so /tmp/rename_hook.c -ldl

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import io
import math
import os
import re
import subprocess
import tarfile
import tempfile
import uuid


def test_video_frames():
    video_path = "/app/project_demo.mp4"
    frames_dir = "/home/user/frames"

    assert os.path.isfile(video_path), f"Video file missing at {video_path}"
    assert os.path.isdir(frames_dir), f"Frames directory missing at {frames_dir}"

    result = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", video_path],
        capture_output=True, text=True
    )
    assert result.returncode == 0, "Failed to get video duration with ffprobe"
    duration = float(result.stdout.strip())
    duration_int = int(duration)

    frames = sorted(glob.glob(os.path.join(frames_dir, "frame_*.jpg")))
    assert len(frames) > 0, "No frames found in /home/user/frames/"
    assert abs(len(frames) - duration_int) <= 2, f"Expected around {duration_int} frames based on video length, got {len(frames)}"

    for i, frame_path in enumerate(frames, start=1):
        basename = os.path.basename(frame_path)
        assert re.match(r"^frame_\d{4}\.jpg$", basename), f"Frame name {basename} does not match expected format"
        expected_name = f"frame_{i:04d}.jpg"
        assert basename == expected_name, f"Frames not sequentially named correctly: expected {expected_name}, got {basename}"

    # Independently extract the expected 1-fps sequence and compare decoded images.
    with tempfile.TemporaryDirectory() as refs:
        ref_pattern = os.path.join(refs, "ref_%04d.jpg")
        made = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", video_path, "-vf", "fps=1", "-q:v", "2", ref_pattern],
            capture_output=True, text=True
        )
        assert made.returncode == 0, f"Could not create reference frames: {made.stderr}"
        reference_frames = sorted(glob.glob(os.path.join(refs, "ref_*.jpg")))
        assert len(frames) == len(reference_frames), (
            f"Exactly 1 fps should produce {len(reference_frames)} frames, got {len(frames)}"
        )

        for submitted, reference in zip(frames, reference_frames):
            probe = subprocess.run(
                ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "csv=p=0", submitted],
                capture_output=True, text=True
            )
            assert probe.returncode == 0 and probe.stdout.strip() == "1280,720", f"Invalid or incorrectly sized image: {submitted}"

            comparison = subprocess.run(
                ["ffmpeg", "-v", "info", "-i", submitted, "-i", reference,
                 "-lavfi", "psnr", "-frames:v", "1", "-f", "null", "-"],
                capture_output=True, text=True
            )
            assert comparison.returncode == 0, f"Could not decode/compare {submitted}"
            match = re.search(r"average:([0-9.]+|inf)", comparison.stderr)
            assert match, f"No image comparison result for {submitted}"
            psnr = math.inf if match.group(1) == "inf" else float(match.group(1))
            assert psnr >= 28.0, f"{submitted} does not correspond to the expected video frame (PSNR {psnr})"


def test_safe_tar_evil_corpus():
    binary = "/home/user/safe_tar/target/release/safe_tar"
    assert os.path.isfile(binary), f"Compiled binary missing at {binary}"
    assert os.access(binary, os.X_OK), f"Binary at {binary} is not executable"

    evil_dir = "/app/corpus/evil"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing at {evil_dir}"
    evil_files = [f for f in os.listdir(evil_dir) if f.endswith('.tar')]
    assert len(evil_files) > 0, "No evil tar files found to test against"

    failed = []
    for f in evil_files:
        tar_path = os.path.join(evil_dir, f)
        with tempfile.TemporaryDirectory() as tmpdir:
            result = subprocess.run([binary, tar_path, tmpdir], capture_output=True, text=True)
            stdout = result.stdout.strip()
            if result.returncode != 1 or stdout != "REJECT":
                failed.append(f"{f} (exit code {result.returncode}, stdout: {stdout})")
            elif os.listdir(tmpdir):
                failed.append(f"{f} (output directory not empty after rejection)")
    assert not failed, f"{len(failed)} of {len(evil_files)} evil bypassed: {', '.join(failed)}"


def test_safe_tar_clean_corpus():
    binary = "/home/user/safe_tar/target/release/safe_tar"
    assert os.path.isfile(binary), f"Compiled binary missing at {binary}"

    clean_dir = "/app/corpus/clean"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing at {clean_dir}"
    clean_files = [f for f in os.listdir(clean_dir) if f.endswith('.tar')]
    assert len(clean_files) > 0, "No clean tar files found to test against"

    failed = []
    for f in clean_files:
        tar_path = os.path.join(clean_dir, f)
        with tempfile.TemporaryDirectory() as tmpdir:
            result = subprocess.run([binary, tar_path, tmpdir], capture_output=True, text=True)
            stdout = result.stdout.strip()
            if result.returncode != 0 or stdout != "ACCEPT":
                failed.append(f"{f} (exit code {result.returncode}, stdout: {stdout})")
            elif not os.listdir(tmpdir):
                failed.append(f"{f} (output directory empty after acceptance)")
    assert not failed, f"{len(failed)} of {len(clean_files)} clean modified/rejected: {', '.join(failed)}"


def add_bytes(tar, name, data):
    info = tarfile.TarInfo(name)
    info.size = len(data)
    info.mode = 0o640
    tar.addfile(info, io.BytesIO(data))


def invoke(binary, archive, output, env=None):
    result = subprocess.run([binary, archive, output], capture_output=True, text=True, env=env)
    return result


def test_safe_tar_generated_archives_and_atomic_writes():
    binary = "/home/user/safe_tar/target/release/safe_tar"
    token = uuid.uuid4().hex

    with tempfile.TemporaryDirectory(prefix="generated_safe_tar_") as root:
        clean_tar = os.path.join(root, f"input_{token}.tar")
        expected = {
            f"project_{token}/README.txt": b"generated clean data\n",
            f"project_{token}/assets/blob.bin": os.urandom(1024 * 1024 + 137),
            f"project_{token}/empty.dat": b"",
        }
        with tarfile.open(clean_tar, "w") as tar:
            directory = tarfile.TarInfo(f"project_{token}")
            directory.type = tarfile.DIRTYPE
            directory.mode = 0o750
            tar.addfile(directory)
            subdirectory = tarfile.TarInfo(f"project_{token}/assets")
            subdirectory.type = tarfile.DIRTYPE
            subdirectory.mode = 0o750
            tar.addfile(subdirectory)
            for name, data in expected.items():
                add_bytes(tar, name, data)

        output = os.path.join(root, "clean_output")
        os.mkdir(output)
        rename_log = os.path.join(root, "renames.log")
        env = os.environ.copy()
        env["LD_PRELOAD"] = "/tmp/rename_hook.so"
        env["RENAME_LOG"] = rename_log
        result = invoke(binary, clean_tar, output, env)
        assert result.returncode == 0, f"Generated clean archive rejected: {result.stderr}"
        assert result.stdout.strip() == "ACCEPT", f"Generated clean archive output was {result.stdout!r}"

        actual_files = set()
        for current, dirs, files in os.walk(output):
            for filename in files:
                path = os.path.join(current, filename)
                assert not os.path.islink(path), f"Unexpected extracted symlink: {path}"
                relative = os.path.relpath(path, output)
                actual_files.add(relative)
                with open(path, "rb") as f:
                    assert f.read() == expected[relative], f"Wrong extracted contents for {relative}"
        assert actual_files == set(expected), f"Unexpected extracted file set: {actual_files}"
        assert not any("tmp" in name.lower() for _, _, files in os.walk(output) for name in files), "Temporary extraction files remain"

        assert os.path.isfile(rename_log), "No atomic rename operations were observed"
        operations = []
        with open(rename_log, encoding="utf-8", errors="replace") as f:
            for line in f:
                parts = line.rstrip("\n").split("\t", 2)
                if len(parts) == 3 and parts[0] == "R":
                    operations.append((parts[1], parts[2]))
        for relative in expected:
            final_name = os.path.basename(relative)
            matching = [(old, new) for old, new in operations if os.path.basename(new) == final_name]
            assert matching, f"No atomic rename into final file {relative} was observed"
            assert any(os.path.basename(old) != os.path.basename(new) for old, new in matching), (
                f"{relative} was not renamed from a temporary name"
            )

        evil_cases = []

        traversal_tar = os.path.join(root, f"traversal_{token}.tar")
        with tarfile.open(traversal_tar, "w") as tar:
            add_bytes(tar, f"../escaped_{token}", b"escape")
        evil_cases.append((traversal_tar, os.path.join(root, f"escaped_{token}")))

        embedded_parent_tar = os.path.join(root, f"embedded_{token}.tar")
        with tarfile.open(embedded_parent_tar, "w") as tar:
            add_bytes(tar, f"safe_{token}/../forbidden.txt", b"bad")
        evil_cases.append((embedded_parent_tar, None))

        absolute_target = os.path.join("/tmp", f"safe_tar_absolute_{token}")
        if os.path.lexists(absolute_target):
            os.unlink(absolute_target)
        absolute_tar = os.path.join(root, f"absolute_{token}.tar")
        with tarfile.open(absolute_tar, "w") as tar:
            add_bytes(tar, absolute_target, b"absolute")
        evil_cases.append((absolute_tar, absolute_target))

        symlink_tar = os.path.join(root, f"symlink_{token}.tar")
        with tarfile.open(symlink_tar, "w") as tar:
            info = tarfile.TarInfo(f"link_{token}")
            info.type = tarfile.SYMTYPE
            info.linkname = f"target_{token}"
            tar.addfile(info)
        evil_cases.append((symlink_tar, None))

        hardlink_tar = os.path.join(root, f"hardlink_{token}.tar")
        with tarfile.open(hardlink_tar, "w") as tar:
            add_bytes(tar, f"target_{token}", b"target")
            info = tarfile.TarInfo(f"hardlink_{token}")
            info.type = tarfile.LNKTYPE
            info.linkname = f"target_{token}"
            tar.addfile(info)
        evil_cases.append((hardlink_tar, None))

        # A valid file before the invalid entry ensures partial extraction is cleaned up.
        mixed_tar = os.path.join(root, f"mixed_{token}.tar")
        mixed_escape = os.path.join(root, f"mixed_escape_{token}")
        with tarfile.open(mixed_tar, "w") as tar:
            add_bytes(tar, f"valid_before_{token}.txt", b"must be removed")
            add_bytes(tar, f"../mixed_escape_{token}", b"must not escape")
        evil_cases.append((mixed_tar, mixed_escape))

        for index, (archive, escaped_path) in enumerate(evil_cases):
            evil_output = os.path.join(root, f"evil_output_{index}")
            os.mkdir(evil_output)
            result = invoke(binary, archive, evil_output)
            assert result.returncode == 1, f"Generated evil archive accepted: {os.path.basename(archive)}"
            assert result.stdout.strip() == "REJECT", f"Wrong rejection output for {archive}: {result.stdout!r}"
            assert os.listdir(evil_output) == [], f"Partial files remained after rejecting {archive}"
            if escaped_path is not None:
                assert not os.path.lexists(escaped_path), f"Archive wrote outside output directory: {escaped_path}"

        if os.path.lexists(absolute_target):
            os.unlink(absolute_target)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
