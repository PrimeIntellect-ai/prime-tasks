#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import secrets
import subprocess
from pathlib import Path

import numpy as np
import pytest
from skimage.metrics import structural_similarity as ssim
from PIL import Image
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt


def generate_reference_embeddings(eval_txt_path):
    with open(eval_txt_path, 'r') as f:
        lines = [line.strip('\n') for line in f]

    trigrams = set()
    for line in lines:
        for i in range(len(line) - 2):
            trigrams.add(line[i:i+3])

    vocab = sorted(list(trigrams))
    vocab_size = len(vocab)
    vocab_idx = {tg: i for i, tg in enumerate(vocab)}

    N = len(lines)
    counts = np.zeros((N, vocab_size), dtype=np.float32)
    for i, line in enumerate(lines):
        for j in range(len(line) - 2):
            tg = line[j:j+3]
            counts[i, vocab_idx[tg]] += 1.0

    rng = np.random.RandomState(42)
    proj = rng.randn(vocab_size, 64).astype(np.float32)

    embeds = np.dot(counts, proj)
    return embeds


def run_python_script(path):
    env = os.environ.copy()
    env.pop('DISPLAY', None)
    env['MPLBACKEND'] = 'Agg'
    return subprocess.run(
        ['python3', path],
        cwd='/home/user',
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )


def test_00_reproduce_script_exists_and_recomputes_hidden_input():
    script_path = Path('/home/user/reproduce_embeds.py')
    eval_path = Path('/home/user/data/eval.txt')
    output_path = Path('/home/user/data/python_embeds.bin')

    assert script_path.is_file(), f'Agent did not create {script_path}'
    assert not script_path.is_symlink(), f'{script_path} must be a Python source file, not a symlink'

    source = script_path.read_text(encoding='utf-8')
    try:
        tree = ast.parse(source, filename=str(script_path))
    except SyntaxError as exc:
        pytest.fail(f'{script_path} is not valid Python: {exc}')

    assert 'legacy_embedder' not in source.lower(), 'reproduce_embeds.py must implement the pipeline rather than invoke the legacy binary'

    forbidden_modules = {'subprocess', 'commands', 'ctypes', 'pty'}
    forbidden_calls = {
        'system', 'popen', 'popen2', 'popen3', 'popen4',
        'spawnl', 'spawnle', 'spawnlp', 'spawnlpe', 'spawnv', 'spawnve',
        'spawnvp', 'spawnvpe', 'execv', 'execve', 'execvp', 'execvpe',
        '__import__', 'eval', 'exec',
    }
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                assert alias.name.split('.')[0] not in forbidden_modules, 'reproduce_embeds.py may not launch or load the legacy executable'
        elif isinstance(node, ast.ImportFrom) and node.module:
            assert node.module.split('.')[0] not in forbidden_modules, 'reproduce_embeds.py may not launch or load the legacy executable'
            for alias in node.names:
                assert alias.name not in forbidden_calls, 'reproduce_embeds.py may not launch external commands'
        elif isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name):
                assert node.func.id not in forbidden_calls, 'reproduce_embeds.py may not launch external commands'
            elif isinstance(node.func, ast.Attribute):
                assert node.func.attr not in forbidden_calls, 'reproduce_embeds.py may not launch external commands'

    original_eval = eval_path.read_bytes()
    original_output = output_path.read_bytes() if output_path.exists() else None

    nonce = secrets.token_hex(12)
    words = ['alpha', 'bravo', 'cider', 'delta', 'ember', 'forest', 'garden', 'harbor', nonce]
    rng = np.random.default_rng(int.from_bytes(secrets.token_bytes(8), 'little'))
    hidden_lines = []
    for i in range(37):
        chosen = rng.choice(words, size=int(rng.integers(4, 12)), replace=True)
        hidden_lines.append((' '.join(chosen) + f' #{i}!').capitalize())
    hidden_text = '\n'.join(hidden_lines) + '\n'

    try:
        eval_path.write_text(hidden_text, encoding='utf-8')
        output_path.unlink(missing_ok=True)

        result = run_python_script(str(script_path))
        assert result.returncode == 0, f'reproduce_embeds.py failed on verifier input:\n{result.stdout}\n{result.stderr}'
        assert output_path.is_file(), 'reproduce_embeds.py did not create python_embeds.bin when executed'

        expected = generate_reference_embeddings(str(eval_path)).reshape(-1)
        actual = np.fromfile(output_path, dtype=np.float32)
        assert actual.shape == expected.shape, 'reproduce_embeds.py produced the wrong embedding shape on verifier input'
        mse = np.mean((expected - actual) ** 2)
        assert np.isfinite(mse) and mse < 1e-5, f'reproduce_embeds.py failed verifier-derived input with MSE {mse}'
    finally:
        eval_path.write_bytes(original_eval)
        if original_output is None:
            output_path.unlink(missing_ok=True)
        else:
            output_path.write_bytes(original_output)

    output_path.unlink(missing_ok=True)
    result = run_python_script(str(script_path))
    assert result.returncode == 0, f'reproduce_embeds.py failed on eval.txt:\n{result.stdout}\n{result.stderr}'
    assert output_path.is_file(), 'reproduce_embeds.py did not recreate python_embeds.bin'


