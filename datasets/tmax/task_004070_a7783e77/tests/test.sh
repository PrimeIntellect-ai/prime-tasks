#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile
import uuid
import pytest


def test_video_frames_extracted():
    frames_dir = "/home/user/dataset/frames"
    assert os.path.isdir(frames_dir), f"Directory {frames_dir} does not exist."

    files = os.listdir(frames_dir)
    jpg_files = [f for f in files if f.endswith(".jpg")]
    expected_frames = [f"frame_{i:04d}.jpg" for i in range(1, 13)]

    missing = set(expected_frames) - set(jpg_files)
    extra = set(jpg_files) - set(expected_frames)

    assert not missing, f"Missing expected frames: {sorted(list(missing))}"
    assert not extra, f"Found unexpected extra frames: {sorted(list(extra))}"
    assert len(jpg_files) == 12, f"Expected exactly 12 frames, found {len(jpg_files)}"


def decode_rgb(path):
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, f"Could not decode {path}: {result.stderr.decode(errors='replace')}"
    assert result.stdout, f"Decoded image {path} was empty"
    return result.stdout


def test_video_frames_match_video_content():
    with tempfile.TemporaryDirectory(prefix="expected_frames_") as reference_dir:
        pattern = os.path.join(reference_dir, "frame_%04d.jpg")
        result = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", "/app/experiment.mp4", "-vf", "fps=1", pattern],
            capture_output=True,
            timeout=30,
        )
        assert result.returncode == 0, result.stderr.decode(errors="replace")

        reference_files = sorted(f for f in os.listdir(reference_dir) if f.endswith(".jpg"))
        assert reference_files == [f"frame_{i:04d}.jpg" for i in range(1, 13)]

        for name in reference_files:
            submitted = decode_rgb(os.path.join("/home/user/dataset/frames", name))
            expected = decode_rgb(os.path.join(reference_dir, name))
            assert len(submitted) == len(expected), f"{name} has incorrect dimensions or pixel format"
            mean_error = sum(abs(a - b) for a, b in zip(submitted, expected)) / len(expected)
            assert mean_error <= 18.0, f"{name} does not match the corresponding frame from experiment.mp4 (MAE={mean_error:.2f})"


def get_script_path():
    py_script = "/home/user/backup_filter.py"
    sh_script = "/home/user/backup_filter.sh"
    if os.path.isfile(py_script):
        return py_script
    elif os.path.isfile(sh_script):
        return sh_script
    return None


def test_filter_script_exists_and_executable():
    script_path = get_script_path()
    assert script_path is not None, "Backup filter script not found at /home/user/backup_filter.py or /home/user/backup_filter.sh"
    assert os.access(script_path, os.X_OK) or script_path.endswith('.py'), f"Script {script_path} is not executable."


def run_filter_script(corpus_path, timeout=10):
    script_path = get_script_path()
    assert script_path is not None

    cmd = [script_path, corpus_path]
    if script_path.endswith('.py') and not os.access(script_path, os.X_OK):
        cmd = ["python3", script_path, corpus_path]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        assert result.returncode == 0, f"Script failed with return code {result.returncode}\nStderr: {result.stderr}"
        return [line.strip() for line in result.stdout.splitlines() if line.strip()]
    except subprocess.TimeoutExpired:
        pytest.fail("Script exceeded timeout, likely caught in an infinite loop.")


def test_clean_corpus_preserved():
    clean_dir = "/app/corpora/clean"
    output_lines = run_filter_script(clean_dir)

    expected_paths = []
    for root, dirs, files in os.walk(clean_dir):
        expected_paths.append(os.path.abspath(root))
        for d in dirs:
            expected_paths.append(os.path.abspath(os.path.join(root, d)))
        for f in files:
            expected_paths.append(os.path.abspath(os.path.join(root, f)))

    expected_paths = list(set(expected_paths))
    output_set = set(output_lines)
    missing = [p for p in expected_paths if p not in output_set]

    if missing:
        basenames = [os.path.basename(p) for p in missing]
        pytest.fail(f"{len(missing)} of {len(expected_paths)} clean modified/omitted. Offending: {basenames}")


