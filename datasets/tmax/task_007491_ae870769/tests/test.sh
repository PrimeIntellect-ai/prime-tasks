#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shlex
import stat
import subprocess
import time
from pathlib import Path

import pytest

HOME = Path('/home/user')
PIPELINE = HOME / 'pipeline.sh'
METRICS = HOME / 'metrics.txt'

EXPECTED_CPP = '''#include <iostream>
#include <fstream>
#include <vector>
#include <cmath>

void refine_mesh() {
    volatile double sum = 0;
    for(int i=0; i<50000000; ++i) sum += sin(i);
}

void process_spectroscopy() {
    std::ofstream out("peaks.csv");
    for(int i=0; i<200; ++i) {
        out << 50.0 + 10.0 * sin(i) << "\\n";
    }
    out.close();
}

int main() {
    refine_mesh();
    process_spectroscopy();
    return 0;
}
'''

EXPECTED_DENSITY = '''import numpy as np
from scipy.stats import gaussian_kde

data = np.loadtxt('/home/user/peaks.csv')
kde = gaussian_kde(data)
x = np.linspace(30, 70, 1000)
y = kde(x)
print(f"{np.max(y):.4f}")
'''


def install_wrappers(tmp_path, marker):
    wrappers = []
    compile_log = tmp_path / 'gpp.log'
    gprof_log = tmp_path / 'gprof.log'

    for command, log, body in (
        ('g++', compile_log, '''{
  echo BEGIN
  printf 'ARG=%q\\n' "$@"
  echo END
} >> "$VERIFY_LOG"
exec "$VERIFY_REAL" "$@"
'''),
        ('gprof', gprof_log, '''{
  echo BEGIN
  printf 'ARG=%q\\n' "$@"
  echo END
} >> "$VERIFY_LOG"
out=$("$VERIFY_REAL" "$@")
rc=$?
[ "$rc" -eq 0 ] || exit "$rc"
printf '%s\\n' "$out" | awk -v marker="$GPROF_MARKER" '
  /refine_mesh/ { sub(/^[[:space:]]*[0-9]+([.][0-9]+)?/, marker) }
  { print }
'
'''),
    ):
        path = Path('/usr/bin') / command
        backup = Path('/usr/bin') / (command + '.__verifier_real')
        assert path.exists() or path.is_symlink(), f'Missing required command: {path}'
        assert not backup.exists(), f'Stale verifier backup exists: {backup}'
        os.rename(path, backup)
        path.write_text('#!/bin/bash\nset -o pipefail\n' + body)
        path.chmod(0o755)
        wrappers.append((path, backup, log))

    return wrappers, compile_log, gprof_log


def restore_wrappers(wrappers):
    for path, backup, _ in reversed(wrappers):
        try:
            if path.exists() or path.is_symlink():
                path.unlink()
        finally:
            if backup.exists() or backup.is_symlink():
                os.rename(backup, path)


def parse_invocations(log_path):
    invocations = []
    current = None
    for line in log_path.read_text().splitlines() if log_path.exists() else []:
        if line == 'BEGIN':
            current = []
        elif line == 'END' and current is not None:
            invocations.append(current)
            current = None
        elif current is not None and line.startswith('ARG='):
            parsed = shlex.split(line[4:])
            assert len(parsed) == 1
            current.append(parsed[0])
    return invocations


def remove_outputs():
    for name in ('spectro', 'peaks.csv', 'gmon.out', 'metrics.txt'):
        path = HOME / name
        if path.exists() or path.is_symlink():
            path.unlink()