def test_01_plot_script_executes_headlessly_and_plots_residuals(tmp_path):
    script_path = Path('/home/user/plot_artifacts.py')
    legacy_path = Path('/home/user/data/legacy_embeds.bin')
    python_path = Path('/home/user/data/python_embeds.bin')
    plot_path = Path('/home/user/residual_plot.png')

    assert script_path.is_file(), f'Agent did not provide {script_path}'
    assert not script_path.is_symlink(), f'{script_path} must be a Python source file, not a symlink'
    try:
        ast.parse(script_path.read_text(encoding='utf-8'), filename=str(script_path))
    except SyntaxError as exc:
        pytest.fail(f'{script_path} is not valid Python: {exc}')

    saved_legacy = legacy_path.read_bytes() if legacy_path.exists() else None
    saved_python = python_path.read_bytes() if python_path.exists() else None
    saved_plot = plot_path.read_bytes() if plot_path.exists() else None

    rng = np.random.default_rng(int.from_bytes(secrets.token_bytes(8), 'little'))
    python_values = rng.normal(size=6400).astype(np.float32)
    residuals = (0.35 * np.sin(np.arange(6400, dtype=np.float32) / 31.0) +
                 rng.normal(scale=0.03, size=6400)).astype(np.float32)
    legacy_values = python_values + residuals

    try:
        legacy_values.tofile(legacy_path)
        python_values.tofile(python_path)
        plot_path.unlink(missing_ok=True)

        result = run_python_script(str(script_path))
        assert result.returncode == 0, f'plot_artifacts.py failed in a headless environment:\n{result.stdout}\n{result.stderr}'
        assert plot_path.is_file(), 'plot_artifacts.py did not create residual_plot.png when executed'

        reference_path = tmp_path / 'hidden_reference_plot.png'
        plt.figure()
        plt.scatter(range(len(residuals)), residuals, alpha=0.5)
        plt.title('Embedding Residuals')
        plt.xlabel('Dimension Index')
        plt.ylabel('Error')
        plt.savefig(reference_path)
        plt.close()

        img_agent = np.array(Image.open(plot_path).convert('L'))
        img_ref = np.array(Image.open(reference_path).convert('L'))
        if img_agent.shape != img_ref.shape:
            img_agent = np.array(Image.open(plot_path).convert('L').resize(img_ref.shape[::-1]))
        score, _ = ssim(img_ref, img_agent, full=True, data_range=255)
        assert score >= 0.95, f'Executed plot_artifacts.py produced an incorrect residual plot (SSIM {score:.4f})'
    finally:
        if saved_legacy is None:
            legacy_path.unlink(missing_ok=True)
        else:
            legacy_path.write_bytes(saved_legacy)
        if saved_python is None:
            python_path.unlink(missing_ok=True)
        else:
            python_path.write_bytes(saved_python)
        if saved_plot is None:
            plot_path.unlink(missing_ok=True)
        else:
            plot_path.write_bytes(saved_plot)


def test_python_embeds_mse():
    eval_txt_path = "/home/user/data/eval.txt"
    python_embeds_path = "/home/user/data/python_embeds.bin"

    assert os.path.exists(python_embeds_path), f"Agent did not create {python_embeds_path}"

    ref_embeds = generate_reference_embeddings(eval_txt_path)
    agent_embeds = np.fromfile(python_embeds_path, dtype=np.float32)

    assert agent_embeds.shape == ref_embeds.flatten().shape, "Agent embeddings shape mismatch"

    mse = np.mean((ref_embeds.flatten() - agent_embeds) ** 2)
    assert mse < 1e-5, f"MSE between python_embeds.bin and reference is {mse}, which is >= 1e-5 threshold."


def test_residual_plot_ssim(tmp_path):
    eval_txt_path = "/home/user/data/eval.txt"
    python_embeds_path = "/home/user/data/python_embeds.bin"
    agent_plot_path = "/home/user/residual_plot.png"

    assert os.path.exists(agent_plot_path), f"Agent did not create {agent_plot_path}"

    ref_embeds = generate_reference_embeddings(eval_txt_path)

    if os.path.exists(python_embeds_path):
        agent_embeds = np.fromfile(python_embeds_path, dtype=np.float32)
    else:
        agent_embeds = np.zeros_like(ref_embeds.flatten())

    # Generate reference plot
    ref_plot_path = tmp_path / "ref_plot.png"

    residuals = ref_embeds.flatten() - agent_embeds

    plt.figure()
    plt.scatter(range(len(residuals)), residuals, alpha=0.5)
    plt.title("Embedding Residuals")
    plt.xlabel("Dimension Index")
    plt.ylabel("Error")
    plt.savefig(ref_plot_path)
    plt.close()

    # Compute SSIM
    img_agent = np.array(Image.open(agent_plot_path).convert('L'))
    img_ref = np.array(Image.open(ref_plot_path).convert('L'))

    if img_agent.shape != img_ref.shape:
        img_agent = np.array(Image.open(agent_plot_path).convert('L').resize(img_ref.shape[::-1]))

    score, _ = ssim(img_ref, img_agent, full=True, data_range=255)
    assert score >= 0.95, f"SSIM between generated plot and reference is {score:.4f}, expected >= 0.95"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
