#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import random
import struct
import subprocess
import tempfile
import threading
import uuid
import wave

import pytest

PIPELINE_DIR = "/home/user/math_pipeline"


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_constant_extracted():
    constant_file = "/home/user/constant.txt"
    assert os.path.isfile(constant_file), f"File {constant_file} does not exist."

    with open(constant_file, "r") as f:
        content = f.read().strip()

    assert content == "314159", f"Expected constant '314159', but got '{content}'."


def test_math_pipeline_tests_pass():
    assert os.path.isdir(PIPELINE_DIR), f"Directory {PIPELINE_DIR} does not exist."

    result = subprocess.run(
        ["pytest"],
        cwd=PIPELINE_DIR,
        capture_output=True,
        text=True
    )

    assert result.returncode == 0, f"pytest in {PIPELINE_DIR} failed. Output:\n{result.stdout}\n{result.stderr}"


def test_processor_preserves_all_concurrent_updates():
    processor_path = os.path.join(PIPELINE_DIR, "processor.py")
    metrics_path = os.path.join(PIPELINE_DIR, "metrics.json")
    assert os.path.isfile(processor_path), f"Missing {processor_path}"
    processor = load_module("processor_independent_check", processor_path)
    assert callable(getattr(processor, "update_metrics", None))

    for round_number in range(5):
        try:
            os.unlink(metrics_path)
        except FileNotFoundError:
            pass

        token = uuid.uuid4().hex
        expected = {
            f"verify_{token}_{i}": round_number * 1000 + i
            for i in range(50)
        }
        errors = []

        def invoke(key, value):
            try:
                processor.update_metrics(key, value)
            except BaseException as exc:
                errors.append(repr(exc))

        threads = [
            threading.Thread(target=invoke, args=(key, value))
            for key, value in expected.items()
        ]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()

        assert not errors, f"Concurrent update_metrics calls raised errors: {errors}"
        assert os.path.isfile(metrics_path), "update_metrics did not create metrics.json"
        with open(metrics_path, "r") as f:
            actual = json.load(f)
        assert actual == expected, (
            f"Concurrent updates were lost or corrupted: expected 50 exact entries, "
            f"got {len(actual)}"
        )


def make_wav_bytes(fmt_extra=b"", chunk_id=b"data", samples=b""):
    fmt_payload = struct.pack(
        "<HHIIHH", 1, 1, 44100, 44100 * 2, 2, 16
    ) + fmt_extra
    chunks = (
        b"fmt " + struct.pack("<I", len(fmt_payload)) + fmt_payload +
        chunk_id + struct.pack("<I", len(samples)) + samples
    )
    return b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks


def test_wav_parser_independent_18_byte_fmt_check():
    parser_path = os.path.join(PIPELINE_DIR, "wav_parser.py")
    assert os.path.isfile(parser_path), f"Missing {parser_path}"
    parser = load_module("wav_parser_independent_check", parser_path)
    assert callable(getattr(parser, "parse_wav", None))

    with tempfile.TemporaryDirectory(prefix="wavcheck_") as directory:
        valid_path = os.path.join(directory, uuid.uuid4().hex)
        invalid_path = os.path.join(directory, uuid.uuid4().hex)

        with open(valid_path, "wb") as f:
            f.write(make_wav_bytes(fmt_extra=os.urandom(2), samples=struct.pack("<hhh", 1, -2, 3)))
        with open(invalid_path, "wb") as f:
            f.write(make_wav_bytes(fmt_extra=os.urandom(2), chunk_id=b"JUNK"))

        assert parser.parse_wav(valid_path) is True, "Parser rejected a valid 18-byte fmt chunk"
        with pytest.raises(Exception):
            parser.parse_wav(invalid_path)


def test_sanitizer_adversarial_corpus():
    sanitizer_script = os.path.join(PIPELINE_DIR, "sanitizer.py")
    assert os.path.isfile(sanitizer_script), f"Sanitizer script {sanitizer_script} does not exist."

    clean_corpus_dir = "/app/corpora/clean"
    evil_corpus_dir = "/app/corpora/evil"

    assert os.path.isdir(clean_corpus_dir), f"Clean corpus directory {clean_corpus_dir} does not exist."
    assert os.path.isdir(evil_corpus_dir), f"Evil corpus directory {evil_corpus_dir} does not exist."

    clean_files = [os.path.join(clean_corpus_dir, f) for f in os.listdir(clean_corpus_dir) if f.endswith('.wav')]
    evil_files = [os.path.join(evil_corpus_dir, f) for f in os.listdir(evil_corpus_dir) if f.endswith('.wav')]

    assert len(clean_files) > 0, "No clean files found in corpus."
    assert len(evil_files) > 0, "No evil files found in corpus."

    failed_clean = []
    for clean_file in clean_files:
        result = subprocess.run(["python3", sanitizer_script, clean_file], capture_output=True)
        if result.returncode != 0:
            failed_clean.append(os.path.basename(clean_file))

    failed_evil = []
    for evil_file in evil_files:
        result = subprocess.run(["python3", sanitizer_script, evil_file], capture_output=True)
        if result.returncode != 1:
            failed_evil.append(os.path.basename(evil_file))

    errors = []
    if failed_clean:
        errors.append(f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_clean)}")
    if failed_evil:
        errors.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed: {', '.join(failed_evil)}")

    assert not errors, "Sanitizer failed on corpus:\n" + "\n".join(errors)


def random_clean_samples(count):
    samples = [random.randint(-20000, 20000)]
    for _ in range(count - 1):
        low = max(-32768, samples[-1] - 20000)
        high = min(32767, samples[-1] + 20000)
        samples.append(random.randint(low, high))
    return samples


def test_sanitizer_content_based_randomized_inputs():
    sanitizer_script = os.path.join(PIPELINE_DIR, "sanitizer.py")
    assert os.path.isfile(sanitizer_script)

    cases = []
    with tempfile.TemporaryDirectory(prefix="audio_inputs_") as directory:
        for index in range(30):
            count = random.randint(40, 180)
            samples = random_clean_samples(count)
            should_be_evil = bool(random.getrandbits(1))

            if should_be_evil:
                position = random.randrange(count - 1)
                if random.getrandbits(1):
                    samples[position], samples[position + 1] = -32768, random.randint(-12767, 32767)
                else:
                    samples[position], samples[position + 1] = 32767, random.randint(-32768, 12766)
            elif index == 0:
                samples[0], samples[1] = -10000, 10000

            expected_evil = any(
                abs(right - left) > 20000
                for left, right in zip(samples, samples[1:])
            )
            assert expected_evil == should_be_evil

            path = os.path.join(directory, uuid.uuid4().hex)
            with wave.open(path, "wb") as wav_file:
                wav_file.setnchannels(1)
                wav_file.setsampwidth(2)
                wav_file.setframerate(random.choice([8000, 16000, 22050, 44100, 48000]))
                wav_file.writeframes(struct.pack("<" + "h" * len(samples), *samples))
            cases.append((path, 1 if expected_evil else 0))

        random.shuffle(cases)
        failures = []
        for path, expected_status in cases:
            result = subprocess.run(
                ["python3", sanitizer_script, path],
                capture_output=True,
                timeout=10
            )
            if result.returncode != expected_status:
                failures.append((os.path.basename(path), expected_status, result.returncode))

        assert not failures, f"Sanitizer misclassified generated WAV content: {failures}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
