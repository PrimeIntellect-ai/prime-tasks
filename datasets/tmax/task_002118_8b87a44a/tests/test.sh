#!/bin/bash
set -e
mkdir -p /logs/verifier

PIPELINE=/home/user/pipeline.py
ORACLE=/app/oracle_sim
ORACLE_REAL=/app/oracle_sim.verifier-real
HOOK_DIR=/tmp/verifier_hooks
RUN_LOG=/tmp/pipeline_run.log
ORACLE_LOG=/tmp/oracle_audit.log
KDE_LOG=/tmp/kde_audit.log
QUAD_LOG=/tmp/quad_audit.log

rm -rf "$HOOK_DIR"
mkdir -p "$HOOK_DIR"
: > "$RUN_LOG"
: > "$ORACLE_LOG"
: > "$KDE_LOG"
: > "$QUAD_LOG"
chmod 666 "$RUN_LOG" "$ORACLE_LOG" "$KDE_LOG" "$QUAD_LOG"

cat > "$HOOK_DIR/sitecustomize.py" <<'PY_EOF'
import numpy as _np
import scipy.stats as _stats
import scipy.integrate as _integrate

_KDE_LOG = "/tmp/kde_audit.log"
_QUAD_LOG = "/tmp/quad_audit.log"
_OriginalKDE = _stats.gaussian_kde
_original_quad = _integrate.quad

class AuditedKDE(_OriginalKDE):
    def __init__(self, dataset, bw_method=None, weights=None):
        super().__init__(dataset, bw_method=bw_method, weights=weights)
        try:
            scott = bool(_np.isclose(self.factor, self.scotts_factor(), rtol=1e-12, atol=1e-15))
            with open(_KDE_LOG, "a") as f:
                f.write(f"construct n={self.n} d={self.d} scott={int(scott)} bw={bw_method!r}\n")
        except Exception as exc:
            with open(_KDE_LOG, "a") as f:
                f.write(f"construct_error {exc!r}\n")

    def evaluate(self, points):
        try:
            values = _np.asarray(points, dtype=float).reshape(-1)
            if values.size:
                with open(_KDE_LOG, "a") as f:
                    f.write(f"evaluate count={values.size} min={values.min():.17g} max={values.max():.17g}\n")
        except Exception as exc:
            with open(_KDE_LOG, "a") as f:
                f.write(f"evaluate_error {exc!r}\n")
        return super().evaluate(points)

    __call__ = evaluate
    pdf = evaluate


def audited_quad(func, a, b, *args, **kwargs):
    with open(_QUAD_LOG, "a") as f:
        f.write(f"quad a={float(a):.17g} b={float(b):.17g}\n")
    return _original_quad(func, a, b, *args, **kwargs)

_stats.gaussian_kde = AuditedKDE
_integrate.quad = audited_quad
PY_EOF
chmod -R a+rX "$HOOK_DIR"

restore_oracle() {
    if [ -e "$ORACLE_REAL" ]; then
        rm -f "$ORACLE"
        mv "$ORACLE_REAL" "$ORACLE"
        chmod +x "$ORACLE"
    fi
}
trap restore_oracle EXIT

run_ok=0
if [ -f "$PIPELINE" ] && [ -f "$ORACLE" ] && [ -x "$ORACLE" ]; then
    mv "$ORACLE" "$ORACLE_REAL"
    cat > "$ORACLE" <<'WRAPPER_EOF'
#!/bin/bash
log=/tmp/oracle_audit.log
tmp=$(mktemp /tmp/oracle-output.XXXXXX)
trap 'rm -f "$tmp"' EXIT
printf 'call argc=%s arg1=%s\n' "$#" "${1-}" >> "$log"
if /app/oracle_sim.verifier-real "$@" > "$tmp"; then
    lines=$(wc -l < "$tmp")
    printf 'complete argc=%s arg1=%s lines=%s\n' "$#" "${1-}" "$lines" >> "$log"
    cat "$tmp"
else
    rc=$?
    printf 'failed rc=%s\n' "$rc" >> "$log"
    exit "$rc"
