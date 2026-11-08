#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile
import uuid
from pathlib import Path

import numpy as np

SCRIPT = '/home/user/filter_signals.py'


def run_classifier(input_dir, log_file, cores=4, env=None):
    return subprocess.run(
        ['mpiexec', '--allow-run-as-root', '-n', str(cores), 'python', SCRIPT, input_dir, log_file],
        capture_output=True,
        text=True,
        timeout=180,
        env=env,
    )


def read_log(path):
    if not os.path.exists(path):
        return []
    with open(path, 'r') as f:
        return [line.strip() for line in f if line.strip()]


def test_filter_signals_script_exists():
    assert os.path.isfile(SCRIPT), 'The script /home/user/filter_signals.py does not exist.'


def test_evil_corpus_rejected():
    evil_dir = '/app/corpus/evil'
    log_file = '/home/user/evil_rejected.log'

    result = run_classifier(evil_dir, log_file, 4)
    assert result.returncode == 0, f'Script failed on evil corpus. Return code {result.returncode}.\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}'
    assert os.path.isfile(log_file), f'Log file {log_file} was not created.'

    lines = read_log(log_file)
    expected_files = {f'evil_{i:03d}.npy' for i in range(100)}
    actual_files = set(lines)
    missing = expected_files - actual_files
    extra = actual_files - expected_files

    assert len(missing) == 0, f'{len(missing)} of 100 evil bypassed. Missing in log: {list(missing)[:5]}'
    assert len(extra) == 0, f'Extra files in evil log: {list(extra)[:5]}'


def test_clean_corpus_preserved():
    clean_dir = '/app/corpus/clean'
    log_file = '/home/user/clean_rejected.log'

    result = run_classifier(clean_dir, log_file, 4)
    assert result.returncode == 0, f'Script failed on clean corpus. Return code {result.returncode}.\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}'

    if not os.path.exists(log_file):
        return

    lines = read_log(log_file)
    assert len(lines) == 0, f'{len(lines)} of 100 clean modified/rejected. Offending files: {lines[:5]}'


