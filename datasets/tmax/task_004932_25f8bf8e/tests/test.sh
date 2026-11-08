#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import re
import math
import secrets

PROJECT = '/home/user/project'


def test_bad_commit_identified():
    bad_commit_file = '/home/user/bad_commit.txt'
    assert os.path.isfile(bad_commit_file), f"Expected {bad_commit_file} to exist."

    with open(bad_commit_file, 'r') as f:
        student_hash = f.read().strip()

    try:
        expected_hash = subprocess.check_output(
            ['git', 'log', '--grep=Optimize solver with pthreads', '--format=%H'],
            cwd=PROJECT, text=True
        ).strip()
    except subprocess.CalledProcessError:
        assert False, "Failed to run git log to find the bad commit."

    assert expected_hash, "Could not find the bad commit in the git history."
    assert student_hash == expected_hash, f"Incorrect bad commit hash. Expected {expected_hash}, got {student_hash}"


def test_pipeline_output_correct():
    output_file = '/home/user/pipeline_output.txt'
    assert os.path.isfile(output_file), f"Expected {output_file} to exist."

    with open(output_file, 'r') as f:
        content = f.read()

    assert "Failed to converge" not in content, "Pipeline output still shows convergence failures."

    def calc_sum(filepath):
        total = 0.0
        with open(filepath, 'r') as f:
            for line in f:
                val = float(line.strip())
                x = val
                for _ in range(10000):
                    delta = (x * x - val) / (2 * x)
                    if abs(delta) < 1e-5:
                        break
                    x -= delta
                total += x
        return total

    dataset1_sum = calc_sum('/home/user/project/data/dataset 1.txt')
    dataset2_sum = calc_sum('/home/user/project/data/dataset 2.txt')

    expected_1 = f"File: data/dataset 1.txt | Sum of roots: {dataset1_sum:.4f}"
    expected_2 = f"File: data/dataset 2.txt | Sum of roots: {dataset2_sum:.4f}"

    assert expected_1 in content, f"Output missing or incorrect for dataset 1. Expected: '{expected_1}'"
    assert expected_2 in content, f"Output missing or incorrect for dataset 2. Expected: '{expected_2}'"


def test_solver_c_fixed():
    solver_path = '/home/user/project/solver.c'
    assert os.path.isfile(solver_path), f"Expected {solver_path} to exist."

    with open(solver_path, 'r') as f:
        content = f.read()

    assert "pthread_create" in content, "solver.c must remain multithreaded (do not revert to single-threaded)."

    worker_idx = content.find('void* worker')
    if worker_idx != -1:
        global_area = content[:worker_idx]
        assert "double delta;" not in global_area, "The race condition is not fixed: 'delta' is still a global variable."

    assert re.search(r'double\s+delta\s*=', content[worker_idx:]) or re.search(r'double\s+delta\s*;\s*delta\s*=', content[worker_idx:]), "delta must be declared locally inside the worker thread."


def test_run_pipeline_sh_fixed():
    script_path = '/home/user/project/run_pipeline.sh'
    assert os.path.isfile(script_path), f"Expected {script_path} to exist."

    with open(script_path, 'r') as f:
        content = f.read()

    assert "$(ls" not in content, "run_pipeline.sh still uses $(ls ...), which breaks on spaces."
    assert "dataset 1.txt" not in content, "run_pipeline.sh should iterate over files, not hardcode them."

    valid_patterns = [r'for\s+\w+\s+in\s+data/\*', r'find\s+data', r'ls\s+data/\*\s*\|\s*while']
    has_valid_loop = any(re.search(p, content) for p in valid_patterns)
    assert has_valid_loop or '"$@"' in content or 'data/' in content, "run_pipeline.sh does not seem to iterate over data/ directory correctly."


def newton_sum(values):
    total = 0.0
    for val in values:
        x = val
        for _ in range(10000):
            delta = (x * x - val) / (2 * x)
            if abs(delta) < 1e-5:
                break
            x -= delta
        else:
            raise AssertionError(f"Verifier input unexpectedly failed to converge: {val}")
        total += x
    return total


def test_recompiled_solver_and_pipeline_on_fresh_inputs():
    token = secrets.token_hex(8)
    solver = os.path.join(PROJECT, 'solver')
    real_solver = os.path.join(PROJECT, f'.verifier_solver_{token}')
    call_log = f'/tmp/solver_calls_{token}'
    created = []

    # Inputs are generated at verification time, so prewritten output cannot pass.
    datasets = []
    for file_index in range(3):
        relpath = f'data/verifier sample {token} {file_index}.txt'
        abspath = os.path.join(PROJECT, relpath)
        values = []
        for i in range(800):
            base = 1.125 + ((i * 7919 + file_index * 104729) % 900000) / 137.0
            scale = (1.0, 17.0, 1009.0, 0.03125)[i % 4]
            values.append(base * scale + (file_index + 1) * 0.000137)
        with open(abspath, 'w') as f:
            f.write(''.join(f'{v:.12f}\n' for v in values))
        created.append(abspath)
        datasets.append((relpath, values))

    try:
        compile_result = subprocess.run(
            ['gcc', '-O2', '-pthread', 'solver.c', '-o', 'solver', '-lm'],
            cwd=PROJECT, text=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=30
        )
        assert compile_result.returncode == 0, f"solver.c failed to compile:\n{compile_result.stderr}"
        assert os.path.isfile(solver) and os.access(solver, os.X_OK), "Compilation did not produce an executable solver."

        expected = {}
        for relpath, values in datasets:
            expected[relpath] = f"File: {relpath} | Sum of roots: {newton_sum(values):.4f}"
            result = subprocess.run(
                ['./solver', relpath], cwd=PROJECT, text=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
            )
            assert result.returncode == 0, f"Recompiled solver failed on {relpath}: {result.stderr}"
            assert "Failed to converge" not in result.stdout, f"Solver failed to converge on fresh input {relpath}."
            assert expected[relpath] in result.stdout.splitlines(), f"Solver produced an incorrect result for {relpath}."

        # Wrap the just-compiled executable so the pipeline test also proves that
        # run_pipeline.sh invokes the submitted solver for every generated file.
        os.replace(solver, real_solver)
        with open(solver, 'w') as f:
            f.write('#!/bin/bash\n')
            f.write(f'printf "%s\\n" "$1" >> "{call_log}"\n')
            f.write(f'exec "{real_solver}" "$@"\n')
        os.chmod(solver, 0o755)

        last_output = ''
        repetitions = 6
        for _ in range(repetitions):
            result = subprocess.run(
                ['./run_pipeline.sh'], cwd=PROJECT, text=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=40
            )
            assert result.returncode == 0, f"run_pipeline.sh failed: {result.stderr}"
            assert "Failed to converge" not in result.stdout, "Pipeline still shows convergence failures."
            lines = result.stdout.splitlines()
            for relpath, _ in datasets:
                assert expected[relpath] in lines, f"Pipeline output missing or incorrect for fresh file with spaces: {relpath}"
            last_output = result.stdout

        assert os.path.isfile(call_log), "run_pipeline.sh did not invoke the compiled solver."
        with open(call_log, 'r') as f:
            calls = f.read().splitlines()
        for relpath, _ in datasets:
            assert calls.count(relpath) >= repetitions, f"run_pipeline.sh did not pass the complete spaced filename to solver: {relpath}"

        with open('/home/user/pipeline_output.txt', 'w') as f:
            f.write(last_output)
    finally:
        if os.path.exists(real_solver):
            if os.path.exists(solver):
                os.remove(solver)
            os.replace(real_solver, solver)
        for path in created:
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        try:
            os.remove(call_log)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
