#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path

EXE = Path('/home/user/filter_pdb')
SOURCE = Path('/home/user/filter_pdb.c')
LIBSRC = Path('/app/struccalc-1.0')


def run(cmd, **kwargs):
    result = subprocess.run(cmd, capture_output=True, text=True, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {cmd}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def parse_exact_output(stdout, directory):
    expected_files = sorted(p.name for p in Path(directory).iterdir() if p.name.endswith('.pdb'))
    lines = stdout.splitlines()
    assert len(lines) == len(expected_files), (
        f"Expected exactly {len(expected_files)} output lines, got {len(lines)}: {lines!r}"
    )

    results = {}
    pattern = re.compile(r'^([^/:]+): (STABLE|UNSTABLE)$')
    for line in lines:
        match = pattern.fullmatch(line)
        assert match, f"Malformed or extra output line: {line!r}"
        filename, status = match.groups()
        assert filename not in results, f"Duplicate output for {filename}"
        results[filename] = status

    assert set(results) == set(expected_files), (
        f"Output filenames differ from directory PDB files: got {set(results)}, "
        f"expected {set(expected_files)}"
    )
    return results


def run_filter(directory, env=None):
    result = subprocess.run([str(EXE), str(directory)], capture_output=True, text=True, env=env)
    assert result.returncode == 0, (
        f"Execution failed for {directory}; stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    return parse_exact_output(result.stdout, directory)


def test_artifacts_and_library_rebuild():
    assert EXE.is_file(), f"Executable {EXE} not found"
    assert os.access(EXE, os.X_OK), f"{EXE} is not executable"
    assert SOURCE.is_file(), f"C source {SOURCE} not found"

    dynamic = run(['readelf', '-d', str(EXE)]).stdout
    assert 'libstruccalc' in dynamic, 'filter_pdb is not dynamically linked to libstruccalc'

    required = ['Makefile', 'struccalc.h', 'struccalc.c', 'matrix_solve.c']
    for name in required:
        assert (LIBSRC / name).is_file(), f"Missing vendored source file {name}"

    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        build = td / 'src'
        build.mkdir()
        for name in required:
            shutil.copy2(LIBSRC / name, build / name)

        run(['make'], cwd=build)
        prefix = td / 'prefix'
        run(['make', 'install', f'PREFIX={prefix}'], cwd=build)
        library = prefix / 'lib' / 'libstruccalc.so'
        header = prefix / 'include' / 'struccalc.h'
        assert library.is_file(), 'make install did not install libstruccalc.so'
        assert header.is_file(), 'make install did not install struccalc.h'

        probe = td / 'probe.c'
        probe.write_text(r'''#include <math.h>
#include <stdio.h>
#include "struccalc.h"
int main(void) {
    double zero[3][3] = {{0}};
    double near_singular[3][3] = {
        {1e-15, 0, 0}, {0, 1e-15, 0}, {0, 0, 1e-15}
    };
    factorize_covariance(zero);
    factorize_covariance(near_singular);
    for (int i = 0; i < 3; ++i)
        for (int j = 0; j < 3; ++j)
            if (!isfinite(zero[i][j]) || !isfinite(near_singular[i][j])) return 2;
    return 0;
}
''')
        probe_exe = td / 'probe'
        run([
            'gcc', str(probe), '-I' + str(prefix / 'include'),
            '-L' + str(prefix / 'lib'), '-lstruccalc', '-lm',
            '-Wl,-rpath,' + str(prefix / 'lib'), '-o', str(probe_exe)
        ])
        run([str(probe_exe)])


def test_clean_corpus():
    clean = Path('/app/data/clean')
    assert clean.is_dir()
    results = run_filter(clean)
    assert all(status == 'STABLE' for status in results.values()), results


def test_evil_corpus():
    evil = Path('/app/data/evil')
    assert evil.is_dir()
    results = run_filter(evil)
    assert all(status == 'UNSTABLE' for status in results.values()), results


def fnv64(name):
    value = 1469598103934665603
    for byte in name.encode():
        value ^= byte
        value = (value * 1099511628211) & ((1 << 64) - 1)
    return value


def classification(name):
    value = fnv64(name)
    if value % 11 == 0:
        return 'UNSTABLE', False
    if value % 3 == 0:
        return 'STABLE', True
    return 'UNSTABLE', True


def test_unseen_inputs_use_library_and_have_exact_output():
    with tempfile.TemporaryDirectory() as td_raw:
        td = Path(td_raw)
        corpus = td / 'unseen'
        corpus.mkdir()

        chosen = []
        seen_categories = set()
        while len(chosen) < 15 or seen_categories != {'stable', 'unstable', 'invalid'}:
            name = 'sample_' + secrets.token_hex(8) + '.pdb'
            status, valid = classification(name)
            category = 'invalid' if not valid else ('stable' if status == 'STABLE' else 'unstable')
            chosen.append((name, status, valid))
            seen_categories.add(category)

        for name, _, _ in chosen:
            (corpus / name).write_text('ATOM      1  CA  TST A   1       0.000   0.000   0.000\n')
        (corpus / ('ignored_' + secrets.token_hex(4) + '.txt')).write_text('not a pdb\n')

        shim_c = td / 'shim.c'
        shim_c.write_text(r'''#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "struccalc.h"

static unsigned long long hash_name(const char *s) {
    unsigned long long h = 1469598103934665603ULL;
    const char *base = strrchr(s, '/');
    s = base ? base + 1 : s;
    while (*s) { h ^= (unsigned char)*s++; h *= 1099511628211ULL; }
    return h;
}
static void log_call(char kind, const char *name) {
    const char *path = getenv("SC_TRACE");
    if (!path) return;
    FILE *f = fopen(path, "a");
    if (f) { fprintf(f, "%c %s\n", kind, name ? name : "(null)"); fclose(f); }
}
PDB *parse_pdb(const char *filename) {
    PDB *p = (PDB *)calloc(1, sizeof(PDB));
    if (!p) return NULL;
    strncpy(p->name, filename, sizeof(p->name) - 1);
    log_call('P', filename);
    if (strcmp(filename, "/app/reference/ideal.pdb") == 0) {
        p->valid = 1;
        p->coords[0][0] = 0.0;
        return p;
    }
    unsigned long long h = hash_name(filename);
    p->valid = (h % 11ULL != 0ULL);
    p->coords[0][0] = (h % 3ULL == 0ULL) ? 1.0 : 5.0;
    return p;
}
double compute_wasserstein_dist(PDB *structure, PDB *reference) {
    log_call('C', structure ? structure->name : "(null)");
    if (!structure || !reference || !structure->valid || !reference->valid) return -1.0;
    return structure->coords[0][0];
}
void factorize_covariance(double mat[3][3]) { (void)mat; }
''')
        shim = td / 'libshim.so'
        run(['gcc', '-shared', '-fPIC', '-I' + str(LIBSRC), str(shim_c), '-o', str(shim)])

        trace = td / 'trace.log'
        env = os.environ.copy()
        env['LD_PRELOAD'] = str(shim)
        env['SC_TRACE'] = str(trace)
        results = run_filter(corpus, env=env)

        expected = {name: status for name, status, _ in chosen}
        assert results == expected, f"Unseen-input classifications differ: {results} != {expected}"

        assert trace.is_file(), 'No calls into the injected struccalc implementation were observed'
        trace_lines = trace.read_text().splitlines()
        parsed = {Path(line[2:]).name for line in trace_lines if line.startswith('P ')}
        computed = {Path(line[2:]).name for line in trace_lines if line.startswith('C ')}
        assert 'ideal.pdb' in parsed, 'Reference PDB was not parsed through struccalc'
        for name, _, valid in chosen:
            assert name in parsed, f"{name} was not parsed through struccalc"
            if valid:
                assert name in computed, f"Wasserstein distance was not computed for {name}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
