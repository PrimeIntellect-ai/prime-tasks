#!/bin/bash
set -u
mkdir -p /logs/verifier
rm -f /home/user/result_spectrum.json /tmp/verifier_submission.json /tmp/verifier_job_seen

# Stop any backend left running by the agent so the worker is exercised against
# a verifier-controlled Flask API.
pkill -f '/app/server.py' 2>/dev/null || true
sleep 1
redis-server --daemonize yes >/dev/null 2>&1 || true

cat << 'SERVER_EOF' > /tmp/verifier_server.py
from flask import Flask, jsonify, request
import json

app = Flask(__name__)
job_seen = False

@app.get('/')
def health():
    return jsonify({'status': 'ready'})

@app.get('/job')
def job():
    global job_seen
    job_seen = True
    with open('/tmp/verifier_job_seen', 'w') as f:
        f.write('1')
    return jsonify({'alpha': 0.05, 'duration': 10.0, 'dt': 0.01})

@app.post('/submit')
def submit():
    if not job_seen:
        return jsonify({'error': 'job must be fetched before submission'}), 400
    if not request.is_json:
        return jsonify({'error': 'submission must be JSON'}), 415
    data = request.get_json()
    with open('/tmp/verifier_submission.json', 'w') as f:
        json.dump(data, f)
    with open('/home/user/result_spectrum.json', 'w') as f:
        json.dump(data, f)
    return jsonify({'status': 'success'})

app.run(host='127.0.0.1', port=5000)
SERVER_EOF

python3 /tmp/verifier_server.py >/tmp/verifier_server.log 2>&1 &
SERVER_PID=$!
cleanup() {
    kill "$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT

SERVER_READY=0
for _ in $(seq 1 50); do
    if curl -fsS http://127.0.0.1:5000/ >/dev/null 2>&1; then
        SERVER_READY=1
        break
    fi
    sleep 0.1
done

WORKER_OK=0
if [ "$SERVER_READY" -eq 1 ] && [ -f /app/worker.py ]; then
    if timeout 180s python3 /app/worker.py >/tmp/verifier_worker.log 2>&1; then
        WORKER_OK=1
    fi
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import numpy as np
from scipy.integrate import solve_ivp
import pytest


def _constant_values(tree):
    """Resolve simple numeric assignments used for mesh configuration."""
    values = {}

    def evaluate(node):
        if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
            return node.value
        if isinstance(node, ast.Name) and node.id in values:
            return values[node.id]
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.UAdd, ast.USub)):
            value = evaluate(node.operand)
            return value if isinstance(node.op, ast.UAdd) else -value
        if isinstance(node, ast.BinOp):
            left, right = evaluate(node.left), evaluate(node.right)
            if isinstance(node.op, ast.Add): return left + right
            if isinstance(node.op, ast.Sub): return left - right
            if isinstance(node.op, ast.Mult): return left * right
            if isinstance(node.op, ast.Div): return left / right
            if isinstance(node.op, ast.FloorDiv): return left // right
            if isinstance(node.op, ast.Pow): return left ** right
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
            args = [evaluate(arg) for arg in node.args]
            if node.func.id == 'int' and len(args) == 1: return int(args[0])
            if node.func.id == 'round' and len(args) in (1, 2): return round(*args)
        raise ValueError

    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            try:
                value = evaluate(node.value)
            except Exception:
                continue
            for target in targets:
                if isinstance(target, ast.Name):
                    values[target.id] = value
    return values, evaluate


