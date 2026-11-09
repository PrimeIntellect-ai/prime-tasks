#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import re
import shutil
import subprocess
import tempfile


def run(cmd, timeout=120):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def parse_sanitiser_output(stdout):
    results = {}
    for line in stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        match = re.fullmatch(r"(.+?)\s+(PASS|FAIL)", line)
        assert match, f"Unexpected sanitiser output line: {line!r}"
        filename = os.path.basename(match.group(1))
        assert filename not in results, f"Duplicate result for {filename}"
        results[filename] = match.group(2)
    return results


def clear_frames():
    frames_dir = "/home/user/frames"
    os.makedirs(frames_dir, exist_ok=True)
    for path in glob.glob(os.path.join(frames_dir, "*")):
        if os.path.isdir(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)


def decode_rgb(path):
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        capture_output=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Invalid image {path}: {result.stderr.decode(errors='replace')}"
    assert len(result.stdout) == 320 * 240 * 3, f"Unexpected image dimensions or data size for {path}"
    return result.stdout


def mean_absolute_error(a, b):
    assert len(a) == len(b)
    return sum(abs(x - y) for x, y in zip(a, b)) / len(a)


def validate_recording_frames(start_second, count):
    frames = sorted(glob.glob("/home/user/frames/*.jpg"))
    assert len(frames) == count, f"Expected {count} recording frames, found {len(frames)}: {frames}"
    assert all(re.fullmatch(r"frame_\d{4}\.jpg", os.path.basename(p)) for p in frames), \
        f"Frames do not use frame_%04d.jpg naming: {frames}"

    with tempfile.TemporaryDirectory() as reference_dir:
        result = run([
            "ffmpeg", "-v", "error", "-i", "/app/fixture.mp4",
            "-vf", "fps=1", "-q:v", "2",
            os.path.join(reference_dir, "reference_%04d.jpg"),
        ])
        assert result.returncode == 0, f"Could not derive reference frames: {result.stderr}"
        references = sorted(glob.glob(os.path.join(reference_dir, "reference_*.jpg")))
        assert len(references) == 30
        reference_rgb = [decode_rgb(p) for p in references]

        for offset, frame in enumerate(frames):
            actual = decode_rgb(frame)
            expected_index = start_second + offset
            errors = [mean_absolute_error(actual, ref) for ref in reference_rgb]
            expected_error = errors[expected_index]
            assert expected_error < 25, \
                f"{frame} does not resemble video content at {expected_index}s (MAE {expected_error:.2f})"
            assert expected_error <= min(errors) + 3, \
                f"{frame} corresponds more closely to a time outside its RECORDING position"


def test_frames_extracted():
    frames_dir = "/home/user/frames"
    assert os.path.isdir(frames_dir), f"Directory {frames_dir} does not exist."

    jpg_files = glob.glob(os.path.join(frames_dir, "*.jpg"))
    assert len(jpg_files) == 10, f"Expected exactly 10 frames extracted, found {len(jpg_files)}: {jpg_files}"


def test_sanitiser_script_clean_corpus():
    sanitiser_path = "/home/user/sanitiser.py"
    clean_dir = "/home/user/metadata/clean/"

    assert os.path.isfile(sanitiser_path), f"Sanitiser script not found at {sanitiser_path}"

    result = subprocess.run(["python3", sanitiser_path, clean_dir], capture_output=True, text=True)
    assert result.returncode == 0, f"Sanitiser script failed on clean corpus with error:\n{result.stderr}"

    output_lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    clean_files = [f for f in os.listdir(clean_dir) if f.endswith('.json')]

    failed_clean = []
    for f in clean_files:
        found_pass = any(f in line and "PASS" in line for line in output_lines)
        if not found_pass:
            failed_clean.append(f)

    assert not failed_clean, f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected (expected PASS). Offending files: {failed_clean}"


def test_sanitiser_script_evil_corpus():
    sanitiser_path = "/home/user/sanitiser.py"
    evil_dir = "/home/user/metadata/evil/"

    assert os.path.isfile(sanitiser_path), f"Sanitiser script not found at {sanitiser_path}"

    result = subprocess.run(["python3", sanitiser_path, evil_dir], capture_output=True, text=True)
    assert result.returncode == 0, f"Sanitiser script failed on evil corpus with error:\n{result.stderr}"

    output_lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    evil_files = [f for f in os.listdir(evil_dir) if f.endswith('.json')]

    bypassed_evil = []
    for f in evil_files:
        found_fail = any(f in line and "FAIL" in line for line in output_lines)
        if not found_fail:
            bypassed_evil.append(f)

    assert not bypassed_evil, f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed (expected FAIL). Offending files: {bypassed_evil}"


