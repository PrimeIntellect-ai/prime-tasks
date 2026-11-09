#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import subprocess
from pathlib import Path
from collections import defaultdict
import pytest

OUTPUT_PATH = "/home/user/output/final_translations.csv"
INPUT_FILES = [
    "/home/user/inputs/batch1.csv",
    "/home/user/inputs/batch2.csv"
]


def normalize_lang(lang):
    """Normalize language string to ll-CC format."""
    parts = lang.replace('_', '-').split('-')
    if len(parts) == 2:
        return f"{parts[0].lower()}-{parts[1].upper()}"
    return lang


def compute_expected_data():
    """Derive the expected output data from the input files."""
    records = []
    for inp in INPUT_FILES:
        if not os.path.exists(inp):
            continue
        with open(inp, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                records.append(row)

    # Deduplicate: keep highest timestamp per (msg_id, normalized_lang)
    dedup = {}
    for r in records:
        msg_id = r['msg_id']
        lang = normalize_lang(r['lang'])
        key = (msg_id, lang)
        ts = int(r['timestamp'])
        score = int(r['score'])

        if key not in dedup or ts > dedup[key]['timestamp']:
            dedup[key] = {
                'msg_id': msg_id,
                'lang': lang,
                'timestamp': ts,
                'score': score
            }

    # Group by normalized lang
    by_lang = defaultdict(list)
    for key, val in dedup.items():
        by_lang[val['lang']].append(val)

    # Sort and compute rolling average
    expected_rows = []
    for lang in sorted(by_lang.keys()):
        lang_records = sorted(by_lang[lang], key=lambda x: x['timestamp'])
        scores = []
        for r in lang_records:
            scores.append(r['score'])
            window = scores[-3:]
            avg = sum(window) / len(window)
            expected_rows.append({
                'msg_id': r['msg_id'],
                'lang': r['lang'],
                'timestamp': str(r['timestamp']),
                'score': str(r['score']),
                'rolling_avg_score': f"{avg:.2f}"
            })

    return expected_rows


def assert_output_matches(expected_data):
    assert os.path.isfile(OUTPUT_PATH), f"Expected output file {OUTPUT_PATH} does not exist."

    with open(OUTPUT_PATH, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail("Output CSV is empty, expected a header and data rows.")

        expected_header = ['msg_id', 'lang', 'timestamp', 'score', 'rolling_avg_score']
        assert header == expected_header, f"CSV header mismatch. Expected {expected_header}, got {header}."

        actual_data = []
        for row in reader:
            if not row or not any(row):
                continue
            assert len(row) == 5, f"Row {row} does not have exactly 5 columns."
            actual_data.append({
                'msg_id': row[0],
                'lang': row[1],
                'timestamp': row[2],
                'score': row[3],
                'rolling_avg_score': row[4]
            })

    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} rows, but got {len(actual_data)}."
    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, got {actual}."


def test_output_file_exists():
    output_path = "/home/user/output/final_translations.csv"
    assert os.path.isfile(output_path), f"Expected output file {output_path} does not exist."


def test_output_file_contents():
    output_path = "/home/user/output/final_translations.csv"
    assert os.path.isfile(output_path), "Cannot check contents, output file is missing."

    expected_data = compute_expected_data()

    with open(output_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail("Output CSV is empty, expected a header and data rows.")

        expected_header = ['msg_id', 'lang', 'timestamp', 'score', 'rolling_avg_score']
        assert header == expected_header, f"CSV header mismatch. Expected {expected_header}, got {header}."

        actual_data = []
        for row in reader:
            if not row or not any(row):
                continue
            assert len(row) == 5, f"Row {row} does not have exactly 5 columns."
            actual_data.append({
                'msg_id': row[0],
                'lang': row[1],
                'timestamp': row[2],
                'score': row[3],
                'rolling_avg_score': row[4]
            })

    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} rows, but got {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, got {actual}."


def write_probe_inputs():
    Path(INPUT_FILES[0]).write_text(
        "msg_id,lang,translation,timestamp,score\n"
        "10,ZH_cn,A,100,10\n"
        "11,en_us,B,200,20\n"
        "10,zh_CN,C,300,30\n"
        "12,en_US,D,150,40\n"
        "13,en_us,E,250,60\n",
        encoding="utf-8"
    )
    Path(INPUT_FILES[1]).write_text(
        "msg_id,lang,translation,timestamp,score\n"
        "14,zh_cn,F,50,50\n"
        "11,en_US,G,220,80\n"
        "15,en_US,H,350,100\n"
        "16,fr_fr,I,175,70\n"
        "17,fr_FR,J,275,90\n"
        "18,fr_fr,K,375,110\n"
        "19,fr_FR,L,475,130\n",
        encoding="utf-8"
    )


def test_cpp_program_compiles_and_generates_output():
    sources = sorted(
        p for p in Path('/home/user').rglob('*')
        if p.is_file() and p.suffix.lower() in {'.cpp', '.cc', '.cxx'}
    )
    assert sources, "No C++ source program was found under /home/user."

    original_inputs = {path: Path(path).read_bytes() for path in INPUT_FILES}
    original_output = Path(OUTPUT_PATH).read_bytes() if os.path.isfile(OUTPUT_PATH) else None

    build_sets = [[source] for source in sources]
    if len(sources) > 1:
        build_sets.append(sources)

    successful_binary = None
    successful_cwd = None
    errors = []

    try:
        for index, build_sources in enumerate(build_sets):
            binary = f"/tmp/submission_program_{index}"
            compile_cmd = ['g++', '-std=c++17'] + [str(p) for p in build_sources] + ['-o', binary]
            compiled = subprocess.run(compile_cmd, capture_output=True, text=True, timeout=30)
            if compiled.returncode != 0:
                errors.append(f"Compilation failed for {[str(p) for p in build_sources]}: {compiled.stderr[-1000:]}")
                continue

            write_probe_inputs()
            probe_expected = compute_expected_data()
            if os.path.exists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)

            cwd = str(build_sources[0].parent)
            try:
                executed = subprocess.run([binary], cwd=cwd, capture_output=True, text=True, timeout=15)
                if executed.returncode != 0:
                    errors.append(f"Program {binary} exited with {executed.returncode}: {executed.stderr[-1000:]}")
                    continue
                assert_output_matches(probe_expected)
            except (AssertionError, subprocess.TimeoutExpired) as exc:
                errors.append(f"Program built from {[str(p) for p in build_sources]} failed the probe: {exc}")
                continue

            successful_binary = binary
            successful_cwd = cwd
            break
    finally:
        for path, contents in original_inputs.items():
            Path(path).write_bytes(contents)
        if original_output is None:
            if os.path.exists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)
        else:
            Path(OUTPUT_PATH).write_bytes(original_output)

    assert successful_binary is not None, "No submitted C++ program compiled and correctly processed the probe inputs. " + " | ".join(errors)

    original_expected = compute_expected_data()
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    executed = subprocess.run([successful_binary], cwd=successful_cwd, capture_output=True, text=True, timeout=15)
    assert executed.returncode == 0, f"Compiled program failed on the provided inputs: {executed.stderr}"
    assert_output_matches(original_expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
