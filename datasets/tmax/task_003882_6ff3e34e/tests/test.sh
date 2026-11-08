#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import math
import os
import pathlib
import re
import subprocess

HOME = pathlib.Path('/home/user')
DATASET = HOME / 'dataset.csv'
OUTPUT = HOME / 'top_pc.txt'
ORIGINAL_DATASET = b'''1.0,2.0,3.0
2.0,NaN,4.0
3.0,4.0,5.0
105.0,6.0,7.0
5.0,8.0,9.0
'''
FORMAT_RE = re.compile(r'^\s*-?\d+\.\d{4}\s*,\s*-?\d+\.\d{4}\s*,\s*-?\d+\.\d{4}\s*$')


def expected_pc(rows):
    cleaned = []
    for row in rows:
        cleaned.append([
            float('nan') if (math.isnan(v) or v > 100.0 or v < -100.0) else v
            for v in row
        ])

    means = []
    for col in range(3):
        valid = [row[col] for row in cleaned if not math.isnan(row[col])]
        assert valid, 'Verifier test data unexpectedly has an empty column.'
        means.append(sum(valid) / len(valid))

    centered = []
    for row in cleaned:
        imputed = [means[j] if math.isnan(row[j]) else row[j] for j in range(3)]
        centered.append([imputed[j] - means[j] for j in range(3)])

    n = len(centered)
    cov = [[sum(row[i] * row[j] for row in centered) / (n - 1)
            for j in range(3)] for i in range(3)]

    # Jacobi diagonalization for this symmetric 3x3 matrix.
    a = [row[:] for row in cov]
    vectors = [[1.0 if i == j else 0.0 for j in range(3)] for i in range(3)]
    for _ in range(100):
        p, q = max(((0, 1), (0, 2), (1, 2)), key=lambda ij: abs(a[ij[0]][ij[1]]))
        if abs(a[p][q]) < 1e-14:
            break
        phi = 0.5 * math.atan2(2.0 * a[p][q], a[q][q] - a[p][p])
        c, s = math.cos(phi), math.sin(phi)
        for k in range(3):
            if k != p and k != q:
                akp, akq = a[k][p], a[k][q]
                a[k][p] = a[p][k] = c * akp - s * akq
                a[k][q] = a[q][k] = s * akp + c * akq
        app, aqq, apq = a[p][p], a[q][q], a[p][q]
        a[p][p] = c*c*app - 2.0*s*c*apq + s*s*aqq
        a[q][q] = s*s*app + 2.0*s*c*apq + c*c*aqq
        a[p][q] = a[q][p] = 0.0
        for k in range(3):
            vkp, vkq = vectors[k][p], vectors[k][q]
            vectors[k][p] = c * vkp - s * vkq
            vectors[k][q] = s * vkp + c * vkq

    index = max(range(3), key=lambda i: a[i][i])
    result = [vectors[i][index] for i in range(3)]
    norm = math.sqrt(sum(x*x for x in result))
    result = [x / norm for x in result]
    if result[0] < 0:
        result = [-x for x in result]
    return result


def csv_text(rows):
    def field(value):
        return 'NaN' if math.isnan(value) else repr(float(value))
    return ''.join(','.join(field(value) for value in row) + '\n' for row in rows)


def read_result():
    assert OUTPUT.exists(), f'{OUTPUT} does not exist after executing the program.'
    assert OUTPUT.is_file(), f'{OUTPUT} is not a file.'
    content = OUTPUT.read_text().strip()
    assert FORMAT_RE.fullmatch(content), (
        'Output must contain exactly three comma-separated numbers, each with exactly four decimal places.'
    )
    return [float(part.strip()) for part in content.split(',')]


def exercise(binary, rows):
    DATASET.write_text(csv_text(rows))
    if OUTPUT.exists() or OUTPUT.is_symlink():
        OUTPUT.unlink()
    completed = subprocess.run([str(binary)], cwd=str(HOME), stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, timeout=10)
    assert completed.returncode == 0, (
        f'Compiled program exited with {completed.returncode}: {completed.stderr}'
    )
    actual = read_result()
    expected = expected_pc(rows)
    for i, (got, want) in enumerate(zip(actual, expected)):
        assert math.isclose(got, want, abs_tol=0.0002), (
            f'Principal component {i} is {got}, expected {want:.4f}.'
        )