def test_evil_corpus_filtered():
    evil_dir = "/app/corpora/evil"
    output_lines = run_filter_script(evil_dir)
    output_set = set(output_lines)

    evil_symlinks = [
        "loop1",
        "loop2",
        "loop3",
        "loop_dir/cyclic_sub",
        "escape_root",
        "escape_relative"
    ]
    evil_paths = [os.path.abspath(os.path.join(evil_dir, p)) for p in evil_symlinks]
    bypassed = [p for p in evil_paths if p in output_set]

    if bypassed:
        basenames = [os.path.basename(p) for p in bypassed]
        pytest.fail(f"{len(bypassed)} of {len(evil_paths)} evil bypassed. Offending: {basenames}")

    safe_paths = [
        os.path.abspath(evil_dir),
        os.path.abspath(os.path.join(evil_dir, "valid_file.txt")),
        os.path.abspath(os.path.join(evil_dir, "loop_dir"))
    ]
    missing_safe = [p for p in safe_paths if p not in output_set]
    if missing_safe:
        basenames = [os.path.basename(p) for p in missing_safe]
        pytest.fail(f"{len(missing_safe)} of {len(safe_paths)} clean modified/omitted in evil dir. Offending: {basenames}")


def test_filter_traverses_unseen_corpus_and_resolves_links():
    token = lambda: "n_" + uuid.uuid4().hex
    with tempfile.TemporaryDirectory(prefix="filter_dynamic_") as base:
        dir1 = os.path.join(base, token())
        dir2 = os.path.join(dir1, token())
        os.makedirs(dir2)

        root_file = os.path.join(base, token())
        deep_file = os.path.join(dir2, token())
        open(root_file, "wb").close()
        open(deep_file, "wb").close()

        safe_relative = os.path.join(base, token())
        os.symlink(os.path.relpath(deep_file, base), safe_relative)
        safe_absolute = os.path.join(dir1, token())
        os.symlink(root_file, safe_absolute)
        safe_chain_end = os.path.join(base, token())
        safe_chain_start = os.path.join(base, token())
        os.symlink(os.path.basename(root_file), safe_chain_end)
        os.symlink(os.path.basename(safe_chain_end), safe_chain_start)

        self_cycle = os.path.join(base, token())
        os.symlink(os.path.basename(self_cycle), self_cycle)

        mutual_a = os.path.join(base, token())
        mutual_b = os.path.join(base, token())
        os.symlink(os.path.basename(mutual_b), mutual_a)
        os.symlink(os.path.basename(mutual_a), mutual_b)

        ancestor_cycle = os.path.join(dir2, token())
        os.symlink("../..", ancestor_cycle)

        escape_absolute = os.path.join(base, token())
        os.symlink("/etc/passwd", escape_absolute)
        escape_relative = os.path.join(dir1, token())
        os.symlink("../../../etc/passwd", escape_relative)

        expected = {
            os.path.abspath(base),
            os.path.abspath(dir1),
            os.path.abspath(dir2),
            os.path.abspath(root_file),
            os.path.abspath(deep_file),
            os.path.abspath(safe_relative),
            os.path.abspath(safe_absolute),
            os.path.abspath(safe_chain_end),
            os.path.abspath(safe_chain_start),
        }
        dangerous = {
            os.path.abspath(self_cycle),
            os.path.abspath(mutual_a),
            os.path.abspath(mutual_b),
            os.path.abspath(ancestor_cycle),
            os.path.abspath(escape_absolute),
            os.path.abspath(escape_relative),
        }

        output = run_filter_script(base, timeout=5)
        assert all(os.path.isabs(p) for p in output), "Filter output must contain absolute paths only"
        assert len(output) == len(set(output)), "Filter emitted duplicate paths"
        output_set = set(output)
        assert not (output_set & dangerous), f"Dangerous links were emitted: {sorted(output_set & dangerous)}"
        assert output_set == expected, f"Unexpected traversal result; missing={sorted(expected-output_set)}, extra={sorted(output_set-expected)}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
