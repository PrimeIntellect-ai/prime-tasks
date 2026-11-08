#!/bin/bash
set +e
mkdir -p /logs/verifier

FEATURES_BACKUP=$(mktemp)
if [ -e /home/user/features.txt ]; then
    cp /home/user/features.txt "$FEATURES_BACKUP"
    HAD_FEATURES=1
else
    HAD_FEATURES=0
fi
restore_features() {
    if [ "$HAD_FEATURES" = 1 ]; then
        cp "$FEATURES_BACKUP" /home/user/features.txt
    else
        rm -f /home/user/features.txt
    fi
    rm -f "$FEATURES_BACKUP"
}
trap restore_features EXIT

cat <<'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess
from pathlib import Path

HOME = Path('/home/user')
FEATURES = HOME / 'features.txt'
OUTPUT = HOME / 'density_output.txt'
PLOT = HOME / 'density_plot.png'


def run(cmd, timeout=30):
    return subprocess.run(
        cmd,
        cwd=str(HOME),
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def write_features(values):
    FEATURES.write_text(''.join(f'{v:.12f}\n' for v in values))


def expected_lines(values):
    result = []
    h = 0.5
    scale = len(values) * h * math.sqrt(2.0 * math.pi)
    for i in range(101):
        x = -5.0 + i * 0.1
        density = sum(math.exp(-((x - value) ** 2) / (2.0 * h * h)) for value in values) / scale
        result.append(f'{x:.1f},{density:.5f}')
    return result


def assert_correct_output(values):
    assert OUTPUT.is_file(), f'{OUTPUT} was not created.'
    lines = OUTPUT.read_text().splitlines()
    assert len(lines) == 101, f'Expected 101 output lines, got {len(lines)}.'
    pattern = re.compile(r'^-?\d+\.\d,-?\d+\.\d{5}$')
    assert all(pattern.fullmatch(line) for line in lines), 'Output does not consistently use %.1f,%.5f formatting.'
    expected = expected_lines(values)
    assert lines == expected, 'KDE output does not match the Gaussian KDE for the supplied features.'


def test_required_files_exist():
    assert (HOME / 'kde.c').is_file(), '/home/user/kde.c does not exist.'
    assert (HOME / 'plot_kde.py').is_file(), '/home/user/plot_kde.py does not exist.'
    assert (HOME / 'test_kde.sh').is_file(), '/home/user/test_kde.sh does not exist.'
    assert os.access(HOME / 'test_kde.sh', os.X_OK), '/home/user/test_kde.sh is not executable.'


def test_regression_script_and_canonical_output():
    canonical = [-1.0, 0.0, 1.0]
    write_features(canonical)
    OUTPUT.unlink(missing_ok=True)

    result = run(['bash', '/home/user/test_kde.sh'])
    assert result.returncode == 0, (
        f'/home/user/test_kde.sh failed with exit code {result.returncode}. '
        f'Stderr: {result.stderr}'
    )
    kde_bin = HOME / 'kde_bin'
    assert kde_bin.is_file(), 'test_kde.sh did not create /home/user/kde_bin.'
    assert os.access(kde_bin, os.X_OK), '/home/user/kde_bin is not executable.'

    assert_correct_output(canonical)
    content = OUTPUT.read_text()
    expected_line = '0.0,0.33795'
    assert expected_line in content, f"Expected line '{expected_line}' not found in {OUTPUT}."

    # A real regression check must fail when the required fixed value is absent.
    write_features([20.0, 21.0, 22.0])
    OUTPUT.unlink(missing_ok=True)
    bad_result = run(['bash', '/home/user/test_kde.sh'])
    assert bad_result.returncode == 1, (
        'test_kde.sh must exit 1 when density_output.txt does not contain '
        'the required 0.0,0.33795 line.'
    )


def test_compiled_c_program_on_unseen_inputs():
    verified_bin = Path('/tmp/kde_verified_bin')
    verified_bin.unlink(missing_ok=True)
    compile_result = run([
        'gcc', '/home/user/kde.c', '-o', str(verified_bin), '-lm'
    ])
    assert compile_result.returncode == 0, f'kde.c failed to compile: {compile_result.stderr}'
    assert verified_bin.is_file() and os.access(verified_bin, os.X_OK)

    rng = secrets.SystemRandom()
    datasets = [
        [rng.uniform(-4.5, 4.5) for _ in range(rng.randint(4, 9))],
        [rng.uniform(-2.0, 2.0) for _ in range(rng.randint(10, 17))],
        [rng.uniform(-8.0, 8.0) for _ in range(rng.randint(2, 7))],
    ]
    for values in datasets:
        # Match the exact decimal values placed in features.txt.
        values = [float(f'{v:.12f}') for v in values]
        write_features(values)
        OUTPUT.unlink(missing_ok=True)
        result = run([str(verified_bin)])
        assert result.returncode == 0, f'Compiled KDE program failed: {result.stderr}'
        assert_correct_output(values)


def test_plot_script_generates_data_dependent_valid_png():
    import matplotlib.image as mpimg

    def render(lines):
        OUTPUT.write_text('\n'.join(lines) + '\n')
        PLOT.unlink(missing_ok=True)
        result = run(['python3', '/home/user/plot_kde.py'], timeout=45)
        assert result.returncode == 0, f'plot_kde.py failed: {result.stderr}'
        assert PLOT.is_file(), f'{PLOT} does not exist.'
        assert PLOT.stat().st_size > 0, f'{PLOT} is empty (size 0).'
        assert PLOT.read_bytes().startswith(b'\x89PNG\r\n\x1a\n'), 'density_plot.png is not a PNG file.'
        image = mpimg.imread(PLOT)
        assert image.size > 0 and image.ndim in (2, 3), 'density_plot.png is not a decodable image.'
        return PLOT.read_bytes()

    xs = [-5.0 + i * 0.1 for i in range(101)]
    flat = [f'{x:.1f},0.10000' for x in xs]
    curved = [f'{x:.1f},{math.exp(-(x * x)):.5f}' for x in xs]
    first_png = render(flat)
    second_png = render(curved)
    assert first_png != second_png, 'plot_kde.py output does not depend on density_output.txt.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
