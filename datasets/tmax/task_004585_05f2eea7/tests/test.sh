#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import subprocess
import unicodedata
import uuid

import pytest

SCRIPT_PATH = "/home/user/clean_pipeline.py"
RAW_DIR = "/home/user/raw_data"
OUTPUT_PATH = "/home/user/clean_data/deduped_output.jsonl"


def run_pipeline(env=None):
    result = subprocess.run(
        ["/usr/bin/python3", SCRIPT_PATH],
        capture_output=True,
        text=True,
        timeout=30,
        env=env,
    )
    assert result.returncode == 0, (
        f"Pipeline failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_and_validate_output(expected_texts):
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."

    actual_texts = set()
    records = []
    with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                pytest.fail(f"Line {line_num} in {OUTPUT_PATH} is not valid JSON.")

            assert isinstance(record, dict), f"Record on line {line_num} is not a JSON object."
            assert "hash" in record, f"Record on line {line_num} missing 'hash' key."
            assert "text" in record, f"Record on line {line_num} missing 'text' key."
            assert len(record) == 2, f"Record on line {line_num} has extra keys."

            text = record["text"]
            text_hash = record["hash"]
            assert isinstance(text, str), f"Text on line {line_num} is not a string."
            assert unicodedata.is_normalized("NFC", text), f"Text {text!r} is not NFC-normalized."

            expected_hash = hashlib.sha256(text.encode("utf-8")).hexdigest()
            assert text_hash == expected_hash, (
                f"Hash for text '{text}' is incorrect. "
                f"Expected {expected_hash}, got {text_hash}."
            )

            actual_texts.add(text)
            records.append(record)

    assert len(records) == len(expected_texts), (
        f"Expected exactly {len(expected_texts)} records, but found {len(records)}."
    )
    assert actual_texts == expected_texts, (
        "The deduplicated texts do not match the expected set. "
        f"Missing: {expected_texts - actual_texts}. "
        f"Unexpected: {actual_texts - expected_texts}."
    )


def test_pipeline_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."


def test_cron_job_configured():
    try:
        result = subprocess.run(
            ["crontab", "-l"], capture_output=True, text=True, check=True
        )
        crontab_output = result.stdout
    except subprocess.CalledProcessError:
        pytest.fail("Failed to read crontab. Is it configured for the user?")

    expected_cron = "0 2 * * * /usr/bin/python3 /home/user/clean_pipeline.py"
    cron_lines = [line.strip() for line in crontab_output.strip().split("\n")]
    assert any(expected_cron in line for line in cron_lines), (
        "The expected cron job is not configured correctly."
    )


def test_pipeline_executes_on_original_data_and_output_is_correct():
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    run_pipeline()

    expected_texts = {
        "Hello World",
        "Data Science",
        "Café",
        "Hola",
        "Python",
        "おはよう",
    }
    read_and_validate_output(expected_texts)


def test_pipeline_handles_new_inputs_and_uses_parallel_processing(tmp_path):
    token = uuid.uuid4().hex

    for entry in os.scandir(RAW_DIR):
        if entry.is_file() or entry.is_symlink():
            os.remove(entry.path)

    alpha = f"Alpha-{token}"
    cafe = f"Café-{token}"
    espanol = f"Español-{token}"
    tokyo = f"東京-{token}"

    with open(os.path.join(RAW_DIR, "dynamic_utf8.txt"), "w", encoding="utf-8") as f:
        f.write(f"   {alpha}   \n")
        f.write(f"Cafe\u0301-{token}\n")
        f.write(f"{alpha}\n")

    with open(os.path.join(RAW_DIR, "dynamic_latin1.txt"), "w", encoding="iso-8859-1") as f:
        f.write(f"  {espanol}  \n")
        f.write(f"{cafe}\n")

    with open(os.path.join(RAW_DIR, "dynamic_utf16.txt"), "w", encoding="utf-16le") as f:
        f.write(f"  {tokyo}  \n")
        f.write(f"Cafe\u0301-{token}\n")

    with open(os.path.join(RAW_DIR, "ignored.bin"), "w", encoding="utf-8") as f:
        f.write(f"SHOULD-NOT-APPEAR-{token}\n")

    probe_dir = tmp_path / "probe"
    probe_dir.mkdir()
    marker = tmp_path / "parallel-used"
    sitecustomize = probe_dir / "sitecustomize.py"
    sitecustomize.write_text(
        '''
import concurrent.futures as _cf
import multiprocessing as _mp
import multiprocessing.pool as _mppool
import os as _os

_MARKER = _os.environ.get("PIPELINE_PARALLEL_MARKER")
def _mark():
    if _MARKER:
        with open(_MARKER, "a", encoding="utf-8") as _f:
            _f.write("used\\n")

_ThreadPoolExecutor = _cf.ThreadPoolExecutor
class ThreadPoolExecutor(_ThreadPoolExecutor):
    def __init__(self, *args, **kwargs):
        _mark()
        super().__init__(*args, **kwargs)
_cf.ThreadPoolExecutor = ThreadPoolExecutor

_ProcessPoolExecutor = _cf.ProcessPoolExecutor
class ProcessPoolExecutor(_ProcessPoolExecutor):
    def __init__(self, *args, **kwargs):
        _mark()
        super().__init__(*args, **kwargs)
_cf.ProcessPoolExecutor = ProcessPoolExecutor

_Pool = _mp.Pool
def Pool(*args, **kwargs):
    _mark()
    return _Pool(*args, **kwargs)
_mp.Pool = Pool

_PoolClass = _mppool.Pool
class PoolClass(_PoolClass):
    def __init__(self, *args, **kwargs):
        _mark()
        super().__init__(*args, **kwargs)
_mppool.Pool = PoolClass

_Process = _mp.Process
class Process(_Process):
    def __init__(self, *args, **kwargs):
        _mark()
        super().__init__(*args, **kwargs)
_mp.Process = Process
''',
        encoding="utf-8",
    )

    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    env = os.environ.copy()
    env["PIPELINE_PARALLEL_MARKER"] = str(marker)
    old_pythonpath = env.get("PYTHONPATH")
    env["PYTHONPATH"] = str(probe_dir) + (os.pathsep + old_pythonpath if old_pythonpath else "")
    run_pipeline(env=env)

    assert marker.is_file() and marker.read_text(encoding="utf-8").strip(), (
        "The pipeline did not use concurrent.futures or multiprocessing while running."
    )
    read_and_validate_output({alpha, cafe, espanol, tokyo})
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
