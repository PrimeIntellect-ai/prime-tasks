#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import math
import os
import random
import re
import shutil
import stat
import subprocess
import tempfile
from datetime import datetime

CSV_FILE = '/home/user/translation_telemetry.csv'
SCRIPT_FILE = '/home/user/analyze_telemetry.py'
INVALID_COUNT_FILE = '/home/user/invalid_count.txt'
DISTANCES_FILE = '/home/user/distances.json'


def compute_expected(csv_file):
    lang_regex = re.compile(r'^[a-z]{2}-[A-Z]{2}$')
    expected_invalid_count = 0
    lang_hour_latencies = {}

    with open(csv_file, 'r', newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                latency = float(row['latency_ms'])
                words = int(row['words_translated'])
            except ValueError:
                expected_invalid_count += 1
                continue

            lang = row['language_code']
            is_valid = True
            if latency <= 0:
                is_valid = False
            if words <= 0:
                is_valid = False
            if not lang_regex.match(lang):
                is_valid = False

            if not is_valid:
                expected_invalid_count += 1
            else:
                try:
                    dt = datetime.strptime(row['timestamp'], '%Y-%m-%dT%H:%M:%SZ')
                    hour = dt.hour
                except ValueError:
                    continue

                if lang not in lang_hour_latencies:
                    lang_hour_latencies[lang] = {h: [] for h in range(24)}
                lang_hour_latencies[lang][hour].append(latency)

    lang_vectors = {}
    for lang, hours_data in lang_hour_latencies.items():
        vector = []
        for h in range(24):
            lats = hours_data[h]
            vector.append(sum(lats) / len(lats) if lats else 0.0)
        lang_vectors[lang] = vector

    expected_distances = {}
    if 'es-ES' in lang_vectors:
        base_vector = lang_vectors['es-ES']
        for lang, vector in lang_vectors.items():
            if lang == 'es-ES':
                continue
            dist = math.sqrt(sum((a - b) ** 2 for a, b in zip(base_vector, vector)))
            expected_distances[lang] = round(dist, 4)

    return expected_invalid_count, expected_distances


def verify_outputs(csv_file):
    assert os.path.exists(INVALID_COUNT_FILE), f'File {INVALID_COUNT_FILE} does not exist.'
    assert os.path.exists(DISTANCES_FILE), f'File {DISTANCES_FILE} does not exist.'

    expected_invalid_count, expected_distances = compute_expected(csv_file)

    with open(INVALID_COUNT_FILE, 'r', encoding='utf-8') as f:
        actual_invalid_count_str = f.read().strip()
    assert actual_invalid_count_str.isdigit(), f'{INVALID_COUNT_FILE} does not contain a valid integer.'
    assert int(actual_invalid_count_str) == expected_invalid_count, \
        f'Expected invalid count {expected_invalid_count}, got {actual_invalid_count_str}'

    with open(DISTANCES_FILE, 'r', encoding='utf-8') as f:
        try:
            actual_distances = json.load(f)
        except json.JSONDecodeError:
            assert False, f'{DISTANCES_FILE} is not a valid JSON file.'

    assert 'es-ES' not in actual_distances, "'es-ES' should not be in the output JSON."

    for lang, expected_dist in expected_distances.items():
        assert lang in actual_distances, f'Language {lang} is missing from distances.json.'
        actual_dist = actual_distances[lang]
        assert isinstance(actual_dist, (int, float)), f'Distance for {lang} should be a number.'
        assert math.isclose(actual_dist, expected_dist, rel_tol=1e-4, abs_tol=1e-4), \
            f'Expected distance for {lang} to be {expected_dist}, got {actual_dist}.'

    for lang in actual_distances:
        assert lang in expected_distances, f'Unexpected language {lang} found in distances.json.'


def remove_outputs():
    for path in (INVALID_COUNT_FILE, DISTANCES_FILE):
        if os.path.exists(path):
            os.remove(path)


def run_submission():
    remove_outputs()
    result = subprocess.run(
        ['python3', SCRIPT_FILE],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=90,
    )
    assert result.returncode == 0, \
        f'{SCRIPT_FILE} failed with exit code {result.returncode}:\n{result.stdout}\n{result.stderr}'


def check_script_and_multiprocessing():
    assert os.path.exists(SCRIPT_FILE), f'File {SCRIPT_FILE} does not exist.'
    assert stat.S_ISREG(os.stat(SCRIPT_FILE).st_mode), f'{SCRIPT_FILE} is not a regular file.'

    with open(SCRIPT_FILE, 'r', encoding='utf-8') as f:
        source = f.read()
    assert source.strip(), f'{SCRIPT_FILE} is empty.'

    try:
        tree = ast.parse(source, filename=SCRIPT_FILE)
        compile(tree, SCRIPT_FILE, 'exec')
    except (SyntaxError, ValueError) as exc:
        assert False, f'{SCRIPT_FILE} is not valid Python: {exc}'

    imports_multiprocessing = False
    imported_parallel_names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            if any(alias.name == 'multiprocessing' or alias.name.startswith('multiprocessing.') for alias in node.names):
                imports_multiprocessing = True
        elif isinstance(node, ast.ImportFrom) and node.module and \
                (node.module == 'multiprocessing' or node.module.startswith('multiprocessing.')):
            imports_multiprocessing = True
            for alias in node.names:
                if alias.name in {'Pool', 'Process'}:
                    imported_parallel_names.add(alias.asname or alias.name)

    uses_parallel_worker = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in imported_parallel_names:
            uses_parallel_worker = True
        elif isinstance(node.func, ast.Attribute) and node.func.attr in {'Pool', 'Process'}:
            uses_parallel_worker = True

    assert imports_multiprocessing, 'The script must import the multiprocessing module.'
    assert uses_parallel_worker, 'The script must use multiprocessing Pool or Process workers.'


def test_final_state():
    check_script_and_multiprocessing()

    backup_dir = tempfile.mkdtemp(prefix='telemetry-verifier-')
    backup_csv = os.path.join(backup_dir, 'translation_telemetry.csv')
    shutil.copy2(CSV_FILE, backup_csv)

    rng = random.SystemRandom()
    a = rng.randint(61, 180)
    b = rng.randint(181, 320)
    c = rng.randint(321, 470)

    try:
        with open(CSV_FILE, 'w', newline='', encoding='utf-8') as f:
            writer = csv.writer(f)
            writer.writerow(['timestamp', 'language_code', 'latency_ms', 'words_translated'])
            writer.writerow(['2023-10-01T00:00:00Z', 'es-ES', a, 10])
            writer.writerow(['2023-10-01T00:20:00Z', 'es-ES', a + 20, 5])
            writer.writerow(['2023-10-01T07:00:00Z', 'es-ES', b, 12])
            writer.writerow(['2023-10-01T00:10:00Z', 'fr-FR', c, 8])
            writer.writerow(['2023-10-01T12:00:00Z', 'de-DE', b + 17, 3])
            writer.writerow(['2023-10-01T01:00:00Z', 'bad-lang', 100, 4])
            writer.writerow(['2023-10-01T02:00:00Z', 'it-IT', -1, 4])
            writer.writerow(['2023-10-01T03:00:00Z', 'pt-BR', 120, 0])

        run_submission()
        verify_outputs(CSV_FILE)
    finally:
        shutil.copy2(backup_csv, CSV_FILE)
        shutil.rmtree(backup_dir)

    # Run the required artifact afresh against the original telemetry, then retain
    # all of the original output assertions.
    run_submission()
    verify_outputs(CSV_FILE)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
