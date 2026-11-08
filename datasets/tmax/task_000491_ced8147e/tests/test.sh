#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import functools
import math
import os
import re
import subprocess
import pytest

GENERATOR_REF = r'''
#include <iostream>
#include <random>
#include <string>
int main(int argc, char* argv[]) {
    if (argc != 2) return 1;
    int N = std::stoi(argv[1]);
    std::mt19937 gen(12345);
    std::normal_distribution<double> dist(5.0, 1.41421356);
    for (int i = 0; i < N; ++i) std::cout << dist(gen) << "\n";
    return 0;
}
'''

BOOTSTRAP_REF = r'''
#include <algorithm>
#include <cstddef>
#include <iomanip>
#include <iostream>
#include <random>
#include <vector>
int main() {
    std::vector<double> values;
    double x;
    while (std::cin >> x) values.push_back(x);
    if (values.empty()) return 1;
    const std::size_t count = values.size();
    std::mt19937 gen(42);
    std::uniform_int_distribution<std::size_t> dist(0, count - 1);
    std::vector<double> means;
    means.reserve(1000);
    for (int b = 0; b < 1000; ++b) {
        double sum = 0.0;
        for (std::size_t i = 0; i < count; ++i) sum += values[dist(gen)];
        means.push_back(sum / static_cast<double>(count));
    }
    std::sort(means.begin(), means.end());
    std::cout << std::setprecision(17) << (means[974] - means[24]) << "\n";
    return 0;
}
'''

FLOAT_RE = re.compile(r'[+-]?(?:(?:\d+(?:\.\d*)?)|(?:\.\d+))(?:[eE][+-]?\d+)?')


def compile_cpp(source_text, output):
    source = output + '.cpp'
    with open(source, 'w') as f:
        f.write(source_text)
    subprocess.run(['g++', '-O3', source, '-o', output], check=True, timeout=60,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)


compile_cpp(GENERATOR_REF, '/tmp/reference_generator')
compile_cpp(BOOTSTRAP_REF, '/tmp/reference_bootstrap')


def run(cmd, input_bytes=None, timeout=60):
    result = subprocess.run(cmd, input=input_bytes, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=timeout)
    assert result.returncode == 0, (
        f"Command {cmd!r} failed with status {result.returncode}: "
        f"{result.stderr.decode(errors='replace')}"
    )
    return result.stdout


def parse_only_float(output, description):
    try:
        text = output.decode('ascii').strip()
    except UnicodeDecodeError:
        pytest.fail(f'{description} did not produce ASCII numeric output')
    assert FLOAT_RE.fullmatch(text), f'{description} must print only one float, got {text!r}'
    value = float(text)
    assert math.isfinite(value), f'{description} produced a non-finite value'
    return value


def assert_close(actual, expected, description):
    assert math.isclose(actual, expected, rel_tol=2e-5, abs_tol=2e-7), (
        f'{description}: expected {expected}, got {actual}'
    )


