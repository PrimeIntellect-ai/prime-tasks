#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import importlib.metadata
import json
import math
import os
import re
import signal
import subprocess
from pathlib import Path

import numpy as np
import pandas as pd
import pytest
import requests

CSV_PATH = Path('/home/user/sensor_data.csv')
TRACKING_PATH = Path('/home/user/tracking.json')
PACKAGE_ROOT = Path('/app/bayes_prob_lib')
AUTH_HEADERS = {'Authorization': 'Bearer lab_auth_token_88'}
URL = 'http://127.0.0.1:8000/infer'


def expected_tracking():
    frame = pd.read_csv(CSV_PATH)
    sensors = ['sensor_A', 'sensor_B', 'sensor_C', 'sensor_D']
    correlations = frame[sensors].corr(method='pearson')
    dropped = max(sensors[1:], key=lambda name: abs(float(correlations.loc['sensor_A', name])))
    retained = [name for name in sensors if name != dropped]
    determinant = float(np.linalg.det(frame[retained].cov(ddof=1).to_numpy()))
    return dropped, retained, determinant


def valid_tracking_file(expected_drop, expected_det):
    if not TRACKING_PATH.is_file():
        return False
    try:
        with TRACKING_PATH.open() as handle:
            data = json.load(handle)
    except (OSError, json.JSONDecodeError):
        return False
    return (
        isinstance(data, dict)
        and set(data) == {'dropped_sensor', 'covariance_determinant'}
        and data.get('dropped_sensor') == expected_drop
        and isinstance(data.get('covariance_determinant'), (int, float))
        and not isinstance(data.get('covariance_determinant'), bool)
        and math.isfinite(float(data['covariance_determinant']))
        and math.isclose(float(data['covariance_determinant']), expected_det,
                         rel_tol=1e-3, abs_tol=1e-4)
    )


def etl_candidates():
    roots = [Path('/home/user'), Path('/app'), Path('/workspace'), Path('/root'), Path('/opt')]
    candidates = []
    for root in roots:
        if not root.exists():
            continue
        for directory, subdirs, files in os.walk(root):
            subdirs[:] = [d for d in subdirs if d not in {
                '.git', '.cache', '__pycache__', 'site-packages', 'dist-packages',
                'node_modules', '.venv', 'venv'
            }]
            for filename in files:
                if not filename.endswith('.py'):
                    continue
                path = Path(directory) / filename
                try:
                    if path.stat().st_size > 1_000_000:
                        continue
                    source = path.read_text(errors='ignore')
                except OSError:
                    continue
                if 'sensor_data.csv' in source and 'tracking.json' in source:
                    candidates.append(path)
    return sorted(set(candidates))


