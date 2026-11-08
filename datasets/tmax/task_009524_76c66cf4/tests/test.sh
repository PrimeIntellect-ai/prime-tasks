#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path

import pytest

WORKSPACE = Path('/home/user/workspace')
RESULTS_FILE = Path('/home/user/results.csv')
DATA_DIR = Path('/home/user/data')
EXECUTABLE = WORKSPACE / 'fit_models'


def run_pipeline(env=None):
    if RESULTS_FILE.exists():
        RESULTS_FILE.unlink()
    result = subprocess.run(
        ['bash', str(WORKSPACE / 'run_pipeline.sh')],
        cwd=WORKSPACE,
        capture_output=True,
        text=True,
        env=env,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"run_pipeline.sh failed with return code {result.returncode}.\n"
        f"Stderr: {result.stderr}\nStdout: {result.stdout}"
    )


def read_results():
    assert RESULTS_FILE.is_file(), f"{RESULTS_FILE} was not created by the pipeline."
    with RESULTS_FILE.open('r') as f:
        return [line.strip() for line in f if line.strip()]


def expected_line(dataset_name, values):
    n = len(values)
    mean = math.fsum(values) / n
    variance = math.fsum((x - mean) ** 2 for x in values) / n

    ordered = sorted(values)
    median = (ordered[4999] + ordered[5000]) / 2.0
    b = math.fsum(abs(x - median) for x in values) / n

    ll_norm = -(n / 2.0) * math.log(2.0 * math.pi * variance) - n / 2.0
    ll_lap = -n * math.log(2.0 * b) - n
    model = 'Normal' if ll_norm > ll_lap else 'Laplace'
    return f"{dataset_name},{model},{abs(ll_norm - ll_lap):.4f}"


def write_doubles(path, values):
    with open(path, 'wb') as f:
        f.write(struct.pack('<10000d', *values))


def make_challenges():
    seed = int.from_bytes(os.urandom(16), 'little')
    rng = random.Random(seed)

    normal = [rng.gauss(11.25, 3.7) for _ in range(10000)]

    laplace = []
    for _ in range(10000):
        u = rng.random() - 0.5
        laplace.append(-7.4 - 2.2 * math.copysign(math.log1p(-2.0 * abs(u)), u))

    return normal, laplace


def assert_single_program_output(path, values):
    expected = expected_line(path.stem, values)
    result = subprocess.run(
        [str(EXECUTABLE), str(path)],
        cwd=WORKSPACE,
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"fit_models failed for {path}: return code {result.returncode}\n"
        f"stderr: {result.stderr}\nstdout: {result.stdout}"
    )
    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    assert lines == [expected], f"Expected {expected!r}, got {lines!r}"
    assert re.fullmatch(r'[^,]+,(Normal|Laplace),[0-9]+\.[0-9]{4}', lines[0]), lines[0]


def test_01_workspace_and_files_exist():
    assert WORKSPACE.is_dir(), f"Workspace directory {WORKSPACE} is missing."
    assert (WORKSPACE / 'fit_models.c').is_file(), "fit_models.c is missing in workspace."
    assert (WORKSPACE / 'Makefile').is_file(), "Makefile is missing in workspace."
    assert (WORKSPACE / 'run_pipeline.sh').is_file(), "run_pipeline.sh is missing in workspace."


def test_02_run_pipeline():
    run_pipeline()


def test_03_results_csv_content():
    lines = read_results()
    assert len(lines) == 2, f"Expected exactly 2 lines of output in {RESULTS_FILE}, got {len(lines)}."

    parts1 = lines[0].split(',')
    assert len(parts1) == 3, f"Line 1 invalid format. Expected 3 comma-separated values, got: {lines[0]}"
    assert parts1[0] == 'dataset_1', f"Line 1 expected dataset_name 'dataset_1', got '{parts1[0]}'"
    assert parts1[1] == 'Normal', f"Line 1 expected Best_Model 'Normal', got '{parts1[1]}'"
    try:
        diff1 = float(parts1[2])
        assert abs(diff1 - 268.0435) <= 0.0002, f"Line 1 Log_Likelihood_Difference expected ~268.0435, got {diff1}"
    except ValueError:
        pytest.fail(f"Line 1 Log_Likelihood_Difference is not a valid float: {parts1[2]}")

    parts2 = lines[1].split(',')
    assert len(parts2) == 3, f"Line 2 invalid format. Expected 3 comma-separated values, got: {lines[1]}"
    assert parts2[0] == 'dataset_2', f"Line 2 expected dataset_name 'dataset_2', got '{parts2[0]}'"
    assert parts2[1] == 'Laplace', f"Line 2 expected Best_Model 'Laplace', got '{parts2[1]}'"
    try:
        diff2 = float(parts2[2])
        assert abs(diff2 - 492.2030) <= 0.0002, f"Line 2 Log_Likelihood_Difference expected ~492.2030, got {diff2}"
    except ValueError:
        pytest.fail(f"Line 2 Log_Likelihood_Difference is not a valid float: {parts2[2]}")

    assert re.fullmatch(r'[0-9]+\.[0-9]{4}', parts1[2]), "Dataset 1 difference is not formatted to 4 decimals."
    assert re.fullmatch(r'[0-9]+\.[0-9]{4}', parts2[2]), "Dataset 2 difference is not formatted to 4 decimals."


