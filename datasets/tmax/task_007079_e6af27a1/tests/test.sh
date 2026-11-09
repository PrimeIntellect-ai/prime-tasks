#!/bin/bash
mkdir -p /logs/verifier

if timeout 600s python3 - <<'PY'
import os
import runpy
import numpy as np
import scipy.optimize
import h5py

SCRIPT = '/home/user/optimize_drift.py'
RESULTS = '/home/user/results.h5'

assert os.path.isfile(SCRIPT), f'{SCRIPT} does not exist'
assert os.path.isfile(SCRIPT) and not os.path.isdir(SCRIPT), f'{SCRIPT} is not a regular file'

# Force the submitted artifact to regenerate its output during verification.
if os.path.exists(RESULTS):
    os.remove(RESULTS)


def reference_simulation(v, active_only_draws=False):
    """Implement the specified seeded dynamics independently."""
    v = np.asarray(v, dtype=np.float64)
    assert v.shape == (2,) and np.all(np.isfinite(v))

    np.random.seed(42)
    pos = np.zeros((10000, 2), dtype=np.float64)
    active = np.ones(10000, dtype=bool)

    for _ in range(20):
        idx = np.flatnonzero(active)
        if active_only_draws:
            steps = np.random.normal(0.0, 1.0, size=(idx.size, 2))
            pos[idx] = pos[idx] + steps + v
        else:
            # Drawing for the full array and applying only to active particles is
            # also consistent with updating every active particle each step.
            steps = np.random.normal(0.0, 1.0, size=(10000, 2))
            pos[idx] = pos[idx] + steps[idx] + v

        trapped = active & (np.sum((pos - np.array([4.0, 4.0])) ** 2, axis=1) <= 9.0)
        pos[trapped] = np.nan
        active[trapped] = False

    finite = active
    target_count = int(np.sum(
        np.sum((pos[finite] - np.array([10.0, 10.0])) ** 2, axis=1) <= 4.0
    ))
    return pos, target_count


def expected_counts(v):
    return {
        reference_simulation(v, active_only_draws=False)[1],
        reference_simulation(v, active_only_draws=True)[1],
    }

# Instrument scipy.optimize.minimize while running the submitted script. This
# verifies that the generated optimized_v is actually returned by a Nelder-Mead
# optimization started from the required initial guess.
original_minimize = scipy.optimize.minimize
minimize_results = []


def tracked_minimize(fun, x0, *args, **kwargs):
    import inspect

    bound = inspect.signature(original_minimize).bind_partial(fun, x0, *args, **kwargs)
    method = bound.arguments.get('method', None)
    assert isinstance(method, str) and method.lower() == 'nelder-mead', \
        f'Expected scipy.optimize.minimize method="Nelder-Mead", got {method!r}'

    initial = np.asarray(x0, dtype=np.float64)
    assert initial.shape == (2,) and np.array_equal(initial, np.array([0.0, 0.0])), \
        f'Expected initial guess [0.0, 0.0], got {initial!r}'

    # Exercise the submitted objective on independently-derived cases. Calling
    # it repeatedly must be safe because every simulation is required to reseed.
    for probe in (initial, np.array([0.65, 0.35], dtype=np.float64)):
        value1 = fun(probe.copy())
        value2 = fun(probe.copy())
        assert np.asarray(value1).shape == (), 'Objective must return a scalar'
        assert np.asarray(value2).shape == (), 'Objective must return a scalar'
        value1 = float(value1)
        value2 = float(value2)
        allowed = {-float(c) for c in expected_counts(probe)}
        assert value1 == value2, 'Objective is not deterministic across repeated simulations'
        assert value1 in allowed, \
            f'Objective at {probe.tolist()} was {value1}, expected negative target count in {sorted(allowed)}'

    result = original_minimize(fun, x0, *args, **kwargs)
    result_x = np.asarray(result.x, dtype=np.float64).copy()
    assert result_x.shape == (2,) and np.all(np.isfinite(result_x)), \
        'Nelder-Mead returned an invalid drift vector'

    final_objective = float(fun(result_x.copy()))
    allowed = {-float(c) for c in expected_counts(result_x)}
    assert final_objective in allowed, \
        f'Objective at optimizer result was {final_objective}, expected one of {sorted(allowed)}'

    minimize_results.append(result_x)
    return result


scipy.optimize.minimize = tracked_minimize
try:
    runpy.run_path(SCRIPT, run_name='__main__')
finally:
    scipy.optimize.minimize = original_minimize

assert minimize_results, 'The script did not call scipy.optimize.minimize'
assert os.path.isfile(RESULTS), f'{RESULTS} was not generated when the script was executed'

with h5py.File(RESULTS, 'r') as f:
    assert 'optimized_v' in f, "Dataset 'optimized_v' missing"
    assert 'final_positions' in f, "Dataset 'final_positions' missing"
    assert 'target_count' in f, "Dataset 'target_count' missing"

    v_ds = f['optimized_v']
    pos_ds = f['final_positions']
    count_ds = f['target_count']

    assert v_ds.shape == (2,), f'optimized_v shape is {v_ds.shape}, expected (2,)'
    assert pos_ds.shape == (10000, 2), \
        f'final_positions shape is {pos_ds.shape}, expected (10000, 2)'
    assert count_ds.shape == (), f'target_count shape is {count_ds.shape}, expected scalar'
    assert v_ds.dtype == np.dtype('float64'), f'optimized_v dtype is {v_ds.dtype}, expected float64'
    assert pos_ds.dtype == np.dtype('float64'), \
        f'final_positions dtype is {pos_ds.dtype}, expected float64'
    assert np.issubdtype(count_ds.dtype, np.integer), \
        f'target_count dtype is {count_ds.dtype}, expected integer'

    v = v_ds[:]
    pos = pos_ds[:]
    count = int(count_ds[()])

assert np.all(np.isfinite(v)), 'optimized_v contains NaN or infinity'
assert any(np.allclose(v, result_v, rtol=0.0, atol=1e-12) for result_v in minimize_results), \
    'optimized_v is not a drift vector returned by the Nelder-Mead optimization'

# Preserve the original NaN and target-count assertions.
nans_x = np.isnan(pos[:, 0])
nans_y = np.isnan(pos[:, 1])
assert np.array_equal(nans_x, nans_y), 'Trapped particles must have NaN in both coordinates'
assert int(np.sum(nans_x)) > 0, 'No trapped particles (NaNs) found!'
assert np.all(np.isfinite(pos[~nans_x])), 'Active particle positions contain non-finite values'

active_pos = pos[~nans_x]
dist_target = np.sqrt(np.sum((active_pos - np.array([10.0, 10.0])) ** 2, axis=1))
computed_count = int(np.sum(dist_target <= 2.0))
assert count == computed_count, \
    f'target_count ({count}) does not match computed count ({computed_count})'
assert computed_count > 1000, \
    f'Optimization failed: only {computed_count} particles reached the target (expected > 1000).'

# Independently replay the exact seeded dynamics using optimized_v. Accept the
# two natural random-draw conventions, while requiring all reported positions
# and the count to come from one complete valid replay.
matched = False
for active_only in (False, True):
    expected_pos, expected_count = reference_simulation(v, active_only_draws=active_only)
    if expected_count == count and np.allclose(
        pos, expected_pos, rtol=0.0, atol=1e-10, equal_nan=True
    ):
        matched = True
        break
assert matched, \
    'final_positions do not match the seeded 20-step simulation for optimized_v'
PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