def assert_elf(path):
    with open(path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f'{path} is not a compiled ELF executable'


def compile_submitted_sources():
    assert os.path.isfile('/home/user/generator.cpp'), '/home/user/generator.cpp is missing.'
    assert os.path.isfile('/home/user/bootstrap.cpp'), '/home/user/bootstrap.cpp is missing.'
    subprocess.run(['g++', '-O3', '/home/user/generator.cpp', '-o', '/tmp/submitted_generator'],
                   check=True, timeout=60, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    subprocess.run(['g++', '-O3', '/home/user/bootstrap.cpp', '-o', '/tmp/submitted_bootstrap'],
                   check=True, timeout=60, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


@functools.lru_cache(maxsize=1)
def convergence_results():
    sizes = [100, 500, 1000, 5000, 10000]
    results = []
    for n in sizes:
        expected_data = run(['/tmp/reference_generator', str(n)])
        actual_data = run(['/home/user/generator', str(n)])
        assert actual_data == expected_data, f'generator output is incorrect for N={n}'

        expected_width = parse_only_float(
            run(['/tmp/reference_bootstrap'], expected_data),
            f'reference bootstrap for N={n}'
        )
        actual_width = parse_only_float(
            run(['/home/user/bootstrap'], actual_data),
            f'/home/user/bootstrap for N={n}'
        )
        assert_close(actual_width, expected_width, f'bootstrap width for N={n}')
        results.append((n, actual_width, expected_width, actual_data))
    return results


def test_executables_exist():
    assert os.path.isfile('/home/user/generator'), '/home/user/generator executable is missing.'
    assert os.access('/home/user/generator', os.X_OK), '/home/user/generator is not executable.'
    assert os.path.isfile('/home/user/bootstrap'), '/home/user/bootstrap executable is missing.'
    assert os.access('/home/user/bootstrap', os.X_OK), '/home/user/bootstrap is not executable.'
    assert_elf('/home/user/generator')
    assert_elf('/home/user/bootstrap')


def test_sources_compile_and_implement_required_programs():
    compile_submitted_sources()
    for n in (1, 17, 257):
        expected = run(['/tmp/reference_generator', str(n)])
        assert run(['/tmp/submitted_generator', str(n)]) == expected, (
            f'generator.cpp produces incorrect output for N={n}'
        )

    datasets = [
        b'3.25\n',
        b'-4\n1.5\n8.25\n0\n-2.75\n9\n3.125\n',
        ''.join(f'{((i * 37) % 101 - 50) / 7.0:.12f}\n' for i in range(137)).encode(),
    ]
    for i, data in enumerate(datasets):
        expected = parse_only_float(run(['/tmp/reference_bootstrap'], data), 'reference bootstrap')
        for executable in ('/tmp/submitted_bootstrap', '/home/user/bootstrap'):
            actual = parse_only_float(run([executable], data), executable)
            assert_close(actual, expected, f'{executable} on bootstrap test dataset {i}')


def test_sequential_convergence():
    results = convergence_results()
    successful = [(n, actual, expected) for n, actual, expected, _ in results if expected < 0.12]
    assert successful, 'No tested sample size has a CI width below 0.12'
    first_n, _, _ = successful[0]
    assert first_n == 5000, f'Expected the first converged N to be 5000, got {first_n}'
    for n, _, expected, _ in results:
        if n < first_n:
            assert expected >= 0.12, f'N={n} already converges and should have been selected first'


def test_training_data():
    data_file = '/home/user/training_data.txt'
    assert os.path.isfile(data_file), f'Missing {data_file}'
    with open(data_file, 'rb') as f:
        content = f.read()
    lines = content.splitlines()
    assert len(lines) == 5000, f'Expected 5000 lines in {data_file}, but found {len(lines)}.'
    for line in lines:
        try:
            value = float(line.strip())
            assert math.isfinite(value)
        except (ValueError, AssertionError):
            pytest.fail(f'Invalid float found in {data_file}: {line.decode(errors="replace")}')

    expected = run(['/tmp/reference_generator', '5000'])
    regenerated = run(['/home/user/generator', '5000'])
    assert content == regenerated, 'training_data.txt is not the output of a fresh generator 5000 run'
    assert content == expected, 'training_data.txt does not contain the supplied generator output'


def test_convergence_log():
    log_file = '/home/user/convergence_log.txt'
    assert os.path.isfile(log_file), f'Missing {log_file}'
    with open(log_file, 'r') as f:
        raw = f.read()
    assert raw.count('\n') <= 1 and ('\n' not in raw or raw.endswith('\n')), (
        f'Expected exactly one line in {log_file}'
    )
    content = raw[:-1] if raw.endswith('\n') else raw
    match = re.fullmatch(r'(\d+) (' + FLOAT_RE.pattern + r')', content)
    assert match, f'Expected exactly two values separated by one space in {log_file}, found {content!r}.'
    n_val, width_val = match.groups()
    assert n_val == '5000', f'Expected N=5000 in {log_file}, found {n_val}.'
    try:
        width = float(width_val)
    except ValueError:
        pytest.fail(f'Invalid float for CI width in {log_file}: {width_val}')
    assert math.isfinite(width), f'Invalid float for CI width in {log_file}: {width_val}'
    assert width < 0.12, f'Expected CI width < 0.12, but got {width}.'
    assert width > 0.05, f'CI width {width} seems suspiciously low for N=5000.'

    row = next(row for row in convergence_results() if row[0] == 5000)
    assert_close(width, row[1], 'logged CI width')
    assert_close(width, row[2], 'logged CI width versus required calculation')
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
