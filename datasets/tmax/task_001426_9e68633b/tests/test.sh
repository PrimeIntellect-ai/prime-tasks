#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import tempfile
import uuid


def run_detector(directory):
    return subprocess.run(
        ["python3", "/home/user/detector.py", directory],
        capture_output=True,
        text=True
    )


def output_lines(result):
    return {line.strip() for line in result.stdout.splitlines() if line.strip()}


def test_detector_script_exists():
    script_path = "/home/user/detector.py"
    assert os.path.isfile(script_path), f"Detector script not found at {script_path}"


def test_clean_corpus_accepted():
    clean_dir = "/app/corpus/clean/"
    expected_files = {f for f in os.listdir(clean_dir) if f.endswith(".json")}
    assert len(expected_files) > 0, "No clean files found to test."

    result = run_detector(clean_dir)
    assert result.returncode == 0, f"Script failed on clean corpus with error: {result.stderr}"

    actual = output_lines(result)
    missing = expected_files - actual
    extra = actual - expected_files
    assert not missing, f"{len(missing)} of {len(expected_files)} clean files were incorrectly rejected: {missing}"
    assert not extra, f"Script output unexpected lines for clean corpus: {extra}"


def test_evil_corpus_rejected():
    evil_dir = "/app/corpus/evil/"
    evil_files = {f for f in os.listdir(evil_dir) if f.endswith(".json")}
    assert len(evil_files) > 0, "No evil files found to test."

    result = run_detector(evil_dir)
    assert result.returncode == 0, f"Script failed on evil corpus with error: {result.stderr}"

    actual = output_lines(result)
    bypassed = actual.intersection(evil_files)
    assert not bypassed, f"{len(bypassed)} of {len(evil_files)} evil files bypassed the filter: {bypassed}"
    assert not actual, f"Script output unexpected lines for evil corpus: {actual}"


def test_mixed_corpus_with_neutral_randomized_names():
    clean_sources = sorted(
        os.path.join("/app/corpus/clean", f)
        for f in os.listdir("/app/corpus/clean") if f.endswith(".json")
    )
    evil_sources = sorted(
        os.path.join("/app/corpus/evil", f)
        for f in os.listdir("/app/corpus/evil") if f.endswith(".json")
    )
    assert clean_sources and evil_sources

    with tempfile.TemporaryDirectory(prefix="batch_") as mixed_dir:
        expected = set()
        items = [(p, True) for p in clean_sources] + [(p, False) for p in evil_sources]
        for source, is_clean in items:
            name = uuid.uuid4().hex + ".json"
            shutil.copyfile(source, os.path.join(mixed_dir, name))
            if is_clean:
                expected.add(name)

        result = run_detector(mixed_dir)
        assert result.returncode == 0, f"Script failed on mixed corpus with error: {result.stderr}"
        actual = output_lines(result)
        assert actual == expected, (
            f"Mixed-corpus classification was incorrect. Missing: {expected - actual}; "
            f"unexpected: {actual - expected}"
        )


def test_log_file_created():
    log_file = "/home/user/pipeline.log"
    assert os.path.isfile(log_file), f"Log file not created at {log_file}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