def run_candidate(path):
    process = subprocess.Popen(
        ['python3', str(path)],
        cwd=str(path.parent),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        process.communicate(timeout=15)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()


def test_tracking_json_is_generated_by_etl_script():
    expected_drop, _, expected_det = expected_tracking()
    original_csv = CSV_PATH.read_bytes()
    candidates = etl_candidates()
    assert candidates, 'No Python ETL script reading sensor_data.csv and writing tracking.json was found.'

    successful_script = None
    for candidate in candidates:
        TRACKING_PATH.unlink(missing_ok=True)
        try:
            run_candidate(candidate)
        finally:
            CSV_PATH.write_bytes(original_csv)
        if valid_tracking_file(expected_drop, expected_det):
            successful_script = candidate
            break

    assert successful_script is not None, (
        'Executing the submitted Python ETL scripts did not produce a correct tracking.json.'
    )

    with TRACKING_PATH.open() as handle:
        data = json.load(handle)
    assert set(data) == {'dropped_sensor', 'covariance_determinant'}, (
        'tracking.json must have exactly the required two fields.'
    )
    assert data['dropped_sensor'] == expected_drop
    assert math.isclose(data['covariance_determinant'], expected_det,
                        rel_tol=1e-3, abs_tol=1e-4)


def test_makefile_and_extension_build():
    makefile = PACKAGE_ROOT / 'Makefile'
    assert makefile.is_file(), 'The vendored package Makefile is missing.'
    source = makefile.read_text()
    lines = source.splitlines()
    build_indices = [i for i, line in enumerate(lines) if re.match(r'^build\s*:', line)]
    assert build_indices, 'The Makefile has no build target.'
    index = build_indices[0] + 1
    while index < len(lines) and not lines[index].strip():
        index += 1
    assert index < len(lines) and lines[index].startswith('\t'), (
        'The build recipe in the Makefile must be indented with a tab.'
    )

    result = subprocess.run(
        ['make', '-B', '-C', str(PACKAGE_ROOT), 'build'],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f'make failed:\n{result.stdout}'

    extension = PACKAGE_ROOT / 'dummy.so'
    assert extension.is_file(), 'make did not create dummy.so.'
    assert extension.read_bytes()[:4] == b'\x7fELF', 'dummy.so is not an ELF shared object.'
    ctypes.CDLL(str(extension))


def test_fixed_package_is_installed_and_operational():
    try:
        distribution = importlib.metadata.distribution('bayes_prob_lib')
    except importlib.metadata.PackageNotFoundError:
        pytest.fail('bayes_prob_lib is not installed in the Python environment.')
    assert distribution.version == '1.0.0'

    import bayes_prob_lib
    from bayes_prob_lib import inference

    module_path = Path(inference.__file__).resolve()
    assert PACKAGE_ROOT.resolve() in module_path.parents, (
        f'Imported bayes_prob_lib from an unexpected location: {module_path}'
    )
    inference_source = module_path.read_text()
    assert re.search(r'^\s*import\s+numpy\s+as\s+np\s*$', inference_source, re.MULTILINE), (
        'inference.py does not contain the required numpy import fix.'
    )
    assert inference.np is np

    for values in (
        {'sensor_A': 0.0, 'sensor_C': 0.0, 'sensor_D': 0.0},
        {'sensor_A': -2.25, 'sensor_C': 0.4, 'sensor_D': 1.1},
        {'sensor_A': 3.7, 'sensor_C': -1.3, 'sensor_D': 0.2},
    ):
        expected = 1.0 / (1.0 + math.exp(-sum(values.values())))
        actual = inference.calculate_posterior(values)
        assert isinstance(actual, float)
        assert math.isclose(actual, expected, rel_tol=1e-10, abs_tol=1e-10)
        assert math.isclose(bayes_prob_lib.calculate_posterior(values), expected,
                            rel_tol=1e-10, abs_tol=1e-10)


def test_server_is_bound_exactly_to_ipv4_loopback_port_8000():
    listeners = []
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        with open(table) as handle:
            next(handle)
            for line in handle:
                fields = line.split()
                local_address, state = fields[1], fields[3]
                address, port = local_address.split(':')
                if state == '0A' and int(port, 16) == 8000:
                    listeners.append((table, address))

    assert ('/proc/net/tcp', '0100007F') in listeners, (
        'No server is listening on exactly 127.0.0.1:8000.'
    )
    assert ('/proc/net/tcp', '00000000') not in listeners, (
        'The server is listening on 0.0.0.0 rather than exactly 127.0.0.1.'
    )
    assert ('/proc/net/tcp6', '00000000000000000000000000000000') not in listeners, (
        'The server is listening on the IPv6 wildcard address.'
    )


def test_api_unauthorized():
    payload = {'sensor_A': 1.0, 'sensor_C': 0.5, 'sensor_D': 1.1}
    try:
        response = requests.post(URL, json=payload, timeout=3)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f'Failed to connect to API at {URL}: {exc}')
    assert response.status_code == 401

    response = requests.post(
        URL,
        json=payload,
        headers={'Authorization': 'Bearer wrong_token'},
        timeout=3,
    )
    assert response.status_code == 401


def assert_authorized_posterior(payload):
    response = requests.post(URL, json=payload, headers=AUTH_HEADERS, timeout=3)
    assert response.status_code == 200, response.text
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f'Response is not valid JSON: {response.text}')
    assert set(data) == {'posterior_probability'}
    actual = data['posterior_probability']
    assert isinstance(actual, (int, float)) and not isinstance(actual, bool)
    expected = 1.0 / (1.0 + math.exp(-sum(payload.values())))
    assert math.isclose(actual, expected, rel_tol=1e-5, abs_tol=1e-5), (
        f'Incorrect posterior for {payload}: expected {expected}, got {actual}'
    )


def test_api_authorized_and_logic_on_multiple_payloads():
    # Preserve the original authorized example.
    assert_authorized_posterior({'sensor_A': 1.0, 'sensor_C': 0.5, 'sensor_D': 1.1})

    # Exercise distinct sums and signs so a single hard-coded response cannot pass.
    assert_authorized_posterior({'sensor_A': -1.75, 'sensor_C': 0.2, 'sensor_D': 0.45})
    assert_authorized_posterior({'sensor_A': 2.4, 'sensor_C': -3.1, 'sensor_D': 0.05})
    assert_authorized_posterior({'sensor_A': 0.0, 'sensor_C': 0.0, 'sensor_D': 0.0})
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