def test_worker_uses_required_mesh_configuration():
    worker = '/app/worker.py'
    assert os.path.isfile(worker), 'The required /app/worker.py artifact is missing.'
    with open(worker, 'r') as f:
        tree = ast.parse(f.read(), filename=worker)

    values, evaluate = _constant_values(tree)
    nx_declared = any(name.lower() in ('nx', 'n_x') and value == 101
                      for name, value in values.items())
    mesh_call = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        name = None
        if isinstance(node.func, ast.Attribute):
            name = node.func.attr
        elif isinstance(node.func, ast.Name):
            name = node.func.id
        if name == 'linspace' and len(node.args) >= 3:
            try:
                mesh_call |= (evaluate(node.args[0]) == 0 and
                              evaluate(node.args[1]) == 1 and
                              evaluate(node.args[2]) == 101)
            except Exception:
                pass
    assert nx_declared or mesh_call, 'Worker must configure the required spatial mesh with exactly Nx = 101.'


def test_result_spectrum_mse():
    assert os.path.isfile('/tmp/verifier_job_seen'), 'Worker did not fetch the job from the Flask /job endpoint.'
    assert os.path.isfile('/tmp/verifier_submission.json'), 'Worker did not POST JSON to the Flask /submit endpoint.'

    result_file = '/home/user/result_spectrum.json'
    assert os.path.isfile(result_file), f'Result file {result_file} is missing. Did the worker submit the result?'

    with open(result_file, 'r') as f:
        try:
            agent_json = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'File {result_file} does not contain valid JSON.')
    with open('/tmp/verifier_submission.json', 'r') as f:
        submitted_json = json.load(f)
    assert agent_json == submitted_json, 'Result file must be produced by the worker submission endpoint.'

    try:
        agent_data = np.asarray(agent_json, dtype=float)
    except (TypeError, ValueError):
        pytest.fail('Submitted amplitudes must be numeric.')
    assert agent_data.ndim == 1, 'Submitted data must be a 1D list of amplitudes.'
    assert len(agent_data) == 501, f'Expected 501 amplitudes, got {len(agent_data)}.'
    assert np.all(np.isfinite(agent_data)), 'Submitted amplitudes must all be finite.'
    assert np.all(agent_data >= 0), 'Absolute FFT amplitudes cannot be negative.'

    # Compute golden reference using the required 101-point spatial mesh.
    alpha = 0.05
    duration = 10.0
    dt = 0.01
    Nx = 101
    x = np.linspace(0, 1, Nx)
    dx = x[1] - x[0]
    t_eval = np.arange(0, duration + dt/2, dt)

    def pde_enforced(t, u_int):
        u = np.zeros(Nx)
        u[1:-1] = u_int
        u[0] = np.sin(15*t) + 0.5*np.sin(40*t)
        u[-1] = 0
        dudt = np.zeros(Nx)
        dudt[1:-1] = alpha * (u[2:] - 2*u[1:-1] + u[:-2]) / dx**2
        return dudt[1:-1]

    u0 = np.zeros(Nx-2)
    sol = solve_ivp(pde_enforced, [0, duration], u0, t_eval=t_eval, method='BDF')
    assert sol.success

    u_full = np.zeros((Nx, len(t_eval)))
    u_full[0, :] = np.sin(15*t_eval) + 0.5*np.sin(40*t_eval)
    u_full[-1, :] = 0
    u_full[1:-1, :] = sol.y
    sensor_signal = u_full[50, :]
    spectrum = np.abs(np.fft.fft(sensor_signal)) / len(sensor_signal)
    half_len = len(sensor_signal) // 2 + 1
    golden_amplitudes = spectrum[:half_len]

    # Keep the original success assertion.
    mse = np.mean((agent_data - golden_amplitudes)**2)
    threshold = 1e-4
    assert mse < threshold, f'MSE {mse:.6e} is not strictly less than the threshold {threshold}.'

    # The absolute MSE is tiny even for an all-zero spectrum because the sensor
    # response is attenuated. Require the submitted spectral shape and energy to
    # agree as well, while allowing ordinary stable numerical solvers.
    relative_l2 = np.linalg.norm(agent_data - golden_amplitudes) / np.linalg.norm(golden_amplitudes)
    assert relative_l2 < 0.20, f'Relative spectrum error {relative_l2:.6e} is too large.'
TEST_EOF

if [ "$WORKER_OK" -eq 1 ] && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
