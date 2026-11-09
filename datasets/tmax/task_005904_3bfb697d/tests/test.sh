#!/bin/bash
set -u
mkdir -p /logs/verifier

verify() {
  rm -rf /tmp/osc_verify
  mkdir -p /tmp/osc_verify

  # Use unpredictable posterior samples so a hard-coded JSON cannot pass.
  eval "$(python3 - <<'PY'
import secrets
g = secrets.choice(range(131, 170)) / 1000
o = secrets.choice(range(3121, 3160)) / 1000
print(f"export VERIFY_GAMMA={g:.3f}")
print(f"export VERIFY_OMEGA={o:.3f}")
PY
)"
  export OSC_TRACE=/tmp/osc_verify/trace.json

  cat > /tmp/osc_verify/sitecustomize.py <<'PY'
import json
import os
import numpy as np

TRACE = os.environ['OSC_TRACE']
TARGET_G = float(os.environ['VERIFY_GAMMA'])
TARGET_O = float(os.environ['VERIFY_OMEGA'])
state = {
    'read_csv': False,
    'solve_valid': False,
    'pool4': False,
    'sampler32': False,
    'steps1000': False,
    'seed42_and_init': False,
    'prior_valid': False,
    'prior_bounds': False,
    'likelihood_valid': False,
    'chain_requested': False,
}
loaded_df = None
seed_calls = []

def save():
    try:
        with open(TRACE, 'w') as f:
            json.dump(state, f)
    except Exception:
        pass

# Record the required data load while returning the real CSV contents.
import pandas as pd
_real_read_csv = pd.read_csv
def read_csv(path, *args, **kwargs):
    global loaded_df
    result = _real_read_csv(path, *args, **kwargs)
    if os.path.abspath(os.fspath(path)) == '/home/user/oscillator_data.csv':
        state['read_csv'] = True
        loaded_df = result.copy()
        save()
    return result
pd.read_csv = read_csv

# Record and validate actual model solves, then delegate to scipy's RK45 solver.
import scipy.integrate
_real_solve_ivp = scipy.integrate.solve_ivp
def solve_ivp(fun, t_span, y0, *args, **kwargs):
    valid = kwargs.get('method', 'RK45') == 'RK45'
    valid = valid and np.allclose(np.asarray(y0, dtype=float), [1.0, 0.0])
    call_args = kwargs.get('args', ())
    try:
        if len(call_args) >= 2:
            gamma, omega = float(call_args[0]), float(call_args[1])
            probe = np.asarray(fun(0.37, [0.7, -0.4], *call_args), dtype=float)
            expected = np.array([-0.4, -2.0 * gamma * (-0.4) - omega**2 * 0.7])
            valid = valid and np.allclose(probe, expected, rtol=1e-10, atol=1e-10)
        else:
            valid = False
        if loaded_df is not None and 't' in loaded_df:
            valid = valid and np.allclose(np.asarray(kwargs.get('t_eval')), loaded_df['t'].to_numpy())
    except Exception:
        valid = False
    if valid:
        state['solve_valid'] = True
        save()
    return _real_solve_ivp(fun, t_span, y0, *args, **kwargs)
scipy.integrate.solve_ivp = solve_ivp

# Record the reproducibility call.
_real_seed = np.random.seed
def seed(value=None):
    seed_calls.append(value)
    return _real_seed(value)
np.random.seed = seed

# Replace only the expensive pool and sampler. The submitted posterior function is
# still called and its ODE/data likelihood is checked below.
import multiprocessing
class CheckedPool:
    def __init__(self, processes=None, *args, **kwargs):
        if processes == 4:
            state['pool4'] = True
            save()
        self.processes = processes
    def __enter__(self): return self
    def __exit__(self, *exc): return False
    def close(self): pass
    def join(self): pass
    def terminate(self): pass
    def map(self, func, iterable, chunksize=None): return list(map(func, iterable))
    def starmap(self, func, iterable, chunksize=None): return [func(*x) for x in iterable]
multiprocessing.Pool = CheckedPool

