#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import stat
import subprocess
import tempfile
from decimal import Decimal
from pathlib import Path

import pytest

BASE = Path('/home/user/profiling')
DUMPS = BASE / 'dumps'
OPTIM = BASE / 'run_optim.sh'
UNSTABLE = BASE / 'unstable.log'
RESULTS = BASE / 'optim_results.log'


def test_unstable_log():
    log_path = '/home/user/profiling/unstable.log'
    assert os.path.isfile(log_path), f'File {log_path} does not exist. Did you create it?'

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = ['mat_2.txt', 'mat_3.txt', 'mat_5.txt']

    assert lines == expected, (
        f'Contents of {log_path} do not match expected sorted list of unstable matrices. '
        f'Expected {expected}, but got {lines}.'
    )


def test_optim_results_log():
    log_path = '/home/user/profiling/optim_results.log'
    assert os.path.isfile(log_path), f'File {log_path} does not exist. Did you run the optimization script?'

    with open(log_path, 'r') as f:
        lines = sorted([line.strip() for line in f if line.strip()])

    expected = [
        'Successfully optimized: mat_1.txt',
        'Successfully optimized: mat_4.txt',
        'Successfully optimized: mat_6.txt'
    ]

    assert lines == expected, (
        f'Contents of {log_path} do not match expected stable matrices. '
        f'Expected {expected}, but got {lines}.'
    )


def shell_candidates():
    excluded = {
        str(OPTIM.resolve()),
        str((Path('/home/user') / '.bashrc').resolve()),
        str((Path('/home/user') / '.profile').resolve()),
        str((Path('/home/user') / '.bash_logout').resolve()),
    }
    found = []
    for path in Path('/home/user').rglob('*'):
        if not path.is_file():
            continue
        try:
            resolved = str(path.resolve())
        except OSError:
            continue
        if resolved in excluded or DUMPS in path.parents or path in (UNSTABLE, RESULTS):
            continue
        try:
            head = path.read_bytes()[:4096]
        except OSError:
            continue
        first = head.splitlines()[0] if head.splitlines() else b''
        if path.suffix in ('.sh', '.bash') or re.match(br'^#!.*\b(?:ba)?sh\b', first):
            found.append(path)
    return sorted(set(found), key=lambda p: str(p))


def read_nonempty(path):
    if not path.is_file():
        return None
    return [line.strip() for line in path.read_text(errors='replace').splitlines() if line.strip()]


def test_solution_script_on_fresh_matrices():
    candidates = shell_candidates()
    assert candidates, 'No Bash solution script was found under /home/user.'

    # A Bash wrapper may use normal CLI tools, but must not delegate the task to
    # one of the explicitly prohibited scripting languages.
    usable = []
    banned = re.compile(r'(?im)(?:^|[;&|()\s])(?:/[^\s;&|()]*/)?(?:python(?:[0-9.]*)?|perl|ruby)(?:\s|$)')
    for candidate in candidates:
        try:
            text = candidate.read_text(errors='replace')
        except OSError:
            continue
        if not banned.search(text):
            usable.append(candidate)
    assert usable, 'No purely Bash-based solution script was found.'

    backup = Path(tempfile.mkdtemp(prefix='matrix-verifier-backup-'))
    original_dumps = backup / 'dumps'
    shutil.copytree(DUMPS, original_dumps)
    original_optim = (OPTIM.read_bytes(), stat.S_IMODE(OPTIM.stat().st_mode))
    original_logs = {}
    for log in (UNSTABLE, RESULTS):
        original_logs[log] = (log.read_bytes(), stat.S_IMODE(log.stat().st_mode)) if log.exists() else None

    token = secrets.token_hex(12)
    calls = BASE / ('.verifier_calls_' + token)
    deltas = [
        Decimal('-0.008'), Decimal('0.006'), Decimal('0'), Decimal('0.0099'),
        Decimal('0.01'), Decimal('-0.01'), Decimal('0.25'), Decimal('-3.0')
    ]
    # Random names prevent a submission from passing by recognizing a fixed list.
    names = [f'm_{secrets.token_hex(7)}.txt' for _ in deltas]
    cases = []
    for i, (name, delta) in enumerate(zip(names, deltas)):
        a = Decimal([2, 4, 5, 8][i % 4])
        b = Decimal(secrets.randbelow(15) + 1)
        c = Decimal(secrets.randbelow(17) + 1)
        d = (b * c + delta) / a
        cases.append((name, a, b, c, d))

    expected_unstable = []
    expected_stable = []
    for name, a, b, c, d in cases:
        determinant = a * d - b * c
        if abs(determinant) < Decimal('0.01'):
            expected_unstable.append(name)
        else:
            expected_stable.append(name)
    expected_unstable.sort()
    expected_paths = sorted(str(DUMPS / name) for name in expected_stable)
    expected_results = sorted(f'VERIFY-{token}:{name}' for name in expected_stable)

    def install_fresh_case():
        BASE.mkdir(parents=True, exist_ok=True)
        if DUMPS.exists():
            shutil.rmtree(DUMPS)
        DUMPS.mkdir(parents=True)
        for name, a, b, c, d in cases:
            (DUMPS / name).write_text(f'{a} {b}\n{c} {d}\n')
        UNSTABLE.unlink(missing_ok=True)
        RESULTS.unlink(missing_ok=True)
        calls.write_text('')
        os.chmod(calls, 0o666)
        OPTIM.write_text(
            '#!/bin/bash\n'
            'if [ "$#" -ne 1 ]; then exit 41; fi\n'
            f'printf "%s\\n" "$1" >> {str(calls)!r}\n'
            f'printf "VERIFY-{token}:%s\\n" "$(basename "$1")"\n'
        )
        os.chmod(OPTIM, 0o755)

    failures = []
    passed = False
    try:
        for candidate in usable:
            install_fresh_case()
            try:
                proc = subprocess.run(
                    ['/bin/bash', str(candidate)],
                    cwd=str(BASE),
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=15,
                )
            except subprocess.TimeoutExpired:
                failures.append(f'{candidate}: timed out')
                continue

            unstable_lines = read_nonempty(UNSTABLE)
            result_lines = read_nonempty(RESULTS)
            call_lines = read_nonempty(calls)
            ok = (
                proc.returncode == 0
                and unstable_lines == expected_unstable
                and result_lines is not None
                and sorted(result_lines) == expected_results
                and call_lines is not None
                and sorted(call_lines) == expected_paths
            )
            if ok:
                passed = True
                break
            failures.append(
                f'{candidate}: exit={proc.returncode}, unstable={unstable_lines}, '
                f'results={result_lines}, optimizer_calls={call_lines}, stderr={proc.stderr[-300:]!r}'
            )
    finally:
        if DUMPS.exists():
            shutil.rmtree(DUMPS)
        shutil.copytree(original_dumps, DUMPS)
        OPTIM.write_bytes(original_optim[0])
        os.chmod(OPTIM, original_optim[1])
        for log, saved in original_logs.items():
            if saved is None:
                log.unlink(missing_ok=True)
            else:
                log.write_bytes(saved[0])
                os.chmod(log, saved[1])
        calls.unlink(missing_ok=True)
        shutil.rmtree(backup, ignore_errors=True)

    assert passed, 'No submitted Bash script correctly handled fresh matrices and invoked run_optim.sh. ' + ' | '.join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
