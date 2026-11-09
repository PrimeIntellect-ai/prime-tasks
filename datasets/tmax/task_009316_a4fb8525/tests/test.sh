#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shlex
import subprocess
from pathlib import Path

HOME = Path('/home/user')
TARGET = HOME / 'target.txt'
BEST = HOME / 'best_k.txt'


def simulate(k):
    v = 0.0
    values = [v]
    for _ in range(100):
        v += 0.1 * (9.8 - k * v * abs(v))
        values.append(v)
    return values


def render_target(base_k, noisy=False):
    values = simulate(base_k)
    if noisy:
        rng = secrets.SystemRandom()
        values = [v if i == 0 else v + rng.uniform(-0.015, 0.015)
                  for i, v in enumerate(values)]
    return ''.join(f'{i/10:.1f} {v:.6f}\n' for i, v in enumerate(values))


def expected_k(target_text):
    observed = [float(line.split()[1]) for line in target_text.splitlines()]
    scores = []
    for n in range(1, 51):
        k = n / 100.0
        predicted = simulate(k)
        mse = sum((a - b) ** 2 for a, b in zip(predicted, observed)) / len(observed)
        scores.append((mse, n))
    scores.sort()
    assert len(scores) == 50 and scores[0][0] < scores[1][0]
    return f'{scores[0][1] / 100:.2f}'


def shell_candidates():
    result = []
    for path in HOME.rglob('*'):
        if not path.is_file() or path in (TARGET, BEST):
            continue
        try:
            data = path.read_bytes()
        except OSError:
            continue
        if b'\0' in data:
            continue
        first = data.splitlines()[0] if data.splitlines() else b''
        if path.suffix == '.sh' or os.access(path, os.X_OK) or re.search(br'^#!.*\b(?:ba)?sh\b', first):
            result.append(path)
    return sorted(result)


def parallel_tokens(tokens):
    for i, token in enumerate(tokens):
        name = os.path.basename(token)
        if name == 'xargs':
            for j in range(i + 1, len(tokens)):
                arg = tokens[j]
                if arg in ('-P', '--max-procs') and j + 1 < len(tokens):
                    return tokens[j + 1] != '1'
                if arg.startswith('-P') and len(arg) > 2:
                    return arg[2:] != '1'
                if arg.startswith('--max-procs='):
                    return arg.split('=', 1)[1] != '1'
        if name == 'parallel':
            for j in range(i + 1, len(tokens)):
                arg = tokens[j]
                if arg in ('-j', '--jobs') and j + 1 < len(tokens):
                    return tokens[j + 1] != '1'
                if arg.startswith('-j') and len(arg) > 2:
                    return arg[2:] != '1'
                if arg.startswith('--jobs='):
                    return arg.split('=', 1)[1] != '1'
            return True
    return False


def source_parallel_evidence(paths):
    background = False
    waits = False
    for path in paths:
        try:
            text = path.read_text(errors='ignore')
        except OSError:
            continue
        for line in text.splitlines():
            try:
                tokens = shlex.split(line, comments=True, posix=True)
            except ValueError:
                tokens = []
            if parallel_tokens(tokens):
                return True
            uncommented = line.split('#', 1)[0]
            if re.search(r'(?<![&>])&(?![&>])', uncommented):
                background = True
            if re.search(r'(^|[;|&()\s])wait([;|&()\s]|$)', uncommented):
                waits = True
    return background and waits


def logged_parallel_evidence(log_path):
    if not log_path.exists():
        return False
    for line in log_path.read_text(errors='ignore').splitlines():
        fields = line.split('\t')
        if fields and parallel_tokens(fields):
            return True
    return False


def make_wrappers(directory, log_path):
    directory.mkdir()
    for command in ('xargs', 'parallel'):
        wrapper = directory / command
        wrapper.write_text(
            '#!/bin/bash\n'
            f"{{ printf '%s' '{command}'; printf '\\t%s' \"$@\"; printf '\\n'; }} >> {shlex.quote(str(log_path))}\n"
            f'exec /usr/bin/{command} "$@"\n'
        )
        wrapper.chmod(0o755)


def run_workflow(script, datasets, all_sources, tmp_path):
    log_path = tmp_path / ('parallel-' + str(abs(hash(str(script)))) + '.log')
    wrapper_dir = tmp_path / ('bin-' + str(abs(hash(str(script)))))
    make_wrappers(wrapper_dir, log_path)
    env = os.environ.copy()
    env['PATH'] = str(wrapper_dir) + os.pathsep + env.get('PATH', '')

    for target_text, expected in datasets:
        TARGET.write_text(target_text)
        try:
            BEST.unlink()
        except FileNotFoundError:
            pass
        proc = subprocess.run(
            ['timeout', '--kill-after=2', '35', 'bash', str(script)],
            cwd=str(HOME), env=env, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True
        )
        if proc.returncode != 0 or not BEST.is_file():
            return False
        if BEST.read_text().strip() != expected:
            return False

    return logged_parallel_evidence(log_path) or source_parallel_evidence(all_sources)


def test_completed_parallel_bash_workflow(tmp_path):
    # Preserve the original verifier's assertions on the state left by the agent.
    assert BEST.is_file(), 'The file /home/user/best_k.txt is missing. The task requires writing the optimal k to this file.'
    content = BEST.read_text().strip()
    assert content == '0.15', f"Expected the best k to be '0.15', but found '{content}'."

    original_target = TARGET.read_bytes()
    candidates = shell_candidates()
    assert candidates, 'No Bash workflow script was found under /home/user.'

    original = render_target(0.15, noisy=False)
    datasets = [(original, expected_k(original))]
    choices = list(range(1, 51))
    choices.remove(15)
    for _ in range(2):
        base = secrets.choice(choices) / 100.0
        text = render_target(base, noisy=True)
        datasets.append((text, expected_k(text)))

    try:
        for script in candidates:
            if run_workflow(script, datasets, candidates, tmp_path):
                return
        raise AssertionError(
            'No Bash workflow could be rerun successfully on derived target data while using parallel evaluation.'
        )
    finally:
        TARGET.write_bytes(original_target)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
