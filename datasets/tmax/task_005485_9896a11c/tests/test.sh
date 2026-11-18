#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess

RESULTS_PATH = "/home/user/ml_data/results.txt"
VENV_PYTHON = "/home/user/venv/bin/python"


def test_venv_and_directories():
    """Check if the virtual environment and data directory are created."""
    assert os.path.isdir("/home/user/venv"), "Virtual environment directory /home/user/venv is missing."
    assert os.path.isfile(VENV_PYTHON), "Python executable not found in /home/user/venv/bin/."
    assert os.access(VENV_PYTHON, os.X_OK), "Virtual environment Python is not executable."
    assert os.path.isdir("/home/user/ml_data"), "Directory /home/user/ml_data is missing."

    proc = subprocess.run(
        [VENV_PYTHON, "-c", "import numpy, scipy"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert proc.returncode == 0, "numpy and scipy must be installed in /home/user/venv.\n" + proc.stderr


def find_and_execute_submission():
    candidates = []
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d not in {"venv", ".cache", "__pycache__"}]
        for name in files:
            if not name.endswith(".py"):
                continue
            path = os.path.join(root, name)
            try:
                with open(path, "r", encoding="utf-8", errors="ignore") as f:
                    source = f.read()
            except OSError:
                continue
            score = sum(token in source for token in
                        ("results.txt", "minimize", "Nelder-Mead", "svd", "percentile", "solve_ivp", "odeint"))
            candidates.append((-score, path))

    assert candidates, "No Python script was created under /home/user."
    candidates.sort()

    failures = []
    for _, script in candidates:
        try:
            if os.path.exists(RESULTS_PATH):
                os.remove(RESULTS_PATH)
            proc = subprocess.run(
                [VENV_PYTHON, script],
                cwd=os.path.dirname(script) or "/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=900,
                env={**os.environ, "PYTHONNOUSERSITE": "1"},
            )
        except subprocess.TimeoutExpired:
            failures.append(f"{script}: timed out")
            continue

        if proc.returncode == 0 and os.path.isfile(RESULTS_PATH):
            return script
        failures.append(f"{script}: exit={proc.returncode}, stderr={proc.stderr[-500:]}")

    raise AssertionError(
        "No submitted Python script successfully generated /home/user/ml_data/results.txt.\n"
        + "\n".join(failures)
    )


def parse_and_check_results():
    """Check if results.txt exists and contains the correct structure and approximate values."""
    assert os.path.isfile(RESULTS_PATH), f"Results file {RESULTS_PATH} is missing."

    with open(RESULTS_PATH, "r") as f:
        content = f.read()

    # Original parsing assertions.
    gamma_match = re.search(r"gamma:\s*([\d\.]+)", content)
    omega_match = re.search(r"omega:\s*([\d\.]+)", content)
    gamma_ci_match = re.search(r"gamma_ci:\s*\[([\d\.]+),\s*([\d\.]+)\]", content)
    omega_ci_match = re.search(r"omega_ci:\s*\[([\d\.]+),\s*([\d\.]+)\]", content)

    assert gamma_match, "Could not parse 'gamma: <value>' from results.txt."
    assert omega_match, "Could not parse 'omega: <value>' from results.txt."
    assert gamma_ci_match, "Could not parse 'gamma_ci: [<low>, <high>]' from results.txt."
    assert omega_ci_match, "Could not parse 'omega_ci: [<low>, <high>]' from results.txt."

    gamma = float(gamma_match.group(1))
    omega = float(omega_match.group(1))
    gamma_ci_low, gamma_ci_high = float(gamma_ci_match.group(1)), float(gamma_ci_match.group(2))
    omega_ci_low, omega_ci_high = float(omega_ci_match.group(1)), float(omega_ci_match.group(2))

    # Keep the original approximate-value assertions.
    assert 0.45 <= gamma <= 0.55, f"Expected gamma to be around 0.5054, got {gamma}"
    assert 1.95 <= omega <= 2.05, f"Expected omega to be around 1.9995, got {omega}"
    assert gamma_ci_low < gamma_ci_high, "gamma_ci lower bound must be less than upper bound"
    assert omega_ci_low < omega_ci_high, "omega_ci lower bound must be less than upper bound"
    assert 0.40 <= gamma_ci_low <= 0.51, f"gamma_ci low out of expected range, got {gamma_ci_low}"
    assert 0.50 <= gamma_ci_high <= 0.60, f"gamma_ci high out of expected range, got {gamma_ci_high}"
    assert 1.90 <= omega_ci_low <= 2.00, f"omega_ci low out of expected range, got {omega_ci_low}"
    assert 1.99 <= omega_ci_high <= 2.10, f"omega_ci high out of expected range, got {omega_ci_high}"

    # Enforce the instruction's exact four-line, four-decimal output format.
    exact = re.fullmatch(
        r"gamma: (\d+\.\d{4})\n"
        r"omega: (\d+\.\d{4})\n"
        r"gamma_ci: \[(\d+\.\d{4}), (\d+\.\d{4})\]\n"
        r"omega_ci: \[(\d+\.\d{4}), (\d+\.\d{4})\](?:\n)?",
        content,
    )
    assert exact, "results.txt must use exactly the requested four-line format with four decimal places."
    return gamma, omega, gamma_ci_low, gamma_ci_high, omega_ci_low, omega_ci_high


def independently_compute_results():
    import numpy as np
    from scipy.integrate import solve_ivp
    from scipy.optimize import minimize

    t = np.linspace(0, 10, 100)
    x0s = np.arange(1.0, 2.0, 0.1)

    def simulate(params):
        gamma, omega = params
        y0 = np.zeros(2 * len(x0s))
        y0[0::2] = x0s

        def rhs(_, y):
            out = np.empty_like(y)
            out[0::2] = y[1::2]
            out[1::2] = -gamma * y[1::2] - omega**2 * y[0::2]
            return out

        solution = solve_ivp(rhs, (0, 10), y0, t_eval=t)
        assert solution.success and solution.y.shape == (20, 100), "Independent ODE integration failed."
        return solution.y[0::2].T

    X_true = simulate((0.5, 2.0))
    np.random.seed(42)
    X_noisy = X_true + np.random.normal(0, 0.1, X_true.shape)

    U, singular_values, Vt = np.linalg.svd(X_noisy, full_matrices=False)
    X_denoised = (U[:, :2] * singular_values[:2]) @ Vt[:2, :]

    def objective(params, target):
        return np.mean((simulate(params) - target) ** 2)

    fitted = minimize(
        objective,
        np.array([0.2, 1.5]),
        args=(X_denoised,),
        method="Nelder-Mead",
    ).x
    X_fit = simulate(fitted)
    residuals = X_denoised - X_fit

    np.random.seed(42)
    bootstrap = np.empty((100, 2))
    flattened = residuals.ravel()
    for i in range(100):
        R_boot = np.random.choice(flattened, size=residuals.shape, replace=True)
        X_boot = X_fit + R_boot
        bootstrap[i] = minimize(
            objective,
            fitted,
            args=(X_boot,),
            method="Nelder-Mead",
        ).x

    gamma_ci = np.percentile(bootstrap[:, 0], [2.5, 97.5])
    omega_ci = np.percentile(bootstrap[:, 1], [2.5, 97.5])
    return fitted[0], fitted[1], gamma_ci[0], gamma_ci[1], omega_ci[0], omega_ci[1]


def main():
    test_venv_and_directories()
    find_and_execute_submission()
    actual = parse_and_check_results()
    expected = independently_compute_results()

    # Allow minor integration-library differences while requiring the submitted
    # output to agree with a fresh ODE/SVD/optimization/bootstrap computation.
    tolerances = (0.003, 0.003, 0.015, 0.015, 0.015, 0.015)
    labels = ("gamma", "omega", "gamma_ci low", "gamma_ci high", "omega_ci low", "omega_ci high")
    for label, got, want, tolerance in zip(labels, actual, expected, tolerances):
        assert abs(got - want) <= tolerance, (
            f"{label} does not match the independently recomputed result: "
            f"got {got}, expected approximately {want:.4f}"
        )


if __name__ == "__main__":
    main()
TEST_EOF

if /home/user/venv/bin/python /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
