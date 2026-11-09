#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import secrets
import shlex
import shutil
import stat
import subprocess
import tempfile
import wave

import pytest

PIPELINE = "/home/user/pipeline"
VALIDATOR = f"{PIPELINE}/validator.py"
PROCESSOR = f"{PIPELINE}/process.py"
RUN_DAILY = f"{PIPELINE}/run_daily.sh"


def run_validator(path):
    return subprocess.run(
        ["python3", VALIDATOR, str(path)], capture_output=True, text=True, timeout=15
    )


def write_silent_wav(path, duration_centiseconds, rate=8000):
    frames = rate * duration_centiseconds // 100
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(rate)
        wav.writeframes(b"\x00\x00" * frames)
    return round(frames / rate, 2)


def test_required_directories_exist():
    for path in (PIPELINE, "/home/user/incoming", "/home/user/processed"):
        assert os.path.isdir(path), f"Required directory is missing: {path}"


def test_cron_job_scheduled():
    try:
        result = subprocess.run(
            ["crontab", "-l", "-u", "user"], capture_output=True, text=True
        )
        if result.returncode != 0:
            result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    except Exception as exc:
        pytest.fail(f"Failed to check crontab: {exc}")

    lines = result.stdout.strip().split("\n")

    # Preserve the original schedule/path assertion.
    cron_found = False
    for line in lines:
        if line.startswith("#"):
            continue
        if "15 3 * * *" in line and RUN_DAILY in line:
            cron_found = True
            break
    assert cron_found, "Cron job for run_daily.sh at 03:15 AM is missing or incorrectly configured."

    # Also require an active entry whose actual five schedule fields are exact and
    # whose command directly executes the requested script (optionally through sh).
    executable_entry = False
    for raw in lines:
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        parts = stripped.split(None, 5)
        if len(parts) != 6 or parts[:5] != ["15", "3", "*", "*", "*"]:
            continue
        try:
            tokens = shlex.split(parts[5])
        except ValueError:
            continue
        while tokens and "=" in tokens[0] and not tokens[0].startswith("/"):
            tokens.pop(0)
        if tokens and tokens[0] == RUN_DAILY:
            executable_entry = True
        elif len(tokens) >= 2 and os.path.basename(tokens[0]) in {"sh", "bash"} and tokens[1] == RUN_DAILY:
            executable_entry = True
        if executable_entry:
            break
    assert executable_entry, "Cron entry does not actually execute run_daily.sh at exactly 03:15."


def test_validator_clean_corpus():
    assert os.path.isfile(VALIDATOR), f"Missing validator script at {VALIDATOR}"
    clean_files = glob.glob("/app/corpus/clean/*")
    assert clean_files, "No clean corpus files found."

    failed_files = []
    for path in clean_files:
        result = run_validator(path)
        if result.returncode != 0 or "ACCEPTED" not in result.stdout.upper():
            failed_files.append(os.path.basename(path))
    assert not failed_files, (
        f"{len(failed_files)} of {len(clean_files)} clean modified/rejected: "
        + ", ".join(failed_files)
    )


def test_validator_evil_corpus():
    assert os.path.isfile(VALIDATOR), f"Missing validator script at {VALIDATOR}"
    evil_files = glob.glob("/app/corpus/evil/*")
    assert evil_files, "No evil corpus files found."

    failed_files = []
    for path in evil_files:
        result = run_validator(path)
        if result.returncode != 1 or "REJECTED" not in result.stdout.upper():
            failed_files.append(os.path.basename(path))
    assert not failed_files, (
        f"{len(failed_files)} of {len(evil_files)} evil bypassed: "
        + ", ".join(failed_files)
    )


