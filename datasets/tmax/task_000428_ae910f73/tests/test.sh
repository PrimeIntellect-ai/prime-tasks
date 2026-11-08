#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess
import tempfile
import uuid
from pathlib import Path

import pytest

MIGRATOR_PATH = "/home/user/migrator.py"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"
VIDEO_PATH = "/app/build_dashboard_capture.mp4"
ALLOWED_LANGS = {"cpp", "python", "rust"}
SEMVER = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
EXPECTED_VIDEO_PAYLOADS = [
    {"version": "1.0.0", "build_steps": [{"lang": "python", "cmd": "pip install"}]},
    {"version": "1.0", "build_steps": [{"lang": "python", "cmd": "pip install"}]},
]


def run_migrator(input_dir, output_dir, reject_log):
    cmd = [
        "python3", MIGRATOR_PATH,
        "--input-dir", str(input_dir),
        "--output-dir", str(output_dir),
        "--reject-log", str(reject_log),
    ]
    return subprocess.run(cmd, capture_output=True, text=True, timeout=15)


def read_rejects(path):
    if not os.path.isfile(path):
        return []
    with open(path, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def expected_migration(data):
    if not isinstance(data, dict):
        raise ValueError("top-level value is not an object")
    version = data.get("version")
    if not isinstance(version, str) or SEMVER.fullmatch(version) is None:
        raise ValueError("invalid version")
    version_tuple = tuple(int(part) for part in version.split("."))

    if version_tuple < (2, 0, 0):
        steps = data.get("build_steps")
        if not isinstance(steps, list):
            raise ValueError("invalid build_steps")
        orchestration = {}
        for step in steps:
            if not isinstance(step, dict):
                raise ValueError("invalid step")
            lang = step.get("lang")
            cmd = step.get("cmd")
            if lang not in ALLOWED_LANGS or not isinstance(cmd, str):
                raise ValueError("invalid step fields")
            orchestration.setdefault(lang, {"commands": []})["commands"].append(cmd)
        return {"version": "2.0.0", "orchestration": orchestration}

    orchestration = data.get("orchestration")
    if not isinstance(orchestration, dict):
        raise ValueError("invalid orchestration")
    for lang, entry in orchestration.items():
        if lang not in ALLOWED_LANGS or not isinstance(entry, dict):
            raise ValueError("invalid orchestration language")
        commands = entry.get("commands")
        if not isinstance(commands, list) or any(not isinstance(cmd, str) for cmd in commands):
            raise ValueError("invalid commands")
    return data


def assert_run_matches(input_dir, expected_outputs, expected_rejects):
    with tempfile.TemporaryDirectory(prefix="migrator-check-") as tmp:
        out_dir = Path(tmp) / "out"
        reject_log = Path(tmp) / "rejects.log"
        out_dir.mkdir()
        result = run_migrator(input_dir, out_dir, reject_log)
        assert result.returncode == 0, f"Migrator failed: stdout={result.stdout!r}, stderr={result.stderr!r}"

        assert set(os.listdir(out_dir)) == set(expected_outputs), "Output filenames do not match accepted inputs"
        for filename, expected in expected_outputs.items():
            assert (out_dir / filename).is_file(), f"Missing output file {filename}"
            assert load_json(out_dir / filename) == expected, f"Incorrect migrated content for {filename}"

        rejects = read_rejects(reject_log)
        assert len(rejects) == len(expected_rejects), "Reject log contains missing or duplicate entries"
        assert set(rejects) == set(expected_rejects), "Reject log does not match rejected inputs"


def extract_video_payloads():
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", VIDEO_PATH, "-map", "0:s:0", "-f", "srt", "-"],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, f"Could not extract primary subtitle track: {result.stderr}"
    normalized = result.stdout.replace("\r\n", "\n").strip()
    blocks = re.split(r"\n\s*\n", normalized) if normalized else []
    payloads = []
    for block in blocks:
        lines = block.splitlines()
        assert len(lines) >= 3 and "-->" in lines[1], f"Malformed extracted subtitle cue: {block!r}"
        raw_payload = "\n".join(lines[2:]).strip()
        try:
            payloads.append(json.loads(raw_payload))
        except json.JSONDecodeError:
            pass
    return payloads


def test_migrator_exists():
    assert os.path.isfile(MIGRATOR_PATH), f"Migrator script not found at {MIGRATOR_PATH}"


def test_adversarial_corpus_clean():
    if not os.path.isfile(MIGRATOR_PATH):
        pytest.fail("Migrator script missing.")

    with tempfile.TemporaryDirectory() as tmp_out:
        reject_log = os.path.join(tmp_out, "rejects.log")
        out_dir = os.path.join(tmp_out, "out")
        os.makedirs(out_dir)
        result = run_migrator(CLEAN_CORPUS_DIR, out_dir, reject_log)
        assert result.returncode == 0, result.stderr

        clean_files = set(os.listdir(CLEAN_CORPUS_DIR))
        out_files = set(os.listdir(out_dir))
        rejected_files = set(read_rejects(reject_log))

        failed_clean = []
        for cf in clean_files:
            if cf not in out_files or cf in rejected_files:
                failed_clean.append(cf)
        if failed_clean:
            pytest.fail(f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected. Offending files: {', '.join(failed_clean)}")

        assert out_files == clean_files
        assert rejected_files == set()
        for filename in clean_files:
            source = load_json(os.path.join(CLEAN_CORPUS_DIR, filename))
            assert load_json(os.path.join(out_dir, filename)) == expected_migration(source)


def test_adversarial_corpus_evil():
    if not os.path.isfile(MIGRATOR_PATH):
        pytest.fail("Migrator script missing.")

    with tempfile.TemporaryDirectory() as tmp_out:
        reject_log = os.path.join(tmp_out, "rejects.log")
        out_dir = os.path.join(tmp_out, "out")
        os.makedirs(out_dir)
        result = run_migrator(EVIL_CORPUS_DIR, out_dir, reject_log)
        assert result.returncode == 0, result.stderr

        evil_files = set(os.listdir(EVIL_CORPUS_DIR))
        out_files = set(os.listdir(out_dir))
        rejected_files = set(read_rejects(reject_log))

        bypassed_evil = []
        for ef in evil_files:
            if ef in out_files or ef not in rejected_files:
                bypassed_evil.append(ef)
        if bypassed_evil:
            pytest.fail(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed. Offending files: {', '.join(bypassed_evil)}")

        assert out_files == set()
        assert rejected_files == evil_files


def test_generated_unseen_inputs_are_validated_and_migrated():
    token = uuid.uuid4().hex
    cases = [
        ({"version": "0.9.7", "build_steps": [
            {"lang": "rust", "cmd": "cargo build"},
            {"lang": "python", "cmd": "pytest -q"},
            {"lang": "rust", "cmd": "cargo test"},
        ]}, True),
        ({"version": "1.999.3", "build_steps": []}, True),
        ({"version": "2.0.0", "orchestration": {"cpp": {"commands": ["cmake .", "make"]}}}, True),
        ({"version": "12.4.9", "orchestration": {
            "python": {"commands": []}, "rust": {"commands": ["cargo check"]}
        }}, True),
        ({"version": "1.2", "build_steps": []}, False),
        ({"version": "v1.2.3", "build_steps": []}, False),
        ({"version": "01.2.3", "build_steps": []}, False),
        ({"version": "1.2.3-alpha", "build_steps": []}, False),
        ({"version": 1.2, "build_steps": []}, False),
        ({"build_steps": []}, False),
        ({"version": "1.5.0", "orchestration": {}}, False),
        ({"version": "1.5.0", "build_steps": {}}, False),
        ({"version": "1.5.0", "build_steps": ["not-an-object"]}, False),
        ({"version": "1.5.0", "build_steps": [{"lang": "go", "cmd": "go build"}]}, False),
        ({"version": "1.5.0", "build_steps": [{"lang": "cpp", "cmd": ["make"]}]}, False),
        ({"version": "1.5.0", "build_steps": [{"lang": "cpp"}]}, False),
        ({"version": "2.0.0", "build_steps": []}, False),
        ({"version": "2.3.0", "orchestration": []}, False),
        ({"version": "2.3.0", "orchestration": {"java": {"commands": ["mvn"]}}}, False),
        ({"version": "2.3.0", "orchestration": {"rust": ["cargo build"]}}, False),
        ({"version": "2.3.0", "orchestration": {"rust": {"commands": "cargo build"}}}, False),
        ({"version": "2.3.0", "orchestration": {"rust": {"commands": ["cargo build", 7]}}}, False),
    ]

    with tempfile.TemporaryDirectory(prefix=f"unseen-{token}-") as tmp:
        input_dir = Path(tmp) / f"inputs-{uuid.uuid4().hex}"
        input_dir.mkdir()
        expected_outputs = {}
        expected_rejects = set()

        for index, (payload, accepted) in enumerate(cases):
            filename = f"case_{uuid.uuid4().hex}_{index}.json"
            (input_dir / filename).write_text(json.dumps(payload), encoding="utf-8")
            if accepted:
                expected_outputs[filename] = expected_migration(payload)
            else:
                expected_rejects.add(filename)

        malformed_name = f"malformed_{uuid.uuid4().hex}.json"
        (input_dir / malformed_name).write_text('{"version": "1.0.0",', encoding="utf-8")
        expected_rejects.add(malformed_name)

        array_name = f"array_{uuid.uuid4().hex}.json"
        (input_dir / array_name).write_text("[]", encoding="utf-8")
        expected_rejects.add(array_name)

        assert_run_matches(input_dir, expected_outputs, expected_rejects)


def test_video_configs_extracted_and_migrated():
    extracted_dir = "/home/user/video_configs"
    migrated_dir = "/home/user/video_configs_migrated"
    reject_log = "/home/user/video_rejects.log"

    assert os.path.isdir(extracted_dir), f"Extracted directory missing at {extracted_dir}"
    assert os.path.isdir(migrated_dir), f"Migrated directory missing at {migrated_dir}"
    assert os.path.isfile(reject_log), f"Reject log missing at {reject_log}"

    migrated_files = os.listdir(migrated_dir)
    rejected_files = read_rejects(reject_log)
    assert len(migrated_files) > 0 or len(rejected_files) > 0, "No files were extracted or processed from the video."

    for mf in migrated_files:
        with open(os.path.join(migrated_dir, mf), "r", encoding="utf-8") as f:
            try:
                data = json.load(f)
                assert "orchestration" in data, f"Migrated file {mf} missing 'orchestration' key"
                assert data.get("version") == "2.0.0" or data.get("version", "").startswith("2."), f"Migrated file {mf} has invalid version"
            except json.JSONDecodeError:
                pytest.fail(f"Migrated file {mf} is not valid JSON")

    video_payloads = extract_video_payloads()
    assert video_payloads == EXPECTED_VIDEO_PAYLOADS, "The recording or its primary subtitle payloads were altered"

    expected_extracted_names = [f"config_{i}.json" for i in range(1, len(video_payloads) + 1)]
    assert set(os.listdir(extracted_dir)) == set(expected_extracted_names)
    for filename, payload in zip(expected_extracted_names, video_payloads):
        assert load_json(os.path.join(extracted_dir, filename)) == payload, f"Incorrect extracted payload in {filename}"

    expected_outputs = {}
    expected_rejects = set()
    for filename, payload in zip(expected_extracted_names, video_payloads):
        try:
            expected_outputs[filename] = expected_migration(payload)
        except ValueError:
            expected_rejects.add(filename)

    assert set(migrated_files) == set(expected_outputs)
    assert len(rejected_files) == len(expected_rejects)
    assert set(rejected_files) == expected_rejects
    for filename, expected in expected_outputs.items():
        assert load_json(os.path.join(migrated_dir, filename)) == expected

    # Execute the submitted migrator again on the actual extracted artifacts.
    assert_run_matches(extracted_dir, expected_outputs, expected_rejects)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
