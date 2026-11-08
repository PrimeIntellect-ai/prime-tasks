#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import signal
import subprocess
import time
from pathlib import Path

import numpy as np
import requests
from PIL import Image, ImageDraw, ImageFont
from sklearn.datasets import make_classification
from sklearn.decomposition import PCA

SERVER_URL = "http://127.0.0.1:5000"
AUTH_HEADER = {"X-MLOps-Auth": "track-me"}
WRONG_AUTH_HEADER = {"X-MLOps-Auth": "wrong-auth"}
IMAGE_PATH = Path("/app/experiment_config.png")


def test_server_ready_file_exists():
    ready_file = "/home/user/server_ready.txt"
    assert os.path.exists(ready_file), f"The file {ready_file} was not created, indicating the server might not be ready."


def test_auth_failure():
    response = requests.get(f"{SERVER_URL}/config", headers=WRONG_AUTH_HEADER, timeout=5)
    assert response.status_code in (401, 403), f"Expected 401 or 403 for wrong auth, got {response.status_code}."

    response_no_auth = requests.get(f"{SERVER_URL}/config", timeout=5)
    assert response_no_auth.status_code in (401, 403), f"Expected 401 or 403 for missing auth, got {response_no_auth.status_code}."

    covariance_wrong = requests.get(f"{SERVER_URL}/covariance", headers=WRONG_AUTH_HEADER, timeout=5)
    assert covariance_wrong.status_code in (401, 403), "The auth header must also protect /covariance."
    covariance_missing = requests.get(f"{SERVER_URL}/covariance", timeout=5)
    assert covariance_missing.status_code in (401, 403), "Missing auth must also be rejected by /covariance."


def test_config_endpoint():
    response = requests.get(f"{SERVER_URL}/config", headers=AUTH_HEADER, timeout=5)
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}."

    data = response.json()
    assert "seed" in data, "Missing 'seed' in /config response."
    assert "target_variance" in data, "Missing 'target_variance' in /config response."
    assert "n_components" in data, "Missing 'n_components' in /config response."

    assert data["seed"] == 8128, f"Expected seed 8128, got {data['seed']}."
    assert abs(data["target_variance"] - 0.9) < 1e-4, f"Expected target_variance 0.9, got {data['target_variance']}."
    assert data["n_components"] == 32, f"Expected n_components 32, got {data['n_components']}."


def test_covariance_endpoint():
    response = requests.get(f"{SERVER_URL}/covariance", headers=AUTH_HEADER, timeout=5)
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}."

    data = response.json()
    for key in ["cov_00", "cov_01", "cov_10", "cov_11"]:
        assert key in data, f"Missing '{key}' in /covariance response."

    assert abs(data["cov_00"] - 13.9189) < 1e-3, f"Expected cov_00 ~13.9189, got {data['cov_00']}."
    assert abs(data["cov_01"]) < 1e-3, f"Expected cov_01 ~0.0, got {data['cov_01']}."
    assert abs(data["cov_10"]) < 1e-3, f"Expected cov_10 ~0.0, got {data['cov_10']}."
    assert abs(data["cov_11"] - 7.0427) < 1e-3, f"Expected cov_11 ~7.0427, got {data['cov_11']}."


def listener_pids(port=5000):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local_address, state = fields[1], fields[3]
            if state == "0A" and int(local_address.rsplit(":", 1)[1], 16) == port:
                inodes.add(fields[9])

    result = set()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    result.add(int(proc.name))
                    break
        except (OSError, PermissionError):
            continue
    return result


def read_process(pid):
    proc = Path(f"/proc/{pid}")
    argv = [part.decode(errors="surrogateescape") for part in (proc / "cmdline").read_bytes().split(b"\0") if part]
    cwd = os.readlink(proc / "cwd")
    env = os.environ.copy()
    for item in (proc / "environ").read_bytes().split(b"\0"):
        if b"=" in item:
            key, value = item.split(b"=", 1)
            env[key.decode(errors="surrogateescape")] = value.decode(errors="surrogateescape")
    return argv, cwd, env