def build_and_exercise_submission():
    eigen_headers = glob.glob('/home/user/eigen/**/Eigen/Dense', recursive=True)
    assert eigen_headers, 'No locally downloaded Eigen3 headers were found under /home/user/eigen.'
    include_roots = sorted({str(pathlib.Path(header).parent.parent) for header in eigen_headers})

    sources = []
    for extension in ('*.cpp', '*.cc', '*.cxx'):
        for source in HOME.rglob(extension):
            try:
                source.relative_to(HOME / 'eigen')
                continue
            except ValueError:
                pass
            sources.append(source)
    sources = sorted(set(sources))
    assert sources, 'No C++ source file was found under /home/user.'

    include_pattern = re.compile(r'^\s*#\s*include\s*[<\"][^>\"]*Eigen/', re.MULTILINE)
    assert any(include_pattern.search(source.read_text(errors='ignore')) for source in sources), (
        'The submitted C++ source does not include Eigen3.'
    )

    source_groups = [sources]
    source_groups.extend([[source] for source in sources if include_pattern.search(source.read_text(errors='ignore'))])
    binaries = []
    seen = set()
    for group in source_groups:
        key = tuple(group)
        if key in seen:
            continue
        seen.add(key)
        binary = pathlib.Path(f'/tmp/submission_{len(binaries)}')
        command = ['g++', '-std=c++17', '-O2']
        command.extend(str(source) for source in group)
        for root in include_roots:
            command.extend(['-I', root])
        command.extend(['-o', str(binary)])
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if result.returncode == 0:
            binaries.append(binary)
    assert binaries, 'The submitted Eigen3 C++ source could not be compiled.'

    cases = [
        [
            [1.0, 2.0, 3.0], [2.0, float('nan'), 4.0], [3.0, 4.0, 5.0],
            [105.0, 6.0, 7.0], [5.0, 8.0, 9.0],
        ],
        [
            [-100.0, 1.0, 9.0], [100.0, 3.0, 7.0], [100.01, 4.0, 6.0],
            [-100.01, 8.0, 2.0], [float('nan'), 11.0, -1.0],
            [35.0, float('nan'), -5.0], [48.0, 17.0, float('nan')],
        ],
        [
            [4.0, -8.0, 2.0], [7.0, -3.0, 9.0], [13.0, 2.0, 8.0],
            [21.0, 10.0, -4.0], [34.0, 19.0, -13.0], [55.0, 31.0, -20.0],
            [101.0, 44.0, -37.0], [89.0, -101.0, float('nan')],
        ],
    ]

    errors = []
    for binary in binaries:
        try:
            for rows in cases:
                exercise(binary, rows)
            DATASET.write_bytes(ORIGINAL_DATASET)
            exercise(binary, cases[0])
            return binary
        except Exception as exc:
            errors.append(f'{binary}: {exc}')
    DATASET.write_bytes(ORIGINAL_DATASET)
    raise AssertionError('No freshly compiled submission passed the required processing tests. ' + ' | '.join(errors))


SELECTED_BINARY = build_and_exercise_submission()


def test_top_pc_file_exists():
    """Check if the output file was created."""
    file_path = "/home/user/top_pc.txt"
    assert os.path.exists(file_path), f"{file_path} does not exist."
    assert os.path.isfile(file_path), f"{file_path} is not a file."


def test_top_pc_content():
    """Check if the output file contains the correct principal component."""
    file_path = "/home/user/top_pc.txt"
    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content, f"The file {file_path} is empty."

    parts = [p.strip() for p in content.split(",")]
    assert len(parts) == 3, f"Expected 3 comma-separated values in {file_path}, got {len(parts)}."

    expected = [0.3533, 0.6121, 0.7071]
    for i in range(3):
        try:
            val = float(parts[i])
        except ValueError:
            assert False, f"Could not parse '{parts[i]}' as a float."

        assert math.isclose(val, expected[i], abs_tol=0.0002), (
            f"Value at index {i} is {val}, expected {expected[i]} (within 0.0002 tolerance)."
        )


def test_top_pc_exact_format():
    content = pathlib.Path('/home/user/top_pc.txt').read_text().strip()
    assert FORMAT_RE.fullmatch(content), 'Each component must be formatted to exactly four decimal places.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