def test_sanitiser_on_derived_corpus():
    sanitiser_path = "/home/user/sanitiser.py"
    with tempfile.TemporaryDirectory(prefix="metadata_audit_") as corpus:
        cases = {
            "holiday.json": ({"title": "Family Holiday", "tags": ["sea", "summer"]}, "PASS"),
            "notes.json": ({"title": "Tutorial", "details": {"author": "Ada", "topic": "video"}}, "PASS"),
            "markup.json": ({"caption": "<img src=x onerror=alert(1)>"}, "FAIL"),
            "database.json": ({"comment": "' UNION SELECT password FROM users --"}, "FAIL"),
            "nested.json": ({"a": {"b": {"c": {"d": "too deep"}}}}, "FAIL"),
        }
        for filename, (payload, _) in cases.items():
            with open(os.path.join(corpus, filename), "w") as handle:
                json.dump(payload, handle)
        with open(os.path.join(corpus, "broken.json"), "w") as handle:
            handle.write('{"title": "unterminated", "data": {')
        cases["broken.json"] = (None, "FAIL")

        result = run(["python3", sanitiser_path, corpus])
        assert result.returncode == 0, f"Sanitiser failed on derived corpus: {result.stderr}"
        observed = parse_sanitiser_output(result.stdout)
        expected = {name: verdict for name, (_, verdict) in cases.items()}
        assert observed == expected, f"Incorrect sanitiser decisions: expected {expected}, got {observed}"


def test_pipeline_executes_sanitiser_parser_video_and_benchmark():
    ci_script = "/home/user/ci_pipeline.sh"
    sanitiser = "/home/user/sanitiser.py"
    events = "/home/user/events.sml"
    benchmark = "/home/user/benchmark.log"
    assert os.path.isfile(ci_script)
    assert os.access(ci_script, os.X_OK)

    original_events = open(events, "rb").read()
    original_sanitiser = open(sanitiser, "rb").read()
    original_mode = os.stat(sanitiser).st_mode
    saved_sanitiser = "/home/user/.sanitiser.audit.original.py"
    call_log = "/tmp/sanitiser_calls.log"
    if os.path.exists(call_log):
        os.unlink(call_log)

    with open(saved_sanitiser, "wb") as handle:
        handle.write(original_sanitiser)
    wrapper = f'''#!/usr/bin/env python3
import subprocess, sys
with open({call_log!r}, "a") as log:
    log.write(" ".join(sys.argv[1:]) + "\\n")
result = subprocess.run(["python3", {saved_sanitiser!r}] + sys.argv[1:])
sys.exit(result.returncode)
'''

    try:
        with open(sanitiser, "w") as handle:
            handle.write(wrapper)
        os.chmod(sanitiser, 0o755)

        with open(events, "w") as handle:
            handle.write("STATE_CHANGE:INIT timestamp=00:00:00.000\n")
            handle.write("STATE_CHANGE:RECORDING timestamp=00:00:02.000\n")
            handle.write("STATE_CHANGE:PAUSED timestamp=00:00:06.000\n")
            handle.write("STATE_CHANGE:STOPPED timestamp=00:00:30.000\n")
        clear_frames()
        result = run([ci_script], timeout=180)
        assert result.returncode == 0, f"CI pipeline failed for a derived state log:\n{result.stdout}\n{result.stderr}"
        validate_recording_frames(2, 4)

        assert os.path.isfile(call_log), "CI pipeline did not invoke /home/user/sanitiser.py"
        calls = open(call_log).read()
        assert "/home/user/metadata/clean" in calls, "CI pipeline did not sanitise the clean corpus"
        assert "/home/user/metadata/evil" in calls, "CI pipeline did not sanitise the evil corpus"

        with open(events, "wb") as handle:
            handle.write(original_events)
        clear_frames()
        if os.path.exists(benchmark):
            os.unlink(benchmark)
        result = run([ci_script], timeout=180)
        assert result.returncode == 0, f"CI pipeline failed on the supplied inputs:\n{result.stdout}\n{result.stderr}"
        validate_recording_frames(5, 10)
        assert os.path.isfile(benchmark), "CI pipeline did not create benchmark.log"
        assert os.path.getsize(benchmark) > 0, "CI pipeline created an empty benchmark.log"
        benchmark_text = open(benchmark, errors="replace").read()
        assert re.search(r"(?:real|user|sys|elapsed|seconds?)", benchmark_text, re.I), \
            f"benchmark.log does not contain timing results: {benchmark_text!r}"
    finally:
        with open(events, "wb") as handle:
            handle.write(original_events)
        with open(sanitiser, "wb") as handle:
            handle.write(original_sanitiser)
        os.chmod(sanitiser, original_mode)
        if os.path.exists(saved_sanitiser):
            os.unlink(saved_sanitiser)


def test_ci_pipeline_and_benchmark():
    ci_script = "/home/user/ci_pipeline.sh"
    benchmark_log = "/home/user/benchmark.log"

    assert os.path.isfile(ci_script), f"CI pipeline script not found at {ci_script}"
    assert os.access(ci_script, os.X_OK), f"CI pipeline script {ci_script} is not executable"

    assert os.path.isfile(benchmark_log), f"Benchmark log not found at {benchmark_log}"
    assert os.path.getsize(benchmark_log) > 0, f"Benchmark log {benchmark_log} is empty"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