import emcee
class CheckedSampler:
    def __init__(self, nwalkers, ndim, log_prob_fn, *args, **kwargs):
        self.nwalkers = nwalkers
        self.ndim = ndim
        self.log_prob_fn = log_prob_fn
        self.pool = kwargs.get('pool')
        if nwalkers == 32 and ndim == 2:
            state['sampler32'] = True
            save()
        # Burn-in deliberately has a different mean. Only discarding 500 steps
        # produces the unpredictable target values.
        self._chain = np.empty((1000, 32, 2), dtype=float)
        self._chain[:500, :, 0] = 0.8
        self._chain[:500, :, 1] = 4.8
        offsets = np.tile(np.array([-0.0004, 0.0004]), 16)
        self._chain[500:, :, 0] = TARGET_G + offsets
        self._chain[500:, :, 1] = TARGET_O - offsets

    def run_mcmc(self, initial_state, nsteps, *args, **kwargs):
        p = np.asarray(initial_state, dtype=float)
        state['steps1000'] = (nsteps == 1000)
        expected = np.array([0.2, 3.0]) + 0.01 * np.random.RandomState(42).normal(size=(32, 2))
        state['seed42_and_init'] = bool(seed_calls and seed_calls[-1] == 42 and p.shape == (32, 2) and np.allclose(p, expected))
        try:
            theta = np.array([0.2, 3.0])
            value = float(self.log_prob_fn(theta))
            state['prior_valid'] = np.isfinite(value)
            outside = [(0.0, 3.0), (1.0, 3.0), (0.2, 1.0), (0.2, 5.0)]
            state['prior_bounds'] = all(np.isneginf(float(self.log_prob_fn(np.array(x)))) for x in outside)

            # Check the finite posterior against the specified Gaussian likelihood.
            # A constant normalization term is accepted whether included or omitted.
            if loaded_df is not None:
                t = loaded_df['t'].to_numpy(dtype=float)
                obs = loaded_df['y1_obs'].to_numpy(dtype=float)
                def rhs(tt, y):
                    return [y[1], -2.0 * theta[0] * y[1] - theta[1]**2 * y[0]]
                sol = _real_solve_ivp(rhs, [float(t[0]), float(t[-1])], [1.0, 0.0], t_eval=t, method='RK45')
                residual = obs - sol.y[0]
                core = -0.5 * np.sum((residual / 0.1) ** 2)
                normalized = core - 0.5 * len(obs) * np.log(2.0 * np.pi * 0.1**2)
                state['likelihood_valid'] = bool(np.isclose(value, core, rtol=1e-7, atol=1e-6) or np.isclose(value, normalized, rtol=1e-7, atol=1e-6))
        except Exception:
            pass
        save()
        return self._chain[-1]

    def get_chain(self, discard=0, thin=1, flat=False):
        state['chain_requested'] = True
        save()
        result = self._chain[discard::thin]
        return result.reshape((-1, 2)) if flat else result

    @property
    def chain(self):
        state['chain_requested'] = True
        save()
        return np.transpose(self._chain, (1, 0, 2))

emcee.EnsembleSampler = CheckedSampler
save()
PY

  mapfile -t candidates < <(find /home/user -maxdepth 3 -type f -name '*.py' -print 2>/dev/null | sort)
  [ "${#candidates[@]}" -gt 0 ] || return 1

  chosen=''
  for script in "${candidates[@]}"; do
    rm -f "$OSC_TRACE" /home/user/posterior_mean.json
    if timeout 90 env PYTHONPATH="/tmp/osc_verify${PYTHONPATH:+:$PYTHONPATH}" \
        OSC_TRACE="$OSC_TRACE" VERIFY_GAMMA="$VERIFY_GAMMA" VERIFY_OMEGA="$VERIFY_OMEGA" \
        python3 "$script" >/tmp/osc_verify/run.out 2>/tmp/osc_verify/run.err; then
      if python3 - "$OSC_TRACE" "$VERIFY_GAMMA" "$VERIFY_OMEGA" <<'PY'
import json, os, sys
trace, eg, eo = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
required = ['read_csv', 'solve_valid', 'pool4', 'sampler32', 'steps1000',
            'seed42_and_init', 'prior_valid', 'prior_bounds',
            'likelihood_valid', 'chain_requested']
try:
    with open(trace) as f: state = json.load(f)
    with open('/home/user/posterior_mean.json') as f: result = json.load(f)
    assert all(state.get(k) is True for k in required)
    assert set(result) >= {'gamma', 'omega'}
    assert result['gamma'] == round(eg, 3)
    assert result['omega'] == round(eo, 3)
except Exception:
    raise SystemExit(1)
PY
      then
        chosen="$script"
        break
      fi
    fi
  done
  [ -n "$chosen" ] || return 1

  # Preserve the original verifier's existence, content, range, and rounding assertions.
  cat > /tmp/osc_verify/test_final_state.py <<'PY'
import json
import os

def test_posterior_mean_file_exists():
    file_path = '/home/user/posterior_mean.json'
    assert os.path.exists(file_path), f'The required output file {file_path} does not exist.'
    assert os.path.isfile(file_path), f'The path {file_path} is not a file.'

def test_posterior_mean_content():
    file_path = '/home/user/posterior_mean.json'
    with open(file_path) as f:
        data = json.load(f)
    assert 'gamma' in data, "Key 'gamma' is missing from the JSON file."
    assert 'omega' in data, "Key 'omega' is missing from the JSON file."
    gamma, omega = data['gamma'], data['omega']
    assert isinstance(gamma, (int, float)), f"Expected 'gamma' to be a number, got {type(gamma)}"
    assert isinstance(omega, (int, float)), f"Expected 'omega' to be a number, got {type(omega)}"
    assert 0.130 <= gamma <= 0.170, f'Gamma value {gamma} is out of the expected bounds [0.130, 0.170]'
    assert 3.120 <= omega <= 3.160, f'Omega value {omega} is out of the expected bounds [3.120, 3.160]'

def test_posterior_mean_rounding():
    with open('/home/user/posterior_mean.json') as f:
        data = json.load(f)
    for key in ('gamma', 'omega'):
        text = str(data[key])
        if '.' in text:
            assert len(text.split('.')[1]) <= 3, f'{key} value {data[key]} is not rounded to 3 decimal places.'
PY
  python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/osc_verify/test_final_state.py -q --tb=short
}

if verify >/tmp/osc_verify_result.out 2>&1; then
  echo '1' > /logs/verifier/reward.txt
else
  cat /tmp/osc_verify_result.out 2>/dev/null || true
  echo '0' > /logs/verifier/reward.txt
fi
