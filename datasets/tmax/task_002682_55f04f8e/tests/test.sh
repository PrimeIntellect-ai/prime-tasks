#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile
import urllib.request


def step(values, k=4):
    result = list(values)
    for i in range(1, len(values) - 1):
        delta = values[i - 1] - 2 * values[i] + values[i + 1]
        quotient = abs(delta) // k
        if delta < 0:
            quotient = -quotient
        result[i] = values[i] + quotient
    return result


def parse_ints(data):
    return [int(x) for x in data.split()]


def mesh_env():
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = "/app/libthermal:" + env.get("LD_LIBRARY_PATH", "")
    return env


def test_api_env_configured():
    env_path = "/app/services/api/.env"
    assert os.path.isfile(env_path), f"Missing {env_path}"
    with open(env_path, "r") as f:
        content = f.read()
    assert "REDIS_HOST=127.0.0.1" in content or "REDIS_HOST=localhost" in content, \
        "REDIS_HOST not configured correctly in .env"


def test_libthermal_compiled():
    so_path = "/app/libthermal/libthermal.so"
    assert os.path.isfile(so_path), f"Missing compiled library {so_path}"


def test_mesh_step_executable():
    source_path = "/app/mesh_step.c"
    exe_path = "/app/mesh_step"
    assert os.path.isfile(source_path), f"Missing source file {source_path}"
    assert os.path.isfile(exe_path), f"Missing executable {exe_path}"
    assert os.access(exe_path, os.X_OK), f"{exe_path} is not executable"

    dynamic = subprocess.run(
        ["readelf", "-d", exe_path], capture_output=True, text=True, env=mesh_env()
    )
    assert dynamic.returncode == 0, f"{exe_path} is not a valid dynamic executable"
    assert "libthermal.so" in dynamic.stdout, \
        f"{exe_path} is not linked against libthermal.so"


def test_fit_sh_executable():
    sh_path = "/app/fit.sh"
    assert os.path.isfile(sh_path), f"Missing script {sh_path}"
    assert os.access(sh_path, os.X_OK), f"{sh_path} is not executable"


def test_fuzz_equivalence():
    agent_path = "/app/mesh_step"
    assert os.path.isfile(agent_path), f"Agent executable missing at {agent_path}"

    env = mesh_env()
    random.seed(42)
    for _ in range(100):
        n = random.randint(5, 100)
        temps = [random.randint(0, 10000) for _ in range(n)]
        input_bytes = (f"{n}\n" + " ".join(map(str, temps)) + "\n").encode()
        expected = (" ".join(map(str, step(temps))) + "\n").encode()

        proc = subprocess.run(
            [agent_path], input=input_bytes, capture_output=True, env=env, timeout=5
        )
        assert proc.returncode == 0, f"Nonzero return code on input {input_bytes!r}: {proc.stderr!r}"
        assert proc.stdout == expected, \
            f"Output mismatch on input {input_bytes!r}\nExpected: {expected!r}\nActual: {proc.stdout!r}"


def test_fit_sh_execution():
    env = mesh_env()

    with urllib.request.urlopen("http://127.0.0.1:8080/init", timeout=5) as response:
        init_data = response.read().decode()
    initial = parse_ints(init_data)
    assert initial, "The API returned an empty initialization"
    n = initial[0]
    values = initial[1:]
    assert len(values) == n, "The API initialization does not contain N temperatures"

    subprocess.run(["redis-cli", "del", "final_mesh"], check=True, capture_output=True)

    trace_dir = tempfile.mkdtemp(prefix="mesh-trace-")
    real_path = "/app/mesh_step.verifier-real"
    agent_path = "/app/mesh_step"
    os.replace(agent_path, real_path)
    wrapper = f'''#!/bin/bash
set -o pipefail
trace={trace_dir!r}
count=$(cat "$trace/count" 2>/dev/null || echo 0)
count=$((count + 1))
printf '%s\n' "$count" > "$trace/count"
cat > "$trace/input.$count"
"{real_path}" < "$trace/input.$count" | tee "$trace/output.$count"
exit ${{PIPESTATUS[0]}}
'''
    try:
        with open(agent_path, "w") as f:
            f.write(wrapper)
        os.chmod(agent_path, 0o755)

        proc = subprocess.run(["/app/fit.sh"], capture_output=True, env=env, timeout=30)
        assert proc.returncode == 0, f"/app/fit.sh failed with error: {proc.stderr.decode(errors='replace')}"

        count_path = os.path.join(trace_dir, "count")
        assert os.path.isfile(count_path), "/app/fit.sh did not invoke /app/mesh_step"
        with open(count_path) as f:
            count = int(f.read().strip())
        assert count == 5, f"/app/fit.sh invoked /app/mesh_step {count} times instead of exactly 5"

        current = values
        for iteration in range(1, 6):
            with open(os.path.join(trace_dir, f"input.{iteration}")) as f:
                actual_input = parse_ints(f.read())
            assert actual_input == [n] + current, \
                f"Step {iteration} did not receive N followed by the previous step's mesh"

            current = step(current)
            with open(os.path.join(trace_dir, f"output.{iteration}")) as f:
                actual_output = parse_ints(f.read())
            assert actual_output == current, f"Incorrect output from mesh step {iteration}"

        redis_proc = subprocess.run(
            ["redis-cli", "get", "final_mesh"], capture_output=True, text=True
        )
        assert redis_proc.returncode == 0, "Failed to connect to redis"
        final_mesh = redis_proc.stdout.strip()
        assert final_mesh and final_mesh != "(nil)", "final_mesh key not found in Redis"
        assert parse_ints(final_mesh) == current, \
            "The submitted final_mesh is not the result of exactly five iterative steps"
        assert len(parse_ints(final_mesh)) == n, \
            "The submitted final_mesh must contain just the N temperatures"
    finally:
        if os.path.exists(real_path):
            if os.path.exists(agent_path):
                os.unlink(agent_path)
            os.replace(real_path, agent_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
