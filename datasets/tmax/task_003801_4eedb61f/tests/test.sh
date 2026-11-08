#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import uuid
from pathlib import Path

import pytest

CLEAN_CORPUS = "/app/corpus/clean"
EVIL_CORPUS = "/app/corpus/evil"
PIPELINE_SCRIPT = "/home/user/pipeline.sh"
SANITIZER_EXEC = "/home/user/sanitizer"
SANITIZER_SOURCE = "/home/user/sanitizer.c"
VENDORED_DIR = "/app/vendored/cJSON-1.7.15"
DELIMITER = "---END_RECORD---\n"


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def test_pipeline_script_exists():
    assert os.path.isfile(PIPELINE_SCRIPT), f"Pipeline script not found at {PIPELINE_SCRIPT}"
    assert os.access(PIPELINE_SCRIPT, os.X_OK) or os.path.exists(PIPELINE_SCRIPT), "Pipeline script should exist"


def test_sanitizer_executable_exists():
    assert os.path.isfile(SANITIZER_EXEC), f"Sanitizer executable not found at {SANITIZER_EXEC}"
    assert os.access(SANITIZER_EXEC, os.X_OK), f"Sanitizer at {SANITIZER_EXEC} is not executable"


def test_clean_corpus_preserved(tmp_path):
    output_dir = str(tmp_path / "clean_out")
    os.makedirs(output_dir, exist_ok=True)

    result = subprocess.run(["/bin/bash", PIPELINE_SCRIPT, CLEAN_CORPUS, output_dir], capture_output=True, text=True)
    assert result.returncode == 0, f"Pipeline script failed on clean corpus:\n{result.stderr}"

    clean_files = []
    for root, _, files in os.walk(CLEAN_CORPUS):
        for f in files:
            if f.endswith(".log"):
                clean_files.append(os.path.relpath(os.path.join(root, f), CLEAN_CORPUS))

    assert len(clean_files) > 0, "No clean log files found to test."

    modified_clean = []
    missing_clean = []
    for rel_file in clean_files:
        in_path = os.path.join(CLEAN_CORPUS, rel_file)
        out_path = os.path.join(output_dir, rel_file)
        if not os.path.exists(out_path):
            missing_clean.append(rel_file)
            continue
        with open(in_path, "r") as f:
            in_content = f.read()
        with open(out_path, "r") as f:
            out_content = f.read()
        if in_content != out_content:
            modified_clean.append(rel_file)

    error_msgs = []
    if missing_clean:
        error_msgs.append(f"{len(missing_clean)} clean files missing in output: {missing_clean[:5]}")
    if modified_clean:
        error_msgs.append(f"{len(modified_clean)} clean files modified (not perfectly preserved): {modified_clean[:5]}")
    assert not error_msgs, " | ".join(error_msgs)


def test_evil_corpus_rejected(tmp_path):
    output_dir = str(tmp_path / "evil_out")
    os.makedirs(output_dir, exist_ok=True)

    result = subprocess.run(["/bin/bash", PIPELINE_SCRIPT, EVIL_CORPUS, output_dir], capture_output=True, text=True)
    assert result.returncode == 0, f"Pipeline script failed on evil corpus:\n{result.stderr}"

    evil_files = []
    for root, _, files in os.walk(EVIL_CORPUS):
        for f in files:
            if f.endswith(".log"):
                evil_files.append(os.path.relpath(os.path.join(root, f), EVIL_CORPUS))

    assert len(evil_files) > 0, "No evil log files found to test."

    bypassed_evil = []
    for rel_file in evil_files:
        out_path = os.path.join(output_dir, rel_file)
        if os.path.exists(out_path):
            with open(out_path, "r") as f:
                content = f.read().strip()
            if content:
                bypassed_evil.append(rel_file)

    assert not bypassed_evil, f"{len(bypassed_evil)} of {len(evil_files)} evil files bypassed sanitization (output not empty): {bypassed_evil[:5]}"


