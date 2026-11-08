#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import re
import signal
import stat
import subprocess
import time
import urllib.request

ROOT = "/home/user/mobile_build"


def run(args, **kwargs):
    return subprocess.run(args, capture_output=True, text=True, **kwargs)


def test_conflict_txt():
    path = os.path.join(ROOT, "conflict.txt")
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 1, f"Expected exactly one symbol in conflict.txt, found {len(lines)}."
    assert lines[0] == "calculate_metric", f"Expected 'calculate_metric' in conflict.txt, got '{lines[0]}'."


def test_build_and_app_output():
    build_script = os.path.join(ROOT, "build.sh")
    assert os.path.isfile(build_script), f"File {build_script} does not exist."

    map_path = os.path.join(ROOT, "beta.map")
    assert os.path.isfile(map_path), "beta.map does not exist."
    with open(map_path, "r") as f:
        map_text = f.read()
    assert "calculate_metric" in map_text, "beta.map does not mention calculate_metric."
    assert "beta_specific_math" in map_text, "beta.map does not mention beta_specific_math."
    assert re.search(r"\blocal\s*:", map_text), "beta.map has no local section."
    assert re.search(r"\bglobal\s*:", map_text), "beta.map has no global section."

    with open(build_script, "r") as f:
        build_text = f.read()
    assert "beta.map" in build_text, "build.sh does not use the required beta.map file."
    assert "version-script" in build_text, "build.sh does not pass beta.map as a linker version script."

    for name in ("app", "libmath_alpha.so", "libmath_beta.so"):
        try:
            os.remove(os.path.join(ROOT, name))
        except FileNotFoundError:
            pass

    res = run(["bash", "build.sh"], cwd=ROOT)
    assert res.returncode == 0, f"build.sh failed to execute. stderr: {res.stderr}"

    app_path = os.path.join(ROOT, "app")
    assert os.path.isfile(app_path), f"File {app_path} was not created by build.sh."
    with open(app_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "app is not an ELF executable produced by the build."
    assert os.stat(app_path).st_mode & stat.S_IXUSR, "app is not executable."

    res_app = run(["./app"], cwd=ROOT)
    assert res_app.returncode == 0, f"./app failed to execute. stderr: {res_app.stderr}"
    assert res_app.stdout.strip() == "10", f"Expected app output to be '10', got '{res_app.stdout.strip()}'."

    dynamic = run(["readelf", "-d", app_path])
    assert dynamic.returncode == 0, f"Failed to inspect app: {dynamic.stderr}"
    assert re.search(r"NEEDED.*\[libmath_alpha\.so\]", dynamic.stdout), "app is not dynamically linked to libmath_alpha.so."
    assert re.search(r"NEEDED.*\[libmath_beta\.so\]", dynamic.stdout), "app is not dynamically linked to libmath_beta.so."
    assert re.search(r"(?:RPATH|RUNPATH).*\[\.\]", dynamic.stdout), "app does not have the required current-directory runtime library path."

    app_symbols = run(["nm", "-D", app_path])
    assert app_symbols.returncode == 0, "Failed to inspect app dynamic symbols."
    assert re.search(r"\bU\s+calculate_metric(?:@\S+)?$", app_symbols.stdout, re.MULTILINE), "app does not dynamically call calculate_metric."

    preload_src = "/tmp/verifier_metric.c"
    preload_so = "/tmp/verifier_metric.so"
    with open(preload_src, "w") as f:
        f.write("int calculate_metric(int input) { (void)input; return 731; }\n")
    built = run(["gcc", "-shared", "-fPIC", "-o", preload_so, preload_src])
    assert built.returncode == 0, f"Failed to build preload probe: {built.stderr}"
    env = os.environ.copy()
    env["LD_PRELOAD"] = preload_so
    probed = run(["./app"], cwd=ROOT, env=env)
    assert probed.returncode == 0, f"app failed with symbol probe: {probed.stderr}"
    assert probed.stdout.strip() == "731", "app output is hardcoded instead of coming from its calculate_metric call."


def test_shared_library_symbols():
    alpha_path = os.path.join(ROOT, "libmath_alpha.so")
    beta_path = os.path.join(ROOT, "libmath_beta.so")
    for path in (alpha_path, beta_path):
        assert os.path.isfile(path), f"File {path} does not exist."
        with open(path, "rb") as f:
            assert f.read(4) == b"\x7fELF", f"{path} is not an ELF shared library."

    res = run(["nm", "-D", "--defined-only", beta_path])
    assert res.returncode == 0, "Failed to run nm on libmath_beta.so"
    beta_names = [line.split()[-1].split("@")[0] for line in res.stdout.splitlines() if line.split()]
    assert "calculate_metric" not in beta_names, "calculate_metric is still exported dynamically in libmath_beta.so. The ABI was not properly managed."
    assert "beta_specific_math" in beta_names, "beta_specific_math is not globally exported by libmath_beta.so."

    symbols = run(["readelf", "-Ws", beta_path])
    assert symbols.returncode == 0, "Failed to inspect libmath_beta.so symbol visibility."
    assert re.search(r"\bLOCAL\b.*\bcalculate_metric$", symbols.stdout, re.MULTILINE), "calculate_metric was not retained as a local symbol in libmath_beta.so."
    assert re.search(r"\bGLOBAL\b.*\bDEFAULT\b.*\bbeta_specific_math(?:@\S+)?$", symbols.stdout, re.MULTILINE), "beta_specific_math is not a global default-visibility symbol."

    alpha = ctypes.CDLL(alpha_path)
    alpha.calculate_metric.argtypes = [ctypes.c_int]
    alpha.calculate_metric.restype = ctypes.c_int
    for value in (-7, 0, 11):
        assert alpha.calculate_metric(value) == value * 2, "libmath_alpha.so does not implement calculate_metric correctly."

    beta = ctypes.CDLL(beta_path)
    beta.beta_specific_math.argtypes = []
    beta.beta_specific_math.restype = ctypes.c_int
    assert beta.beta_specific_math() == 42, "libmath_beta.so does not implement beta_specific_math correctly."


def test_api_response():
    api_script = os.path.join(ROOT, "api.sh")
    assert os.path.isfile(api_script), f"File {api_script} does not exist."

    app_path = os.path.join(ROOT, "app")
    saved_app = os.path.join(ROOT, ".app.verifier_saved")
    subprocess.run(["pkill", "-f", "api.sh"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-x", "nc"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.3)

    os.replace(app_path, saved_app)

    def install_probe(value):
        with open(app_path, "w") as f:
            f.write(f"#!/bin/sh\nprintf '%s\\n' '{value}'\n")
        os.chmod(app_path, 0o755)

    def fetch_api():
        req = urllib.request.Request("http://localhost:8080/api/math/result")
        with urllib.request.urlopen(req, timeout=2) as response:
            assert response.status == 200, f"Expected HTTP 200, got {response.status}."
            return response.read().decode("utf-8")

    proc = None
    try:
        first = 48137
        second = 59243
        install_probe(first)
        proc = subprocess.Popen(
            ["bash", "api.sh"], cwd=ROOT,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True,
        )

        body = None
        last_error = None
        for _ in range(20):
            try:
                body = fetch_api()
                break
            except Exception as e:
                last_error = e
                time.sleep(0.15)
        assert body is not None, f"Failed to connect to API or read response: {last_error}"
        data = json.loads(body)
        assert data.get("status") == "success", f"Expected status 'success', got {data.get('status')}"
        assert data.get("result") == first, "api.sh did not execute ./app to obtain the response value."
        assert proc.poll() is None, "api.sh did not continue running after the first request."

        install_probe(second)
        body2 = fetch_api()
        data2 = json.loads(body2)
        assert data2.get("status") == "success", f"Expected status 'success', got {data2.get('status')}"
        assert data2.get("result") == second, "api.sh cached or hardcoded the result instead of executing ./app for each request."
        assert proc.poll() is None, "api.sh did not run continuously."
    finally:
        if proc is not None and proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
                proc.wait(timeout=2)
            except Exception:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except Exception:
                    pass
        try:
            os.remove(app_path)
        except FileNotFoundError:
            pass
        if os.path.exists(saved_app):
            os.replace(saved_app, app_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
