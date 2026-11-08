#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import math
import os
import re
import secrets
import stat
import subprocess
import textwrap
from pathlib import Path

PROJECT = Path('/home/user/mcmc_project')
MCMC = PROJECT / 'mcmc_integration.py'
PROFILE = PROJECT / 'profile_runs.sh'
SAMPLES = PROJECT / 'integral_samples.txt'
CI = PROJECT / 'ci_output.txt'

ORIGINAL = '''import numpy as np
import sys

# Deterministic seed based on time/run to simulate stochastic runs but keep it simple
# We'll use a random seed so runs produce different outputs
np.random.seed()

def run_mcmc():
    dim = 5
    # Simulate a near-singular covariance matrix
    cov = np.ones((dim, dim)) * 0.99 + np.eye(dim) * 0.0001

    # This will fail randomly or consistently without jitter
    # We force it to fail if jitter isn't added by making it strictly singular
    cov[:, 4] = cov[:, 0]
    cov[4, :] = cov[0, :]

    # Agent needs to add jitter before this line
    L = np.linalg.cholesky(cov)

    # Simulate integration result
    result = np.random.normal(loc=15.5, scale=2.1)
    return result

if __name__ == "__main__":
    try:
        val = run_mcmc()
        print(f"{val:.6f}")
    except np.linalg.LinAlgError:
        print("LinAlgError", file=sys.stderr)
        sys.exit(1)
'''


def find_run_mcmc(tree):
    funcs = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'run_mcmc']
    assert len(funcs) == 1, 'mcmc_integration.py must retain run_mcmc().' 
    return funcs[0]


def is_cholesky_statement(stmt):
    if not isinstance(stmt, ast.Assign) or len(stmt.targets) != 1:
        return False
    call = stmt.value
    return (
        isinstance(call, ast.Call)
        and isinstance(call.func, ast.Attribute)
        and call.func.attr == 'cholesky'
        and isinstance(call.func.value, ast.Attribute)
        and call.func.value.attr == 'linalg'
        and isinstance(call.func.value.value, ast.Name)
        and call.func.value.value.id == 'np'
    )


def test_mcmc_source_has_only_immediate_jitter_change():
    assert MCMC.exists(), f'File {MCMC} is missing.'
    submitted = ast.parse(MCMC.read_text())
    expected = ast.parse(ORIGINAL)
    submitted_func = find_run_mcmc(submitted)

    chol_indices = [i for i, stmt in enumerate(submitted_func.body) if is_cholesky_statement(stmt)]
    assert chol_indices == [5], 'The original Cholesky operation and surrounding logic must be preserved.'
    chol_index = chol_indices[0]
    assert chol_index > 0, 'Jitter must be added immediately before Cholesky.'

    # The task permits exactly one added statement immediately before Cholesky.
    # Removing that statement must recover the complete original program AST,
    # which also verifies that the seed and all other logic were preserved.
    del submitted_func.body[chol_index - 1]
    assert ast.dump(submitted, include_attributes=False) == ast.dump(expected, include_attributes=False), (
        'Only a single jitter statement immediately before Cholesky may differ; '
        'the random seed and all other logic must remain unchanged.'
    )


def test_jitter_value_reaching_cholesky():
    import numpy as np

    captured = {}
    original_cholesky = np.linalg.cholesky
    original_normal = np.random.normal

    def fake_cholesky(matrix):
        captured['matrix'] = np.array(matrix, dtype=float, copy=True)
        return np.eye(matrix.shape[0])

    def fake_normal(*args, **kwargs):
        assert kwargs == {'loc': 15.5, 'scale': 2.1}, 'The integration-result logic was changed.'
        return 17.25

    try:
        np.linalg.cholesky = fake_cholesky
        np.random.normal = fake_normal
        spec = importlib.util.spec_from_file_location('submitted_mcmc', MCMC)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        assert module.run_mcmc() == 17.25
    finally:
        np.linalg.cholesky = original_cholesky
        np.random.normal = original_normal

    dim = 5
    expected = np.ones((dim, dim)) * 0.99 + np.eye(dim) * 0.0001
    expected[:, 4] = expected[:, 0]
    expected[4, :] = expected[0, :]
    expected = expected + np.eye(dim) * 1e-6
    np.testing.assert_allclose(
        captured.get('matrix'), expected, rtol=0, atol=1e-12,
        err_msg='Cholesky must receive the original covariance plus exactly 1e-6 on its diagonal.'
    )