fi
WRAPPER_EOF
    chmod 755 "$ORACLE"

    rm -f /home/user/integral_result.txt
    if timeout 300s runuser -u user -- env PYTHONPATH="$HOOK_DIR" python3 "$PIPELINE" > "$RUN_LOG" 2>&1; then
        run_ok=1
    fi
fi
printf '%s\n' "$run_ok" > /tmp/pipeline_run_status
restore_oracle
trap - EXIT

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import pytest
import numpy as np
import scipy.integrate as integrate
import scipy.stats as stats


def test_pipeline_script_exists():
    pipeline_file = "/home/user/pipeline.py"
    assert os.path.exists(pipeline_file), f"Failed: Pipeline script not found at {pipeline_file}"
    assert os.path.isfile(pipeline_file), f"Failed: Path {pipeline_file} is not a file."


def test_pipeline_executed_successfully():
    with open("/tmp/pipeline_run_status") as f:
        status = f.read().strip()
    details = open("/tmp/pipeline_run.log", errors="replace").read()
    assert status == "1", f"Failed: python /home/user/pipeline.py did not complete successfully.\n{details}"


def test_pipeline_executed_required_simulation():
    audit = open("/tmp/oracle_audit.log", errors="replace").read()
    assert re.search(r"^call argc=1 arg1=500000$", audit, re.MULTILINE), \
        "Failed: pipeline did not execute /app/oracle_sim with the single argument 500000."
    assert re.search(r"^complete argc=1 arg1=500000 lines=500000$", audit, re.MULTILINE), \
        "Failed: the required 500000-particle simulation did not complete and emit 500000 lines."


def test_pipeline_used_scott_kde_and_numerical_integration():
    audit = open("/tmp/kde_audit.log", errors="replace").read()
    assert re.search(r"^construct n=500000 d=1 scott=1 ", audit, re.MULTILINE), \
        "Failed: no one-dimensional Gaussian KDE using Scott's bandwidth was constructed from 500000 samples."

    evaluations = []
    for count, low, high in re.findall(
        r"^evaluate count=(\d+) min=([^ ]+) max=([^ ]+)$", audit, re.MULTILINE
    ):
        evaluations.append((int(count), float(low), float(high)))
    assert evaluations, "Failed: the constructed KDE was never evaluated."
    total_points = sum(item[0] for item in evaluations)
    lowest = min(item[1] for item in evaluations)
    highest = max(item[2] for item in evaluations)
    assert total_points >= 20 and lowest <= 1.1 and highest >= 3.9, \
        "Failed: KDE evaluations do not exercise the numerical integration interval [1.0, 4.0]."


def test_integral_result():
    agent_file = "/home/user/integral_result.txt"

    # 1. Check if the output file exists
    assert os.path.exists(agent_file), f"Failed: Output file not found at {agent_file}"
    assert os.path.isfile(agent_file), f"Failed: Path {agent_file} is not a file."

    # 2. Read and parse the agent's output
    try:
        with open(agent_file, "r") as f:
            content = f.read().strip()
            agent_val = float(content)
    except ValueError:
        pytest.fail(f"Failed: Could not parse output file content '{content}' as a float.")
    except Exception as e:
        pytest.fail(f"Failed: Error reading output file: {e}")

    # 3. Compute the exact analytical target
    mu = 1.0
    sigma = 0.5
    dist = stats.lognorm(s=sigma, scale=np.exp(mu))

    def integrand(x):
        return dist.pdf(x) * (x**2) * np.cos(x)

    true_val, _ = integrate.quad(integrand, 1.0, 4.0)

    # 4. Compare with threshold
    absolute_error = abs(true_val - agent_val)
    tolerance = 0.05  # Allow some variance due to KDE approximations and random sampling

    assert absolute_error <= tolerance, (
        f"Failed: Error {absolute_error:.6f} exceeds tolerance {tolerance}.\n"
        f"Target value: {true_val:.6f}\n"
        f"Agent value:  {agent_val:.6f}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
