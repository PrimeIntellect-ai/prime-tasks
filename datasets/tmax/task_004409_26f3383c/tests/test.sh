#!/bin/bash
set -uo pipefail
mkdir -p /logs/verifier

reward=0
workdir=$(mktemp -d /tmp/solver_verify.XXXXXX)
call_log="$workdir/eval_source_calls.log"
real_source="/app/eval_source.verifier-real"
bin_path="$workdir/solver"
touch "$call_log"
chmod 666 "$call_log"

cleanup() {
    if [ -e "$real_source" ]; then
        rm -f /app/eval_source
        mv "$real_source" /app/eval_source
    fi
    rm -rf "$workdir"
}
trap cleanup EXIT

precheck_and_run() {
    test -f /home/user/solver.go || return 1

    # Ensure all imported packages are from the Go standard library.
    local nonstandard
    nonstandard=$(cd /home/user && GO111MODULE=off go list -deps -f '{{if and (not .Standard) (ne .ImportPath "command-line-arguments")}}{{.ImportPath}}{{end}}' solver.go 2>/dev/null) || return 1
    test -z "$nonstandard" || return 1

    (cd /home/user && GO111MODULE=off go build -o "$bin_path" solver.go) || return 1
    test -x "$bin_path" || return 1

    mv /app/eval_source "$real_source" || return 1
    cat > /app/eval_source <<WRAPPER_EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$call_log"
exec "$real_source" "\$@"
WRAPPER_EOF
    chmod 755 /app/eval_source || return 1

    # The submitted program must create the evaluated artifact itself.
    rm -f /home/user/solution.txt
    runuser -u user -- env HOME=/home/user timeout 120s "$bin_path" || return 1
    test -f /home/user/solution.txt || return 1

    # Restore the genuine black-box binary before evaluating the result.
    rm -f /app/eval_source
    mv "$real_source" /app/eval_source || return 1
    return 0
}

if precheck_and_run; then
    cat > "$workdir/test_final_state.py" <<TEST_EOF
import os
import numpy as np
import scipy.integrate as integrate
import pytest

CALL_LOG = ${call_log@Q}

def exact_f(x):
    return -10000.0 * np.exp(-10000.0 * (x - 0.5)**2)

def test_solver_used_black_box_iteratively():
    assert os.path.exists(CALL_LOG), "No eval_source call log was produced"
    with open(CALL_LOG, "r", encoding="utf-8") as fh:
        calls = [line.split() for line in fh if line.strip()]

    assert len(calls) >= 2, "solver.go must evaluate the black-box source during iterative refinement"
    queried = []
    for call in calls:
        for value in call:
            try:
                queried.append(float(value))
            except ValueError:
                pytest.fail(f"eval_source was called with a non-numeric argument: {value!r}")
    assert len(set(queried)) >= 3, "solver.go did not evaluate the source at enough distinct mesh points"
    assert all(np.isfinite(queried)), "eval_source was called with a non-finite coordinate"
    assert all(0.0 <= q <= 1.0 for q in queried), "eval_source was queried outside [0, 1]"

def test_solution_format_and_metrics():
    solution_path = "/home/user/solution.txt"
    assert os.path.exists(solution_path), f"Solution file not found at {solution_path}"

    try:
        data = np.loadtxt(solution_path)
    except Exception as e:
        pytest.fail(f"Failed to load {solution_path}. Ensure it contains space-separated numbers. Error: {e}")

    assert data.ndim == 2, f"Expected 2 columns in {solution_path}, but got {data.ndim} dimensions."
    assert data.shape[1] == 2, f"Expected 2 columns (x, u) in {solution_path}, but got {data.shape[1]} columns."

    x_agent = data[:, 0]
    u_agent = data[:, 1]

    num_points = len(x_agent)
    assert num_points < 150, f"Too many grid points: {num_points}. Must be strictly < 150."

    assert np.all(np.diff(x_agent) > 0), "The x values in solution.txt must be sorted in strictly ascending order."

    # The requested AMR solution must retain a genuinely non-uniform final mesh.
    assert num_points >= 3, "The solution must contain boundary and interior mesh points."
    spacing = np.diff(x_agent)
    assert not np.allclose(spacing, spacing[0], rtol=1e-7, atol=1e-12), \
        "The final mesh is uniform; a non-uniform adaptively refined mesh is required."

    # Compute exact solution using double integration
    x_fine = np.linspace(0, 1, 10000)
    f_fine = exact_f(x_fine)

    # Handle newer scipy versions where cumtrapz is renamed to cumulative_trapezoid
    if hasattr(integrate, 'cumulative_trapezoid'):
        cumtrapz_func = integrate.cumulative_trapezoid
    else:
        cumtrapz_func = integrate.cumtrapz

    u_prime = cumtrapz_func(f_fine, x_fine, initial=0)
    u_temp = cumtrapz_func(u_prime, x_fine, initial=0)

    # Apply Dirichlet boundary conditions: u(0) = 0, u(1) = 0
    u_exact = u_temp - x_fine * u_temp[-1]

    # Interpolate agent's solution onto the fine grid
    u_interp = np.interp(x_fine, x_agent, u_agent)

    # Calculate maximum absolute error
    max_err = np.max(np.abs(u_interp - u_exact))

    assert max_err <= 0.005, f"Max error is {max_err:.5f}, which exceeds the threshold of 0.005."
TEST_EOF

    if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider "$workdir/test_final_state.py" -x --tb=short 2>&1; then
        reward=1
    fi
fi

echo "$reward" > /logs/verifier/reward.txt
exit 0
