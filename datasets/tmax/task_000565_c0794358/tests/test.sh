#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import random
import stat
import subprocess
import tempfile
import unicodedata
import uuid

SCRIPT_PATH = "/home/user/filter_translations.py"
VALIDATOR_PATH = "/app/legacy_validator"


def is_safe(text):
    try:
        text.encode('utf-8')
    except UnicodeEncodeError:
        return False

    for char in text:
        if unicodedata.category(char) == 'Cn':
            return False

    try:
        result = subprocess.run([VALIDATOR_PATH, text], capture_output=True, timeout=5)
        if result.returncode != 0:
            return False
    except Exception:
        return False

    return True


def run_student_script(input_path, output_path, direct=False):
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    command = [SCRIPT_PATH, input_path, output_path] if direct else ["python3", SCRIPT_PATH, input_path, output_path]
    result = subprocess.run(command, capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, (
        f"Script failed with return code {result.returncode}\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )


def load_output(path):
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    assert isinstance(data, list), "Output JSON must be a list"
    assert all(isinstance(entry, dict) for entry in data), "Every retained entry must remain an object"
    return data


def test_script_exists_and_is_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    mode = os.stat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode), "Submission must be a regular file"
    assert os.access(SCRIPT_PATH, os.X_OK), "filter_translations.py must be executable"


def test_clean_corpus():
    clean_dir = "/truth/clean_corpus"
    assert os.path.exists(clean_dir), f"Clean corpus dir missing: {clean_dir}"

    clean_files = [f for f in os.listdir(clean_dir) if f.endswith('.json')]
    assert clean_files, "No JSON files found in clean corpus"

    failed_files = []

    for filename in clean_files:
        input_path = os.path.join(clean_dir, filename)
        with open(input_path, 'r', encoding='utf-8') as f:
            input_data = json.load(f)

        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            output_path = tmp.name

        try:
            run_student_script(input_path, output_path)
            output_data = load_output(output_path)
            expected_data = [entry for entry in input_data if is_safe(entry.get('text', ''))]

            # Preserve the original length and ID assertions.
            if len(output_data) != len(expected_data):
                failed_files.append(filename)
                continue

            expected_ids = {entry['id'] for entry in expected_data}
            output_ids = {entry['id'] for entry in output_data}
            if expected_ids != output_ids:
                failed_files.append(filename)
                continue

            # Retained objects, including lang/text and ordering, must be unchanged.
            if output_data != expected_data:
                failed_files.append(filename)
        finally:
            if os.path.exists(output_path):
                os.remove(output_path)

    assert not failed_files, (
        f"{len(failed_files)} of {len(clean_files)} clean files modified incorrectly: "
        f"{', '.join(failed_files)}"
    )


def test_evil_corpus():
    evil_dir = "/truth/evil_corpus"
    assert os.path.exists(evil_dir), f"Evil corpus dir missing: {evil_dir}"

    evil_files = [f for f in os.listdir(evil_dir) if f.endswith('.json')]
    assert evil_files, "No JSON files found in evil corpus"

    failed_files = []

    for filename in evil_files:
        input_path = os.path.join(evil_dir, filename)
        with open(input_path, 'r', encoding='utf-8') as f:
            input_data = json.load(f)

        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            output_path = tmp.name

        try:
            run_student_script(input_path, output_path)
            output_data = load_output(output_path)
            expected_data = [entry for entry in input_data if is_safe(entry.get('text', ''))]

            # Preserve the original ID assertion.
            expected_ids = {entry['id'] for entry in expected_data}
            output_ids = {entry['id'] for entry in output_data}
            if expected_ids != output_ids:
                failed_files.append(filename)
                continue

            # Reject fabricated or altered retained objects and duplicate-ID tricks.
            if output_data != expected_data:
                failed_files.append(filename)
        finally:
            if os.path.exists(output_path):
                os.remove(output_path)

    assert not failed_files, (
        f"{len(failed_files)} of {len(evil_files)} evil files bypassed filtering: "
        f"{', '.join(failed_files)}"
    )


def find_unassigned_codepoint():
    for value in range(0x80, 0x110000):
        if 0xD800 <= value <= 0xDFFF:
            continue
        char = chr(value)
        if unicodedata.category(char) == 'Cn':
            return char
    raise AssertionError("No unassigned Unicode code point available")


def test_generated_mixed_corpus_preserves_complete_objects():
    token = uuid.uuid4().hex
    unassigned = find_unassigned_codepoint()
    duplicate_id = "duplicate-" + token
    input_data = [
        {"id": duplicate_id, "lang": "en-" + token[:6], "text": "safe alpha " + token},
        {"id": "surrogate-" + token, "lang": "xx", "text": "bad \ud800 " + token},
        {"id": duplicate_id, "lang": "fr-" + token[6:12], "text": "safe beta é " + token},
        {"id": "unassigned-" + token, "lang": "zz", "text": "bad " + unassigned + token},
        {"id": "ascii-limit-" + token, "lang": "en", "text": "A" * 500},
        {"id": "ascii-long-" + token, "lang": "en", "text": "B" * 501},
        {"id": "utf8-limit-" + token, "lang": "ja", "text": "é" * 250},
        {"id": "utf8-long-" + token, "lang": "ja", "text": "é" * 251},
        {"id": "empty-" + token, "lang": "und", "text": ""},
    ]
    random.SystemRandom().shuffle(input_data)
    expected_data = [entry for entry in input_data if is_safe(entry.get('text', ''))]

    input_fd, input_path = tempfile.mkstemp(suffix='.json')
    output_fd, output_path = tempfile.mkstemp(suffix='.json')
    os.close(input_fd)
    os.close(output_fd)
    try:
        with open(input_path, 'w', encoding='utf-8') as f:
            json.dump(input_data, f, ensure_ascii=True)
        run_student_script(input_path, output_path, direct=True)
        output_data = load_output(output_path)
        assert output_data == expected_data, "Generated corpus was not filtered while preserving complete objects and order"
    finally:
        for path in (input_path, output_path):
            if os.path.exists(path):
                os.remove(path)


def test_entries_are_processed_in_parallel():
    token = uuid.uuid4().hex
    input_data = [
        {
            "id": f"parallel-{token}-{i}",
            "lang": f"lang-{i}",
            "text": f"parallel probe {token} number {i}",
        }
        for i in range(16)
    ]

    input_fd, input_path = tempfile.mkstemp(suffix='.json')
    output_fd, output_path = tempfile.mkstemp(suffix='.json')
    log_fd, event_log = tempfile.mkstemp(suffix='.events')
    os.close(input_fd)
    os.close(output_fd)
    os.close(log_fd)
    backup_path = VALIDATOR_PATH + ".real_for_parallel_test"

    with open(input_path, 'w', encoding='utf-8') as f:
        json.dump(input_data, f, ensure_ascii=False)

    wrapper = f'''#!/usr/bin/env python3
import base64
import os
import subprocess
import sys
import time
pid = os.getpid()
text = sys.argv[1] if len(sys.argv) > 1 else ""
encoded = base64.b64encode(text.encode("utf-8")).decode("ascii")
with open({event_log!r}, "a", encoding="ascii") as log:
    log.write(f"S {{pid}} {{encoded}}\\n")
time.sleep(0.20)
result = subprocess.run([{backup_path!r}] + sys.argv[1:])
with open({event_log!r}, "a", encoding="ascii") as log:
    log.write(f"E {{pid}}\\n")
sys.exit(result.returncode)
'''

    assert os.path.isfile(VALIDATOR_PATH), "Legacy validator is missing"
    assert not os.path.exists(backup_path), "Unexpected validator backup already exists"
    try:
        os.replace(VALIDATOR_PATH, backup_path)
        with open(VALIDATOR_PATH, 'w', encoding='utf-8') as f:
            f.write(wrapper)
        os.chmod(VALIDATOR_PATH, 0o755)

        run_student_script(input_path, output_path, direct=True)
        output_data = load_output(output_path)
        assert output_data == input_data, "Parallel probe entries were not preserved"

        with open(event_log, 'r', encoding='ascii') as f:
            events = [line.strip().split() for line in f if line.strip()]

        active = set()
        max_active = 0
        observed_texts = []
        for event in events:
            if event[0] == 'S':
                assert len(event) == 3, "Malformed validator start event"
                active.add(event[1])
                observed_texts.append(base64.b64decode(event[2]).decode('utf-8'))
                max_active = max(max_active, len(active))
            elif event[0] == 'E':
                assert len(event) == 2, "Malformed validator end event"
                active.discard(event[1])

        expected_texts = [entry['text'] for entry in input_data]
        assert sorted(observed_texts) == sorted(expected_texts), "Every parallel probe text must be checked by the validator exactly once"
        assert max_active >= 2, "Legacy validator calls did not overlap; entries were not processed in parallel"
    finally:
        if os.path.exists(VALIDATOR_PATH) and os.path.exists(backup_path):
            os.remove(VALIDATOR_PATH)
        if os.path.exists(backup_path):
            os.replace(backup_path, VALIDATOR_PATH)
        for path in (input_path, output_path, event_log):
            if os.path.exists(path):
                os.remove(path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