def test_validator_on_independent_random_paths(tmp_path):
    valid_records = [
        {"user_id": 731, "transcript": "fresh unicode ✓", "duration_sec": 2.75},
        {"user_id": -4, "transcript": "second record", "duration_sec": None},
    ]
    valid_path = tmp_path / f"unseen-{secrets.token_hex(6)}.jsonl"
    valid_path.write_text("".join(json.dumps(x, ensure_ascii=False) + "\n" for x in valid_records), encoding="utf-8")
    result = run_validator(valid_path)
    assert result.returncode == 0 and "ACCEPTED" in result.stdout.upper(), (
        f"Validator rejected independently generated valid JSON-lines data: {result.stdout} {result.stderr}"
    )

    invalid_documents = [
        '{"user_id": 1, "transcript": "broken \\u002", "duration_sec": 1.5}\n',
        '{"user_id": 1, "transcript": "unterminated", "duration_sec": 1.5\n',
        '{"transcript": "missing id", "duration_sec": 1.5}\n',
        '{"user_id": 1, "duration_sec": 1.5}\n',
        '{"user_id": 1, "transcript": "missing duration"}\n',
        '{"user_id": true, "transcript": "bool is not an integer id", "duration_sec": 1.5}\n',
        '{"user_id": 1.25, "transcript": "float id", "duration_sec": 1.5}\n',
        '{"user_id": 1, "transcript": 99, "duration_sec": 1.5}\n',
        '{"user_id": 1, "transcript": "zero", "duration_sec": 0.0}\n',
        '{"user_id": 1, "transcript": "negative", "duration_sec": -0.01}\n',
        '{"user_id": 1, "transcript": "string duration", "duration_sec": "2.0"}\n',
        '{"user_id": 1, "transcript": "bool duration", "duration_sec": true}\n',
        '{"user_id": 1, "transcript": "nonstandard number", "duration_sec": NaN}\n',
        json.dumps(valid_records[0]) + '\nnot-json\n',
    ]
    for index, contents in enumerate(invalid_documents):
        path = tmp_path / f"unseen-bad-{index}-{secrets.token_hex(4)}.jsonl"
        path.write_text(contents, encoding="utf-8")
        result = run_validator(path)
        assert result.returncode == 1 and "REJECTED" in result.stdout.upper(), (
            f"Validator accepted independent invalid case {index}: stdout={result.stdout!r}, stderr={result.stderr!r}"
        )