def test_repaired_static_cjson_build_and_c_sanitizer():
    assert os.path.isfile(SANITIZER_SOURCE), "sanitizer.c was not created"
    source = Path(SANITIZER_SOURCE).read_text(errors="replace")
    assert re.search(r"cJSON_Parse", source), "sanitizer.c does not call the cJSON parser"
    assert "cJSON" in source, "sanitizer.c does not use the vendored cJSON API"

    with open(SANITIZER_EXEC, "rb") as f:
        assert f.read(4) == b"\x7fELF", "sanitizer must be a compiled native executable"

    makefiles = list(Path(VENDORED_DIR).glob("Makefile*"))
    assert makefiles, "Vendored cJSON Makefile is missing"
    for makefile in makefiles:
        assert "gcc_broken_typo_compiler" not in makefile.read_text(errors="replace"), \
            f"Broken compiler perturbation remains in {makefile}"

    archives = list(Path(VENDORED_DIR).rglob("*.a"))
    valid_archives = []
    for archive in archives:
        listing = run(["ar", "t", str(archive)])
        symbols = run(["nm", "-g", "--defined-only", str(archive)])
        if listing.returncode == 0 and listing.stdout.strip() and symbols.returncode == 0 and "cJSON_Parse" in symbols.stdout:
            valid_archives.append(archive)
    assert valid_archives, "No built static cJSON archive containing the parser was found"

    linked_symbols = run(["nm", "-g", SANITIZER_EXEC])
    assert linked_symbols.returncode == 0, "Could not inspect sanitizer linkage"
    assert re.search(r"\b[Tt]\s+cJSON_Parse(?:WithOpts|WithLengthOpts|WithLength)?\b", linked_symbols.stdout), \
        "sanitizer does not contain the statically linked cJSON parser"

    dynamic = run(["ldd", SANITIZER_EXEC])
    assert dynamic.returncode == 0, f"Could not inspect sanitizer dynamic dependencies: {dynamic.stderr}"
    assert not re.search(r"(?:lib)?cjson", dynamic.stdout, re.IGNORECASE), \
        "sanitizer dynamically links cJSON instead of the built static archive"


def record(block):
    return block + DELIMITER


def test_sanitizer_on_novel_mixed_records(tmp_path):
    token = uuid.uuid4().hex
    clean_missing = '{\n  "id": "' + token + '",\n  "type": "sensor_reading",\n  "payload": [1, {"note": "---END_RECORD--- is data"}]\n}\n'
    clean_boundary = '{"id":"boundary-' + token + '","type":"sensor_reading","calibration_error":5e0}\n'
    clean_negative = '{\n\t"type" : "sensor_reading",\n\t"calibration_error" : -12.75,\n\t"text" : "unicode \\u03bb"\n}\n'
    evil_high = '{"id":"high-' + token + '","type":"sensor_reading","calibration_error":5.0001}\n'
    evil_type = '{"id":"wrong-' + token + '","type":"Sensor_Reading","calibration_error":0}\n'
    evil_nonstring_type = '{"id":"nonstr-' + token + '","type":17}\n'
    evil_invalid = '{"id":"bad-' + token + '","type":"sensor_reading",}\n'
    evil_trailing = '{"id":"trail-' + token + '","type":"sensor_reading"} garbage\n'

    content = "".join(record(x) for x in [
        clean_missing, evil_high, clean_boundary, evil_type,
        evil_invalid, clean_negative, evil_nonstring_type, evil_trailing,
    ])
    expected = record(clean_missing) + record(clean_boundary) + record(clean_negative)

    input_file = tmp_path / ("novel-" + token + ".log")
    output_file = tmp_path / "direct-output.log"
    input_file.write_text(content)

    result = run([SANITIZER_EXEC, str(input_file), str(output_file)])
    assert result.returncode == 0, f"Sanitizer failed on mixed records:\n{result.stderr}"
    assert output_file.is_file(), "Sanitizer did not create its output file"
    assert output_file.read_text() == expected, "Sanitizer did not preserve exactly the clean records from a novel mixed input"


def test_pipeline_on_novel_recursive_mixed_corpus(tmp_path):
    token = uuid.uuid4().hex
    input_dir = tmp_path / ("input-" + token)
    output_dir = tmp_path / ("output-" + token)
    nested = input_dir / "level one" / "deeper"
    other = input_dir / "second"
    nested.mkdir(parents=True)
    other.mkdir(parents=True)

    good_a = '{\n  "type": "sensor_reading",\n  "id": "A-' + token + '",\n  "calibration_error": 4.999\n}\n'
    good_b = '{"type":"sensor_reading","id":"B-' + token + '"}\n'
    bad_a = '{"type":"other","id":"C-' + token + '"}\n'
    bad_b = '{"type":"sensor_reading","id":"D-' + token + '","calibration_error":99}\n'
    malformed = '{ definitely not json ' + token + '\n'

    first_input = record(good_a) + record(bad_a) + record(good_b)
    second_input = record(bad_b) + record(good_b) + record(malformed)
    (nested / "mixed sample.log").write_text(first_input)
    (other / "another.log").write_text(second_input)
    (input_dir / "ignored.txt").write_text(record(good_a))

    result = run(["/bin/bash", PIPELINE_SCRIPT, str(input_dir), str(output_dir)])
    assert result.returncode == 0, f"Pipeline failed on novel recursive corpus:\n{result.stderr}"

    first_output = output_dir / "level one" / "deeper" / "mixed sample.log"
    second_output = output_dir / "second" / "another.log"
    assert first_output.is_file(), "Pipeline did not preserve the first relative log path"
    assert second_output.is_file(), "Pipeline did not preserve the second relative log path"
    assert first_output.read_text() == record(good_a) + record(good_b)
    assert second_output.read_text() == record(good_b)
    assert not (output_dir / "ignored.txt").exists(), "Pipeline processed a file that does not end in .log"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
