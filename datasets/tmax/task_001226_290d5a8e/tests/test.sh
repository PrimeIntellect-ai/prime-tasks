#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import os
import pathlib
import random
import secrets
import subprocess

DATA_DIR = pathlib.Path('/home/user/data')
SOURCE = pathlib.Path('/home/user/process_data.c')
EXECUTABLE = pathlib.Path('/home/user/process_data')
RESULTS = pathlib.Path('/home/user/results.csv')
FILES = ('institutions.tsv', 'authors.tsv', 'publications.tsv')
BASELINE_EXPECTED = [
    'University of British Columbia,100',
    'University of Toronto,90',
    'University of Waterloo,80',
]


def read_results():
    assert RESULTS.is_file(), f'The output file {RESULTS} does not exist.'
    with RESULTS.open('r') as f:
        return [line.strip() for line in f if line.strip()]


def run_and_check(program, expected):
    if RESULTS.exists() or RESULTS.is_symlink():
        RESULTS.unlink()
    proc = subprocess.run(
        [str(program)], cwd='/home/user', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=8
    )
    assert proc.returncode == 0, (
        f'{program} exited with status {proc.returncode}.\n'
        f'stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}'
    )
    actual = read_results()
    assert actual == expected, (
        f'Incorrect output from {program}.\n'
        f'Expected:\n{chr(10).join(expected)}\n'
        f'Actual:\n{chr(10).join(actual)}'
    )


def write_dataset(institutions, authors, publications):
    rows = {
        'institutions.tsv': institutions,
        'authors.tsv': authors,
        'publications.tsv': publications,
    }
    for filename, records in rows.items():
        (DATA_DIR / filename).write_text(
            ''.join('\t'.join(map(str, row)) + '\n' for row in records)
        )


def make_case():
    rng = random.SystemRandom()
    suffix = secrets.token_hex(5)
    inst_ids = rng.sample(range(1000, 9000), 6)
    author_ids = rng.sample(range(20000, 80000), 8)
    pub_ids = iter(rng.sample(range(100000, 900000), 40))

    institutions = []
    for i, inst_id in enumerate(inst_ids):
        country = 'Canada' if i < 5 else 'USA'
        institutions.append((inst_id, f'Institute_{suffix}_{i}', country))

    authors = []
    for i, inst_id in enumerate(inst_ids):
        authors.append((author_ids[i], f'Author_{suffix}_{i}', inst_id))
    authors.append((author_ids[6], f'Author_{suffix}_6', inst_ids[0]))
    authors.append((author_ids[7], f'Author_{suffix}_7', inst_ids[2]))

    publications = []
    for i, (author_id, _, _) in enumerate(authors):
        publications.append((next(pub_ids), author_id, f'Current_{i}', rng.randint(2011, 2025), rng.randint(11, 180)))
        publications.append((next(pub_ids), author_id, f'Boundary_{i}', 2010, rng.randint(300, 900)))
        if i % 2 == 0:
            publications.append((next(pub_ids), author_id, f'Extra_{i}', rng.randint(2012, 2024), rng.randint(1, 90)))

    rng.shuffle(institutions)
    rng.shuffle(authors)
    rng.shuffle(publications)

    inst_by_id = {row[0]: (row[1], row[2]) for row in institutions}
    author_to_inst = {row[0]: row[2] for row in authors}
    totals = {}
    for _, author_id, _, year, citations in publications:
        inst_id = author_to_inst.get(author_id)
        if inst_id is None:
            continue
        name, country = inst_by_id[inst_id]
        if country == 'Canada' and year > 2010:
            totals[name] = totals.get(name, 0) + citations
    expected = [f'{name},{total}' for name, total in sorted(totals.items(), key=lambda item: (-item[1], item[0]))[:3]]
    return institutions, authors, publications, expected


# Preserve the original verifier's assertions before changing any files.
assert read_results() == BASELINE_EXPECTED, (
    f'Contents of {RESULTS} do not match the expected output.'
)
assert SOURCE.is_file(), f'The source code file {SOURCE} does not exist.'
assert EXECUTABLE.is_file(), f'The compiled executable {EXECUTABLE} does not exist.'
assert os.access(EXECUTABLE, os.X_OK), f'The file {EXECUTABLE} is not executable.'
with EXECUTABLE.open('rb') as f:
    assert f.read(4) == b'\x7fELF', 'The submitted executable is not a compiled ELF executable.'

original_data = {name: (DATA_DIR / name).read_bytes() for name in FILES}
cases = [make_case(), make_case()]
compiled_copy = pathlib.Path('/tmp/process_data_from_source')

try:
    # Independently compile the submitted C source so dummy source cannot pass.
    build = subprocess.run(
        ['gcc', '-O3', str(SOURCE), '-o', str(compiled_copy)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert build.returncode == 0, f'Compilation failed:\n{build.stdout}\n{build.stderr}'
    assert compiled_copy.is_file() and os.access(compiled_copy, os.X_OK)

    # Execute the submitted executable on the original data and altered data.
    run_and_check(EXECUTABLE, BASELINE_EXPECTED)
    for institutions, authors, publications, expected in cases:
        write_dataset(institutions, authors, publications)
        run_and_check(EXECUTABLE, expected)

    # Exercise the binary independently compiled from the submitted source.
    for institutions, authors, publications, expected in cases:
        write_dataset(institutions, authors, publications)
        run_and_check(compiled_copy, expected)

    # Perform the required build command at the required output path, restore the
    # original dataset, execute that build, and re-check the original result.
    for name, content in original_data.items():
        (DATA_DIR / name).write_bytes(content)
    build = subprocess.run(
        ['gcc', '-O3', str(SOURCE), '-o', str(EXECUTABLE)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert build.returncode == 0, f'Compilation failed:\n{build.stdout}\n{build.stderr}'
    assert EXECUTABLE.is_file() and os.access(EXECUTABLE, os.X_OK)
    run_and_check(EXECUTABLE, BASELINE_EXPECTED)
finally:
    for name, content in original_data.items():
        (DATA_DIR / name).write_bytes(content)
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
