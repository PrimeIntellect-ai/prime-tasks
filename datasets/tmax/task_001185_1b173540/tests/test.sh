#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
from pathlib import Path

PROJECT = Path('/home/user/math_project')
RESULT = PROJECT / 'result.txt'
LIBRARY = PROJECT / 'libmathparse.so'
MAIN = PROJECT / 'main'


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, timeout=30, **kwargs)


def assert_elf(path, executable=False):
    assert path.is_file(), f'{path} does not exist or is not a regular file.'
    with path.open('rb') as f:
        assert f.read(4) == b'\x7fELF', f'{path} is not an ELF binary.'
    if executable:
        assert os.access(path, os.X_OK), f'{path} is not executable.'


def test_result_file_exists():
    """Retain the original assertion that the agent generated result.txt."""
    assert RESULT.is_file(), (
        f'The file {RESULT} does not exist. Did you successfully build and run the executable?'
    )


def test_result_file_content():
    """Retain the original exact output assertion."""
    assert RESULT.is_file(), f'Cannot check content, {RESULT} is missing.'
    content = RESULT.read_text().strip()
    assert content == '150.00', (
        f"The content of {RESULT} is incorrect. Expected '150.00', but got '{content}'."
    )


def test_binaries_exist_and_are_real():
    """Retain the existence checks and reject placeholder artifacts."""
    assert LIBRARY.is_file(), f'The shared library {LIBRARY} was not built.'
    assert MAIN.is_file(), f'The executable {MAIN} was not built.'
    assert_elf(LIBRARY)
    assert_elf(MAIN, executable=True)


def test_clean_make_and_runtime_loading():
    """Force Makefile reconstruction and run main without LD_LIBRARY_PATH."""
    LIBRARY.unlink(missing_ok=True)
    MAIN.unlink(missing_ok=True)
    RESULT.unlink(missing_ok=True)

    built = run(['make', '-B'], cwd=PROJECT)
    assert built.returncode == 0, f'make failed:\n{built.stdout}'
    assert_elf(LIBRARY)
    assert_elf(MAIN, executable=True)

    dynamic = run(['readelf', '-d', str(MAIN)])
    assert dynamic.returncode == 0, f'readelf failed:\n{dynamic.stdout}'
    assert 'libmathparse.so' in dynamic.stdout, (
        'main has no dynamic dependency on libmathparse.so.'
    )

    env = {
        'PATH': '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
        'HOME': '/home/user',
    }
    executed = run(['./main'], cwd=PROJECT, env=env)
    assert executed.returncode == 0, (
        'The rebuilt ./main did not run successfully with no LD_LIBRARY_PATH set:\n'
        + executed.stdout
    )
    assert RESULT.is_file(), 'Running the rebuilt ./main did not create result.txt.'
    assert RESULT.read_text().strip() == '150.00', (
        f'Running the rebuilt ./main produced {RESULT.read_text()!r}, not 150.00.'
    )


def make_harness():
    rng = random.SystemRandom()
    cases = []
    for length in [1, 2, 3, 5, 8, 17, 31, 63]:
        values = [rng.randrange(256) for _ in range(length)]
        encoded = f'{length:02X}' + ''.join(f'{v:02X}' for v in values)
        cases.append((encoded, sum(values)))

    lines = [
        '#include <math.h>',
        '#include <stdio.h>',
        '#include "libmathparse.h"',
        'int main(void) {',
    ]
    for index, (encoded, expected) in enumerate(cases):
        lines.extend([
            f'  double got_{index} = process_data("{encoded}");',
            f'  if (fabs(got_{index} - {expected}.0) > 0.000001) {{',
            f'    fprintf(stderr, "case {index}: got %.17g, expected {expected}\\n", got_{index});',
            '    return 1;',
            '  }',
        ])
    lines.extend(['  return 0;', '}'])
    path = Path('/tmp/mathparse_harness.c')
    path.write_text('\n'.join(lines) + '\n')
    return path


def test_library_behavior_on_derived_inputs():
    """Exercise the submitted shared library on verifier-generated inputs."""
    harness = make_harness()
    binary = Path('/tmp/mathparse_behavior')
    compiled = run([
        'gcc', '-o', str(binary), str(harness), '-I', str(PROJECT),
        '-L', str(PROJECT), '-lmathparse',
        f'-Wl,-rpath,{PROJECT}', '-lm'
    ])
    assert compiled.returncode == 0, f'Could not link against libmathparse.so:\n{compiled.stdout}'
    checked = run([str(binary)])
    assert checked.returncode == 0, (
        'libmathparse.so failed verifier-generated calculations:\n' + checked.stdout
    )


def test_parser_source_has_no_heap_overflow():
    """Compile the submitted parser with ASan and exercise multiple payload lengths."""
    harness = make_harness()
    binary = Path('/tmp/mathparse_asan')
    compiled = run([
        'gcc', '-fsanitize=address', '-fno-omit-frame-pointer', '-g',
        '-o', str(binary), str(harness), str(PROJECT / 'libmathparse.c'),
        '-I', str(PROJECT), '-lm'
    ])
    assert compiled.returncode == 0, (
        'Could not compile libmathparse.c with AddressSanitizer:\n' + compiled.stdout
    )
    env = os.environ.copy()
    env['ASAN_OPTIONS'] = 'abort_on_error=1:detect_leaks=0'
    checked = run([str(binary)], env=env)
    assert checked.returncode == 0, (
        'AddressSanitizer or calculation checks failed for libmathparse.c:\n'
        + checked.stdout
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