def test_process_independently_gap_fills_generated_audio(tmp_path):
    assert os.path.isfile(PROCESSOR), f"Missing process.py at {PROCESSOR}"

    centiseconds = secrets.choice([73, 91, 127, 163, 218])
    audio = tmp_path / f"audio-{secrets.token_hex(5)}.wav"
    expected_duration = write_silent_wav(audio, centiseconds)
    source = tmp_path / f"metadata-{secrets.token_hex(5)}.jsonl"
    output = tmp_path / f"output-{secrets.token_hex(5)}.jsonl"
    records = [
        {"user_id": 4201, "transcript": "fill this one", "duration_sec": None, "tag": "keep-a"},
        {"user_id": 4202, "transcript": "already measured", "duration_sec": 8.25, "tag": "keep-b"},
        {"user_id": 4203, "transcript": "fill this too", "duration_sec": None},
    ]
    source.write_text("".join(json.dumps(x) + "\n" for x in records), encoding="utf-8")

    result = subprocess.run(
        ["python3", PROCESSOR, str(source), str(audio), str(output)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"process.py failed: {result.stdout}\n{result.stderr}"
    assert output.is_file(), "process.py did not create its requested output file"
    produced = [json.loads(line) for line in output.read_text(encoding="utf-8").splitlines()]
    assert len(produced) == len(records), "process.py did not output every input JSON-lines record"
    assert produced[0]["duration_sec"] == expected_duration
    assert produced[1]["duration_sec"] == 8.25
    assert produced[2]["duration_sec"] == expected_duration
    assert [(x["user_id"], x["transcript"]) for x in produced] == [
        (x["user_id"], x["transcript"]) for x in records
    ]
    assert produced[0]["tag"] == "keep-a" and produced[1]["tag"] == "keep-b"


def test_run_daily_and_process():
    assert os.path.isfile(RUN_DAILY), f"Missing run_daily.sh at {RUN_DAILY}"
    assert os.access(RUN_DAILY, os.X_OK), "run_daily.sh is not executable."
    incoming_data = "/home/user/incoming/data.jsonl"
    assert os.path.isfile(incoming_data), f"Missing incoming data at {incoming_data}"

    result = subprocess.run(["bash", RUN_DAILY], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, (
        f"run_daily.sh failed with exit code {result.returncode}\nStdout: {result.stdout}\nStderr: {result.stderr}"
    )
    processed_file = "/home/user/processed/cleaned.jsonl"
    assert os.path.isfile(processed_file), f"Processed file not found at {processed_file}"
    with open(processed_file, "r", encoding="utf-8") as handle:
        lines = handle.readlines()
    assert lines, "Processed file is empty."
    try:
        data = json.loads(lines[0].strip())
    except json.JSONDecodeError:
        pytest.fail("Processed file does not contain valid JSON.")
    assert "duration_sec" in data, "Missing 'duration_sec' in processed JSON."
    assert data["duration_sec"] == 3.45, f"Expected duration_sec to be 3.45, got {data['duration_sec']}"


def test_run_daily_invokes_both_scripts_and_handles_changed_inputs(tmp_path):
    incoming = "/home/user/incoming/data.jsonl"
    sample = "/app/sample.wav"
    processed = "/home/user/processed/cleaned.jsonl"
    validator_real = f"{PIPELINE}/validator.real_test.py"
    processor_real = f"{PIPELINE}/process.real_test.py"
    marker = tmp_path / "invocations.jsonl"

    backups = tmp_path / "backups"
    backups.mkdir()
    shutil.copy2(VALIDATOR, backups / "validator.py")
    shutil.copy2(PROCESSOR, backups / "process.py")
    shutil.copy2(incoming, backups / "data.jsonl")
    shutil.copy2(sample, backups / "sample.wav")
    processed_existed = os.path.exists(processed)
    if processed_existed:
        shutil.copy2(processed, backups / "cleaned.jsonl")

    shutil.copy2(VALIDATOR, validator_real)
    shutil.copy2(PROCESSOR, processor_real)
    wrapper_template = '''#!/usr/bin/env python3
import json, os, sys
with open({marker!r}, "a", encoding="utf-8") as f:
    f.write(json.dumps({{"kind": {kind!r}, "args": sys.argv[1:]}}) + "\\n")
os.execv(sys.executable, [sys.executable, {real!r}] + sys.argv[1:])
'''

    try:
        with open(VALIDATOR, "w", encoding="utf-8") as handle:
            handle.write(wrapper_template.format(marker=str(marker), kind="validator", real=validator_real))
        with open(PROCESSOR, "w", encoding="utf-8") as handle:
            handle.write(wrapper_template.format(marker=str(marker), kind="processor", real=processor_real))
        os.chmod(VALIDATOR, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR | stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)
        os.chmod(PROCESSOR, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR | stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)

        expected = write_silent_wav(sample, secrets.choice([84, 116, 157, 203]))
        dynamic_records = [
            {"user_id": 88001, "transcript": "dynamic daily null", "duration_sec": None},
            {"user_id": 88002, "transcript": "dynamic daily existing", "duration_sec": 6.75},
        ]
        with open(incoming, "w", encoding="utf-8") as handle:
            for record in dynamic_records:
                handle.write(json.dumps(record) + "\n")
        if os.path.exists(processed):
            os.unlink(processed)

        result = subprocess.run(["bash", RUN_DAILY], capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, f"run_daily.sh failed on changed fixtures: {result.stdout}\n{result.stderr}"
        assert os.path.isfile(processed), "run_daily.sh did not create the required output"
        with open(processed, encoding="utf-8") as handle:
            actual = [json.loads(line) for line in handle if line.strip()]
        assert len(actual) == 2
        assert actual[0]["user_id"] == 88001 and actual[0]["transcript"] == "dynamic daily null"
        assert actual[0]["duration_sec"] == expected
        assert actual[1] == dynamic_records[1]

        assert marker.is_file(), "run_daily.sh invoked neither required Python script"
        calls = [json.loads(line) for line in marker.read_text(encoding="utf-8").splitlines()]
        validator_calls = [x for x in calls if x["kind"] == "validator"]
        processor_calls = [x for x in calls if x["kind"] == "processor"]
        assert any(x["args"] == [incoming] for x in validator_calls), (
            "run_daily.sh did not invoke validator.py on the required incoming file"
        )
        assert any(x["args"] == [incoming, sample, processed] for x in processor_calls), (
            "run_daily.sh did not invoke process.py with the required input, audio, and output paths"
        )
    finally:
        shutil.copy2(backups / "validator.py", VALIDATOR)
        shutil.copy2(backups / "process.py", PROCESSOR)
        shutil.copy2(backups / "data.jsonl", incoming)
        shutil.copy2(backups / "sample.wav", sample)
        if processed_existed:
            shutil.copy2(backups / "cleaned.jsonl", processed)
        elif os.path.exists(processed):
            os.unlink(processed)
        for path in (validator_real, processor_real):
            if os.path.exists(path):
                os.unlink(path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