def run_pipeline(tmp_path, gprof_marker):
    remove_outputs()
    wrappers = []
    try:
        wrappers, compile_log, gprof_log = install_wrappers(tmp_path, gprof_marker)
        env = os.environ.copy()
        env['GPROF_MARKER'] = f'{gprof_marker:.2f}'
        # Each wrapper receives its own log and real executable via a tiny dispatcher
        # by inspecting argv[0]. Install per-command environment through wrapper files.
        for path, backup, log in wrappers:
            text = path.read_text()
            text = text.replace('set -o pipefail\n',
                                f"set -o pipefail\nVERIFY_REAL={shlex.quote(str(backup))}\nVERIFY_LOG={shlex.quote(str(log))}\n")
            path.write_text(text)
            path.chmod(0o755)

        started = time.time()
        result = subprocess.run(
            [str(PIPELINE)], cwd=str(HOME), env=env,
            capture_output=True, text=True, timeout=180
        )
    finally:
        restore_wrappers(wrappers)

    assert result.returncode == 0, (
        f'pipeline.sh failed with return code {result.returncode}.\n'
        f'stdout: {result.stdout}\nstderr: {result.stderr}'
    )

    assert METRICS.is_file(), 'pipeline.sh did not create metrics.txt'
    lines = [line.strip() for line in METRICS.read_text().splitlines() if line.strip()]
    assert len(lines) == 2, f'Expected exactly 2 lines in metrics.txt, found {len(lines)}.'
    try:
        values = [float(line) for line in lines]
    except ValueError:
        pytest.fail(f'metrics.txt must contain only two numeric lines, got: {lines!r}')

    spectro = HOME / 'spectro'
    peaks = HOME / 'peaks.csv'
    gmon = HOME / 'gmon.out'
    assert spectro.is_file() and os.access(spectro, os.X_OK), 'Missing executable spectro'
    assert spectro.read_bytes()[:4] == b'\x7fELF', 'spectro is not an ELF executable'
    assert spectro.stat().st_mtime >= started - 1, 'spectro was not freshly built'
    assert peaks.is_file() and len(peaks.read_text().splitlines()) == 200, 'spectro did not generate the expected peaks.csv'
    assert gmon.is_file() and gmon.stat().st_size > 0, 'spectro did not generate gmon.out'

    compile_calls = parse_invocations(compile_log)
    valid_compile = False
    for args in compile_calls:
        normalized = [os.path.abspath(a) if a.endswith('spectro.cpp') else a for a in args]
        if '-O2' in args and '-pg' in args and str(HOME / 'spectro.cpp') in normalized and '-o' in args:
            out_index = args.index('-o') + 1
            if out_index < len(args) and os.path.abspath(args[out_index]) == str(HOME / 'spectro'):
                valid_compile = True
    assert valid_compile, 'pipeline.sh did not invoke g++ with -O2, -pg, spectro.cpp, and -o spectro'

    gprof_calls = parse_invocations(gprof_log)
    assert gprof_calls, 'pipeline.sh did not invoke gprof'
    assert any(any(os.path.basename(arg) == 'spectro' for arg in args) for args in gprof_calls), \
        'gprof was not invoked on the spectro executable'

    return values


def test_pipeline_sh_executable_and_sources_unchanged():
    assert PIPELINE.is_file(), f'Missing required file: {PIPELINE}'
    assert os.access(PIPELINE, os.X_OK), f'File {PIPELINE} is not executable.'
    assert (HOME / 'spectro.cpp').read_text() == EXPECTED_CPP, 'spectro.cpp was modified'
    assert (HOME / 'density.py').read_text() == EXPECTED_DENSITY, 'density.py was modified'


def test_pipeline_execution_and_metrics(tmp_path):
    marker = random.uniform(65.0, 90.0)
    values = run_pipeline(tmp_path / 'normal', marker)

    # Preserve the original verifier's numeric assertions.
    assert 50.0 <= values[0] <= 100.0, f'Expected refine_mesh % time between 50.0 and 100.0, got {values[0]}.'
    assert 0.060 <= values[1] <= 0.063, f'Expected KDE maximum around 0.0617, got {values[1]}.'

    # The gprof wrapper runs the real profiler, then changes only refine_mesh's
    # reported first column. This proves the script extracts that field.
    assert abs(values[0] - marker) < 0.011, \
        f'First metric was not extracted from the refine_mesh flat-profile row: expected {marker:.2f}, got {values[0]}'


def test_pipeline_uses_density_output_and_gprof_field(tmp_path):
    density = HOME / 'density.py'
    original = density.read_bytes()
    original_mode = stat.S_IMODE(density.stat().st_mode)
    density_marker = random.uniform(0.0601, 0.0629)
    gprof_marker = random.uniform(52.0, 97.0)
    try:
        density.write_text(f'print("{density_marker:.8f}")\n')
        density.chmod(original_mode)
        values = run_pipeline(tmp_path / 'challenge', gprof_marker)
    finally:
        density.write_bytes(original)
        density.chmod(original_mode)

    assert abs(values[0] - gprof_marker) < 0.011, \
        f'First metric was not derived from gprof output: expected {gprof_marker:.2f}, got {values[0]}'
    assert abs(values[1] - density_marker) < 1e-9, \
        f'Second metric was not the output of density.py: expected {density_marker:.8f}, got {values[1]}'
    assert density.read_text() == EXPECTED_DENSITY
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