def make_signal(residual_peak, peak_bin, n=2048):
    # Construct a real signal from a spectrum containing a smooth exponential
    # background plus one known residual peak. The expected label is therefore
    # derived from the specified 18.4 threshold, not from a filename or oracle.
    k = np.arange(n // 2 + 1, dtype=float)
    background = 7.0 + 0.4 * np.exp(-4.0 * k / (n // 2))
    spectrum = background.astype(np.complex128)
    spectrum[peak_bin] += residual_peak
    return np.fft.irfft(spectrum, n=n).astype(np.float64)


def write_trace_hook(hook_dir):
    hook = r'''
import os

_trace = os.environ.get('FILTER_TRACE_FILE')
_prefix = os.environ.get('FILTER_TRACE_PREFIX', '')
_rank = os.environ.get('OMPI_COMM_WORLD_RANK', '0')

def _record(kind, detail=''):
    if _trace:
        with open(_trace, 'a') as f:
            f.write('%s %s %s\n' % (kind, _rank, detail))

try:
    import numpy as _np
    _old_load = _np.load
    def _load(*args, **kwargs):
        if args and str(args[0]).startswith(_prefix):
            _record('LOAD', os.path.basename(str(args[0])))
        return _old_load(*args, **kwargs)
    _np.load = _load

    for _name in ('fft', 'rfft'):
        if hasattr(_np.fft, _name):
            _old = getattr(_np.fft, _name)
            def _make_fft(fn, name):
                def _wrapped(*args, **kwargs):
                    _record('FFT', name)
                    return fn(*args, **kwargs)
                return _wrapped
            setattr(_np.fft, _name, _make_fft(_old, _name))
except Exception:
    pass

try:
    import scipy.fft as _sfft
    for _name in ('fft', 'rfft'):
        if hasattr(_sfft, _name):
            _old = getattr(_sfft, _name)
            def _make_sfft(fn, name):
                def _wrapped(*args, **kwargs):
                    _record('FFT', 'scipy.' + name)
                    return fn(*args, **kwargs)
                return _wrapped
            setattr(_sfft, _name, _make_sfft(_old, _name))
except Exception:
    pass

try:
    import scipy.optimize as _opt
    _old_minimize = _opt.minimize
    def _minimize(*args, **kwargs):
        method = kwargs.get('method')
        if method is None and len(args) >= 4:
            method = args[3]
        if str(method).lower().replace('_', '-').replace(' ', '-') == 'nelder-mead':
            _record('NM', 'minimize')
        return _old_minimize(*args, **kwargs)
    _opt.minimize = _minimize

    _old_fmin = _opt.fmin
    def _fmin(*args, **kwargs):
        _record('NM', 'fmin')
        return _old_fmin(*args, **kwargs)
    _opt.fmin = _fmin
except Exception:
    pass
'''
    Path(hook_dir, 'sitecustomize.py').write_text(hook)


def test_randomized_mixed_corpus_uses_required_pipeline_and_mpi():
    with tempfile.TemporaryDirectory(prefix='signal_validation_') as root:
        input_dir = os.path.join(root, 'unpredictable_' + uuid.uuid4().hex)
        hook_dir = os.path.join(root, 'hooks')
        os.mkdir(input_dir)
        os.mkdir(hook_dir)

        # Values on both sides of 18.4 include near-threshold cases. Filenames
        # and the directory name carry no clean/evil label.
        peaks = [0.0, 5.0, 12.0, 16.5, 18.0, 18.8, 19.5, 22.0, 30.0, 45.0] * 2
        rng = np.random.default_rng()
        rng.shuffle(peaks)
        expected = set()

        for i, peak in enumerate(peaks):
            name = uuid.uuid4().hex + '.npy'
            bin_index = int(rng.integers(80, 850))
            np.save(os.path.join(input_dir, name), make_signal(peak, bin_index))
            if peak > 18.4:
                expected.add(name)

        write_trace_hook(hook_dir)
        trace_file = os.path.join(root, 'trace.log')
        log_file = os.path.join(root, 'rejected.log')
        env = os.environ.copy()
        env['PYTHONPATH'] = hook_dir + (os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
        env['FILTER_TRACE_FILE'] = trace_file
        env['FILTER_TRACE_PREFIX'] = input_dir + os.sep

        result = run_classifier(input_dir, log_file, 4, env)
        assert result.returncode == 0, f'Script failed on randomized mixed corpus.\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}'
        assert os.path.isfile(log_file), 'The rejected log was not created for a mixed corpus.'

        lines = read_log(log_file)
        assert len(lines) == len(set(lines)), 'The rejected log contains duplicate filenames.'
        assert set(lines) == expected, f'Randomized mixed-corpus classification was incorrect. Missing: {sorted(expected - set(lines))[:5]}; extra: {sorted(set(lines) - expected)[:5]}'

        trace = Path(trace_file).read_text().splitlines() if os.path.exists(trace_file) else []
        loads = [line.split() for line in trace if line.startswith('LOAD ')]
        fft_calls = [line for line in trace if line.startswith('FFT ')]
        nm_calls = [line for line in trace if line.startswith('NM ')]
        load_ranks = {parts[1] for parts in loads}
        loaded_names = {parts[2] for parts in loads if len(parts) >= 3}

        assert loaded_names == {p.name for p in Path(input_dir).glob('*.npy')}, 'Every input file must be loaded and processed.'
        assert len(load_ranks) >= 2, f'Files were not meaningfully distributed among MPI ranks; loading occurred on ranks {sorted(load_ranks)}.'
        assert len(fft_calls) >= len(peaks), 'An FFT was not executed for every signal.'
        assert len(nm_calls) >= len(peaks), 'Nelder-Mead optimization was not executed for every signal.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