def test_04_makefile_really_compiles_fit_models_source():
    source = WORKSPACE / 'fit_models.c'
    original = source.read_bytes()
    try:
        source.write_bytes(original + b'\n#error verifier_requires_Makefile_to_compile_fit_models_c\n')
        bad = subprocess.run(
            ['make', '-B'], cwd=WORKSPACE, capture_output=True, text=True, timeout=30
        )
        assert bad.returncode != 0, (
            "make succeeded even though fit_models.c was made invalid; "
            "the Makefile does not compile the required source file."
        )
    finally:
        source.write_bytes(original)

    if EXECUTABLE.exists() or EXECUTABLE.is_symlink():
        EXECUTABLE.unlink()
    good = subprocess.run(
        ['make', '-B'], cwd=WORKSPACE, capture_output=True, text=True, timeout=30
    )
    assert good.returncode == 0, f"Makefile failed to compile fit_models.c:\n{good.stderr}\n{good.stdout}"
    assert EXECUTABLE.is_file(), "Makefile did not create the fit_models executable."
    assert os.access(EXECUTABLE, os.X_OK), "The generated fit_models file is not executable."


def test_05_compiled_program_and_pipeline_use_dataset_contents():
    normal, laplace = make_challenges()

    with tempfile.TemporaryDirectory(prefix='fit_models_verify_') as td:
        temp = Path(td)
        direct_normal = temp / ('hidden_normal_' + os.urandom(6).hex() + '.bin')
        direct_laplace = temp / ('hidden_laplace_' + os.urandom(6).hex() + '.bin')
        write_doubles(direct_normal, normal)
        write_doubles(direct_laplace, laplace)

        assert_single_program_output(direct_normal, normal)
        assert_single_program_output(direct_laplace, laplace)

        data1 = DATA_DIR / 'dataset_1.bin'
        data2 = DATA_DIR / 'dataset_2.bin'
        backup1 = data1.read_bytes()
        backup2 = data2.read_bytes()

        real_executable = temp / 'real_fit_models'
        shutil.copy2(EXECUTABLE, real_executable)
        call_log = temp / 'fit_calls.log'
        bin_dir = temp / 'bin'
        bin_dir.mkdir()

        fit_wrapper = f'''#!/bin/bash
printf '%s\\n' "$1" >> {str(call_log)!r}
exec {str(real_executable)!r} "$@"
'''

        make_wrapper = bin_dir / 'make'
        make_wrapper.write_text(f'''#!/bin/bash
set +e
if grep -q VERIFIER_FIT_WRAPPER {str(EXECUTABLE)!r} 2>/dev/null; then
    cp {str(real_executable)!r} {str(EXECUTABLE)!r}
    chmod +x {str(EXECUTABLE)!r}
fi
/usr/bin/make "$@"
status=$?
if [ "$status" -eq 0 ] && [ -x {str(EXECUTABLE)!r} ]; then
    cp {str(EXECUTABLE)!r} {str(real_executable)!r}
    cat > {str(EXECUTABLE)!r} <<'WRAP_EOF'
#!/bin/bash
# VERIFIER_FIT_WRAPPER
printf '%s\\n' "$1" >> {str(call_log)!r}
exec {str(real_executable)!r} "$@"
WRAP_EOF
    chmod +x {str(EXECUTABLE)!r}
fi
exit "$status"
''')
        make_wrapper.chmod(0o755)

        try:
            write_doubles(data1, normal)
            write_doubles(data2, laplace)

            env = os.environ.copy()
            env['PATH'] = str(bin_dir) + os.pathsep + env.get('PATH', '')
            run_pipeline(env=env)

            expected = [
                expected_line('dataset_1', normal),
                expected_line('dataset_2', laplace),
            ]
            assert read_results() == expected, (
                "Pipeline output did not change to match newly supplied dataset contents."
            )

            calls = call_log.read_text().splitlines() if call_log.exists() else []
            assert len(calls) == 2, f"run_pipeline.sh must invoke fit_models twice; observed calls: {calls!r}"
            assert Path(calls[0]).name == 'dataset_1.bin', f"First fit_models call was not dataset_1.bin: {calls!r}"
            assert Path(calls[1]).name == 'dataset_2.bin', f"Second fit_models call was not dataset_2.bin: {calls!r}"
        finally:
            data1.write_bytes(backup1)
            data2.write_bytes(backup2)
            if real_executable.is_file():
                shutil.copy2(real_executable, EXECUTABLE)

        run_pipeline()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
