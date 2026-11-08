#!/bin/bash
mkdir -p /logs/verifier

ORIG=/app/.sensor_model.verifier_orig
AUDIT=/tmp/sensor_model_invocations.log
instrumented=0
rm -f "$ORIG" "$AUDIT"

# Install a verification-time wrapper so requests must actually invoke the legacy model.
if [ -f /app/sensor_model ] && [ -x /app/sensor_model ] && [ "$(head -c 4 /app/sensor_model | od -An -tx1 | tr -d ' \n')" = "7f454c46" ]; then
    if mv /app/sensor_model "$ORIG"; then
        cat << 'WRAPPER_EOF' > /app/sensor_model
#!/bin/bash
printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> /tmp/sensor_model_invocations.log
exec /app/.sensor_model.verifier_orig "$@"
WRAPPER_EOF
        chmod 755 /app/sensor_model
        : > "$AUDIT"
        chmod 666 "$AUDIT"
        instrumented=1
    fi
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import socket
import subprocess
import pytest

ORIGINAL_MODEL = "/app/.sensor_model.verifier_orig"
AUDIT_LOG = "/tmp/sensor_model_invocations.log"


def assert_compiled_server_exists():
    path = "/home/user/ml_server"
    assert os.path.isfile(path), f"Compiled server is missing at {path}"
    assert os.access(path, os.X_OK), f"Compiled server is not executable: {path}"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Expected {path} to be a compiled ELF executable"


def simulate(dt, f0, damping):
    proc = subprocess.run(
        [ORIGINAL_MODEL, str(f0), str(damping), str(dt)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
        check=True,
    )
    t_vals = []
    y_vals = []
    for line in proc.stdout.splitlines():
        parts = line.split()
        assert len(parts) == 2, f"Malformed sensor_model output line: {line!r}"
        t_vals.append(float(parts[0]))
        y_vals.append(float(parts[1]))
    assert len(t_vals) >= 2, "sensor_model returned too few samples"

    energy = 0.0
    for i in range(1, len(t_vals)):
        dt_i = t_vals[i] - t_vals[i - 1]
        energy += 0.5 * (y_vals[i] ** 2 + y_vals[i - 1] ** 2) * dt_i
    return t_vals, y_vals, energy


def get_expected_values(f0, damping, target_error):
    dt = 0.1
    prev_energy = None
    attempted_dts = []

    for _ in range(16):
        attempted_dts.append(dt)
        t_vals, y_vals, energy = simulate(dt, f0, damping)
        if prev_energy is not None and abs(energy - prev_energy) < target_error:
            break
        prev_energy = energy
        dt /= 2.0
    else:
        pytest.fail("Reference convergence did not complete")

    n_samples = len(y_vals)
    max_mag = -1.0
    dominant_f = 0.0
    for k in range(1, (n_samples + 1) // 2):
        freq = k / (n_samples * dt)
        real = 0.0
        imag = 0.0
        for n, value in enumerate(y_vals):
            angle = -2.0 * math.pi * k * n / n_samples
            real += value * math.cos(angle)
            imag += value * math.sin(angle)
        mag = math.sqrt(real ** 2 + imag ** 2)
        if mag > max_mag:
            max_mag = mag
            dominant_f = freq

    return dt, energy, dominant_f, attempted_dts


def send_request(f0, damping, target_error):
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(15.0)
        s.connect(("127.0.0.1", 8888))
        req = f"ANALYZE {f0} {damping} {target_error}\n"
        s.sendall(req.encode("utf-8"))

        received = b""
        while b"\n" not in received:
            chunk = s.recv(1024)
            if not chunk:
                break
            received += chunk
        assert b"\n" in received, "Server response was not newline-terminated"

        # The service is required to close each client connection after responding.
        trailing = s.recv(1024)
        assert trailing == b"", "Server did not cleanly close the client connection"
        s.close()
        return received.decode("utf-8").strip()
    except AssertionError:
        raise
    except Exception as exc:
        pytest.fail(f"Failed to communicate with the server: {exc}")


def audit_line_count():
    with open(AUDIT_LOG, "r", encoding="utf-8") as f:
        return len(f.readlines())


def audit_lines_since(start):
    with open(AUDIT_LOG, "r", encoding="utf-8") as f:
        return [line.rstrip("\n") for line in f.readlines()[start:]]


_rng = secrets.SystemRandom()
CASES = []
while len(CASES) < 6:
    case = (
        round(_rng.uniform(0.65, 4.45), 4),
        round(_rng.uniform(0.07, 0.95), 4),
        round(_rng.uniform(0.0025, 0.0125), 5),
    )
    if case not in CASES:
        CASES.append(case)


@pytest.mark.parametrize("f0,damping,target_error", CASES)
def test_server_analysis(f0, damping, target_error):
    expected_dt, expected_energy, expected_freq, expected_dts = get_expected_values(
        f0, damping, target_error
    )

    audit_start = audit_line_count()
    response = send_request(f0, damping, target_error)

    parts = response.split()
    assert len(parts) == 4, f"Expected 4 parts in response, got: '{response}'"
    assert parts[0] == "RESULT", f"Expected response to start with RESULT, got: '{response}'"

    try:
        res_dt = float(parts[1])
        res_energy = float(parts[2])
        res_freq = float(parts[3])
    except ValueError:
        pytest.fail(f"Failed to parse numeric values from response: '{response}'")

    assert math.isclose(res_dt, expected_dt, rel_tol=1e-3), \
        f"Expected dt {expected_dt:.4f}, got {res_dt}"
    assert math.isclose(res_energy, expected_energy, rel_tol=1e-3), \
        f"Expected energy {expected_energy:.4f}, got {res_energy}"
    assert math.isclose(res_freq, expected_freq, rel_tol=1e-2), \
        f"Expected dominant freq {expected_freq:.4f}, got {res_freq}"

    expected_str = f"RESULT {expected_dt:.4f} {expected_energy:.4f} {expected_freq:.4f}"
    assert response == expected_str, \
        f"Response formatting incorrect. Expected '{expected_str}', got '{response}'"

    calls = audit_lines_since(audit_start)
    assert len(calls) == len(expected_dts), \
        f"Expected {len(expected_dts)} sensor_model executions, observed {len(calls)}"
    observed_dts = []
    for line in calls:
        fields = line.split("\t")
        assert len(fields) == 3, f"Malformed sensor_model invocation record: {line!r}"
        called_f0, called_damping, called_dt = map(float, fields)
        assert math.isclose(called_f0, f0, rel_tol=0.0, abs_tol=1e-12)
        assert math.isclose(called_damping, damping, rel_tol=0.0, abs_tol=1e-12)
        observed_dts.append(called_dt)
    assert len(observed_dts) == len(expected_dts)
    for observed, expected in zip(observed_dts, expected_dts):
        assert math.isclose(observed, expected, rel_tol=0.0, abs_tol=1e-12), \
            f"Expected sensor_model dt sequence {expected_dts}, got {observed_dts}"


def test_compiled_artifact():
    assert_compiled_server_exists()
TEST_EOF

status=1
if [ "$instrumented" -eq 1 ]; then
    if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
        status=0
    fi
fi

# Restore the legacy binary after verification.
if [ "$instrumented" -eq 1 ]; then
    rm -f /app/sensor_model
    mv "$ORIG" /app/sensor_model
fi
rm -f "$AUDIT"

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