def assert_python_artifact_exists(argv, cwd):
    candidates = []
    for arg in argv[1:]:
        raw = arg.split(":", 1)[0]
        path = Path(raw)
        if not path.is_absolute():
            path = Path(cwd) / path
        if path.suffix == ".py" and path.is_file():
            candidates.append(path)
        elif ":" in arg and raw and "/" not in raw:
            module_path = Path(cwd) / (raw.replace(".", "/") + ".py")
            if module_path.is_file():
                candidates.append(module_path)

    if "--app" in argv:
        index = argv.index("--app") + 1
        if index < len(argv):
            raw = argv[index].split(":", 1)[0]
            path = Path(raw)
            if not path.is_absolute():
                path = Path(cwd) / path
            if not path.suffix:
                path = path.with_suffix(".py")
            if path.is_file():
                candidates.append(path)

    if not candidates:
        candidates.extend(Path(cwd).glob("*.py"))
    assert candidates, "The running service is not backed by a written Python pipeline artifact."


def stop_server():
    deadline = time.time() + 10
    while time.time() < deadline:
        pids = listener_pids()
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        time.sleep(0.25)
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while listener_pids() and time.time() < deadline:
        time.sleep(0.1)
    assert not listener_pids(), "Could not stop the original service to re-execute its pipeline."


def wait_for_server(process, timeout=40):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        if process.poll() is not None:
            raise AssertionError(f"Pipeline exited while starting, with status {process.returncode}.")
        try:
            response = requests.get(f"{SERVER_URL}/config", headers=AUTH_HEADER, timeout=1)
            if response.status_code == 200:
                return response
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.25)
    raise AssertionError(f"Re-executed pipeline did not start its service: {last_error}")


def expected_metrics(seed, target):
    X, _ = make_classification(
        n_samples=1000,
        n_features=50,
        n_informative=30,
        random_state=seed,
    )
    pca = PCA()
    transformed = pca.fit_transform(X)
    cumulative = np.cumsum(pca.explained_variance_ratio_)
    n_components = int(np.searchsorted(cumulative, target, side="left") + 1)
    covariance = np.cov(transformed[:, :n_components], rowvar=False)
    return n_components, {
        "cov_00": round(float(covariance[0, 0]), 4),
        "cov_01": round(float(covariance[0, 1]), 4),
        "cov_10": round(float(covariance[1, 0]), 4),
        "cov_11": round(float(covariance[1, 1]), 4),
    }


def write_challenge_image(seed, target):
    image = Image.new("RGB", (760, 150), color="white")
    draw = ImageDraw.Draw(image)
    font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
    try:
        font = ImageFont.truetype(font_path, 30)
    except OSError:
        font = ImageFont.load_default()
    draw.text((20, 18), f"EXPERIMENT_SEED: {seed}", fill="black", font=font)
    draw.text((20, 82), f"TARGET_VARIANCE: {target:.2f}", fill="black", font=font)
    image.save(IMAGE_PATH)


def test_pipeline_reexecutes_from_unseen_image_values():
    pids = listener_pids()
    assert pids, "No process is listening on port 5000."
    pid = min(pids)
    argv, cwd, env = read_process(pid)
    assert argv, "Could not identify the command running the service."
    assert_python_artifact_exists(argv, cwd)

    rng = secrets.SystemRandom()
    seed = rng.choice([value for value in range(10000, 99999) if value != 8128])
    target = rng.choice([0.82, 0.84, 0.86, 0.88, 0.91, 0.93, 0.95])
    expected_n, expected_covariance = expected_metrics(seed, target)
    original_image = IMAGE_PATH.read_bytes()
    process = None
    log_file = open("/tmp/reexecuted_pipeline.log", "wb")

    try:
        write_challenge_image(seed, target)
        stop_server()
        process = subprocess.Popen(
            argv,
            cwd=cwd,
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=log_file,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        config_response = wait_for_server(process)
        config = config_response.json()
        assert config.get("seed") == seed, "Re-executed pipeline did not extract the unseen seed from the image."
        assert abs(float(config.get("target_variance")) - target) < 1e-6, "Re-executed pipeline did not extract the unseen target variance."
        assert config.get("n_components") == expected_n, "PCA component count was not recomputed for the unseen configuration."

        covariance_response = requests.get(f"{SERVER_URL}/covariance", headers=AUTH_HEADER, timeout=5)
        assert covariance_response.status_code == 200
        covariance = covariance_response.json()
        for key, expected in expected_covariance.items():
            assert key in covariance, f"Missing '{key}' after pipeline re-execution."
            assert abs(float(covariance[key]) - expected) < 5e-5, f"{key} was not recomputed from the unseen seed."
    finally:
        IMAGE_PATH.write_bytes(original_image)
        if process is not None and process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=5)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        log_file.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