def test_mcmc_integration_fixed():
    result = subprocess.run(['python3', str(MCMC)], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f'mcmc_integration.py failed to run. Stderr: {result.stderr}'
    output = result.stdout.strip()
    try:
        value = float(output)
    except ValueError:
        raise AssertionError(f'mcmc_integration.py did not output a valid float. Output: {result.stdout}')
    assert math.isfinite(value), 'mcmc_integration.py must output a finite float.'
    assert len(output.splitlines()) == 1, 'mcmc_integration.py must output one number.'


def test_profile_runs_script():
    assert PROFILE.exists(), f'File {PROFILE} is missing.'
    assert os.access(PROFILE, os.X_OK), f'File {PROFILE} is not executable.'

    source = PROFILE.read_text()
    assert not re.search(r'(^|[;&|]\s*)(?:/\S*/)?(?:python(?:3)?|pypy\d*)\s+-c\b', source, re.M | re.I), \
        'Python may not be used to calculate the bootstrap interval.'
    assert not re.search(r'(^|[;&|]\s*)(?:/\S*/)?(?:R|Rscript)\b', source, re.M), \
        'R may not be used to calculate the bootstrap interval.'

    work = Path('/tmp/profile_verifier_' + secrets.token_hex(8))
    wrappers = work / 'bin'
    captures = work / 'sort_captures'
    work.mkdir()
    wrappers.mkdir()
    captures.mkdir()
    counter = work / 'count'
    values_file = work / 'values'
    counter.write_text('0\n')

    # Hidden, varying integer-valued outputs make fabricated sample and CI files
    # fail while allowing exact validation of all 30 program invocations.
    values = [secrets.randbelow(900) + 100 for _ in range(30)]
    values_file.write_text('\n'.join(map(str, values)) + '\n')

    python_wrapper = wrappers / 'python3'
    python_wrapper.write_text(textwrap.dedent(f'''\
        #!/bin/bash
        target=""
        for arg in "$@"; do
            case "$arg" in
                *mcmc_integration.py) target="$arg" ;;
            esac
        done
        if [ -z "$target" ]; then
            echo "Python is not allowed for bootstrap calculation" >&2
            exit 91
        fi
        exec /usr/bin/python3 "$@"
    '''))
    python_wrapper.chmod(0o755)
    for name in ('python', 'pypy', 'pypy3', 'R', 'Rscript'):
        p = wrappers / name
        p.write_text('#!/bin/bash\necho "Disallowed bootstrap interpreter" >&2\nexit 92\n')
        p.chmod(0o755)

    sort_wrapper = wrappers / 'sort'
    sort_wrapper.write_text(textwrap.dedent(f'''\
        #!/usr/bin/python3
        import os, subprocess, sys
        capture_dir = {str(captures)!r}
        args = sys.argv[1:]
        saved_stdin = None
        if not sys.stdin.isatty():
            saved_stdin = sys.stdin.buffer.read()
            if saved_stdin:
                with open(os.path.join(capture_dir, 'stdin_' + str(os.getpid())), 'wb') as f:
                    f.write(saved_stdin)
        for i, arg in enumerate(args):
            if os.path.isfile(arg):
                try:
                    data = open(arg, 'rb').read()
                    with open(os.path.join(capture_dir, 'file_' + str(os.getpid()) + '_' + str(i)), 'wb') as f:
                        f.write(data)
                except OSError:
                    pass
        proc = subprocess.run(['/usr/bin/sort'] + args, input=saved_stdin)
        sys.exit(proc.returncode)
    '''))
    sort_wrapper.chmod(0o755)

    original_bytes = MCMC.read_bytes()
    original_mode = stat.S_IMODE(MCMC.stat().st_mode)
    stub = textwrap.dedent(f'''\
        #!/usr/bin/python3
        from pathlib import Path
        counter = Path({str(counter)!r})
        values = Path({str(values_file)!r}).read_text().splitlines()
        n = int(counter.read_text())
        if n >= len(values):
            raise SystemExit('mcmc_integration.py was invoked more than 30 times')
        counter.write_text(str(n + 1) + '\\n')
        print(values[n] + '.000000')
    ''')

    env = os.environ.copy()
    env['PATH'] = str(wrappers) + ':' + env.get('PATH', '')

    try:
        MCMC.write_text(stub)
        MCMC.chmod(0o755)
        result = subprocess.run(
            ['/bin/bash', str(PROFILE)], cwd=str(PROJECT), env=env,
            capture_output=True, text=True, timeout=300
        )
    finally:
        MCMC.write_bytes(original_bytes)
        MCMC.chmod(original_mode)

    assert result.returncode == 0, (
        f'profile_runs.sh failed when exercised.\nstdout: {result.stdout}\nstderr: {result.stderr}'
    )
    assert int(counter.read_text().strip()) == 30, 'profile_runs.sh must run mcmc_integration.py exactly 30 times.'

    assert SAMPLES.exists(), f'File {SAMPLES} is missing after running profile_runs.sh.'
    sample_lines = SAMPLES.read_text().strip().splitlines()
    assert len(sample_lines) == 30, f'Expected 30 lines in {SAMPLES}, found {len(sample_lines)}.'
    parsed_samples = []
    for i, line in enumerate(sample_lines):
        try:
            parsed_samples.append(float(line.strip()))
        except ValueError:
            raise AssertionError(f"Line {i + 1} in {SAMPLES} is not a valid float: '{line}'")
    assert parsed_samples == [float(v) for v in values], \
        'integral_samples.txt must contain, in order, the outputs of the 30 actual runs.'

    candidates = []
    for path in captures.iterdir():
        try:
            lines = path.read_text().strip().splitlines()
            nums = [float(x.strip()) for x in lines]
        except (UnicodeDecodeError, ValueError):
            continue
        if len(nums) == 1000 and all(math.isfinite(x) for x in nums):
            candidates.append(nums)
    assert candidates, 'The script must generate and sort exactly 1,000 bootstrap means using Unix tools.'

    lo_sample, hi_sample = min(values), max(values)
    valid = []
    for means in candidates:
        if all(lo_sample - 1e-8 <= x <= hi_sample + 1e-8 for x in means):
            # For integer samples, every 30-draw resample mean multiplied by 30
            # is an integer (allowing ordinary awk/bc output rounding).
            if all(abs(x * 30 - round(x * 30)) < 0.01 for x in means):
                if len({round(x, 6) for x in means}) >= 20:
                    valid.append(means)
    assert valid, 'Captured values are not 1,000 means of 30-sample resamples with replacement.'

    assert CI.exists(), f'File {CI} is missing after running profile_runs.sh.'
    content = CI.read_text().strip()
    match = re.fullmatch(r'95% CI: \[(-?\d+\.\d{4}), (-?\d+\.\d{4})\]', content)
    assert match, (
        f"ci_output.txt content '{content}' does not match the required four-decimal format."
    )

    actual_lower, actual_upper = match.groups()
    matched_interval = False
    for means in valid:
        ordered = sorted(means)
        expected_lower = f'{ordered[24]:.4f}'
        expected_upper = f'{ordered[974]:.4f}'
        if (actual_lower, actual_upper) == (expected_lower, expected_upper):
            matched_interval = True
            break
    assert matched_interval, (
        'ci_output.txt must use the 25th and 975th values of the sorted 1,000 bootstrap means.'
    )


def test_final_output_shapes():
    assert SAMPLES.exists(), f'File {SAMPLES} is missing.'
    lines = SAMPLES.read_text().strip().split('\n')
    assert len(lines) == 30, f'Expected 30 lines in {SAMPLES}, found {len(lines)}.'
    for i, line in enumerate(lines):
        try:
            float(line.strip())
        except ValueError:
            raise AssertionError(f"Line {i + 1} in {SAMPLES} is not a valid float: '{line}'")

    assert CI.exists(), f'File {CI} is missing.'
    content = CI.read_text().strip()
    pattern = r'^95% CI: \[-?\d+\.\d{4}, -?\d+\.\d{4}\]$'
    assert re.match(pattern, content), (
        f"ci_output.txt content '{content}' does not match expected format "
        "'95% CI: [lower_bound, upper_bound]' with 4 decimal places."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
