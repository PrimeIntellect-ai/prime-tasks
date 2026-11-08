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
import ast
import importlib.util
import os

import cv2
import numpy as np
import pandas as pd
import pytest
import requests
import torch
import torch.nn as nn

BASE_URL = "http://127.0.0.1:8000"


class SimpleEncoder(nn.Module):
    def __init__(self):
        super().__init__()
        self.conv1 = nn.Conv2d(3, 16, 3, 2, 1)
        self.relu = nn.ReLU()
        self.conv2 = nn.Conv2d(16, 32, 3, 2, 1)
        self.flatten = nn.Flatten()
        self.fc1 = nn.Linear(32 * 16 * 16, 16)
        self.fc2 = nn.Linear(16, 4)

    def forward(self, x):
        x = self.relu(self.conv1(x))
        x = self.relu(self.conv2(x))
        x = self.flatten(x)
        x = self.relu(self.fc1(x))
        return self.fc2(x)


def get_json(path):
    try:
        resp = requests.get(f"{BASE_URL}{path}", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {path}: {e}")
    assert resp.status_code == 200, f"Expected 200 OK from {path}, got {resp.status_code}. Response: {resp.text}"
    try:
        return resp.json()
    except ValueError:
        pytest.fail(f"Response from {path} is not valid JSON: {resp.text}")


@pytest.fixture(scope="session")
def reference():
    sensors = pd.read_csv("/app/sensor_logs.csv").sort_values("time_sec")
    times = [int(x) for x in sensors["time_sec"].tolist()]

    cap = cv2.VideoCapture("/app/traffic.mp4")
    assert cap.isOpened(), "Could not open /app/traffic.mp4"
    fps = cap.get(cv2.CAP_PROP_FPS)
    assert fps > 0
    wanted = {int(round(t * fps)): t for t in times}
    frames = {}
    index = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        if index in wanted:
            frames[wanted[index]] = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        index += 1
    cap.release()
    assert set(frames) == set(times), f"Could not extract all 1-fps frames; found {sorted(frames)}"

    model = SimpleEncoder()
    try:
        state = torch.load("/app/embedding_model.pth", map_location="cpu", weights_only=True)
    except TypeError:
        state = torch.load("/app/embedding_model.pth", map_location="cpu")
    model.load_state_dict(state)
    model.eval()

    candidates = {t: [] for t in times}
    interpolation_modes = [cv2.INTER_LINEAR, cv2.INTER_AREA, cv2.INTER_CUBIC]
    try:
        from PIL import Image
        pil_modes = [Image.Resampling.BILINEAR, Image.Resampling.BICUBIC, Image.Resampling.LANCZOS]
    except (ImportError, AttributeError):
        Image = None
        pil_modes = []

    with torch.no_grad():
        for t in times:
            images = [cv2.resize(frames[t], (64, 64), interpolation=m) for m in interpolation_modes]
            if Image is not None:
                pil = Image.fromarray(frames[t])
                images.extend(np.asarray(pil.resize((64, 64), resample=m)) for m in pil_modes)
            for image in images:
                tensor = torch.from_numpy(np.ascontiguousarray(image)).permute(2, 0, 1).float().div(255.0).unsqueeze(0)
                candidates[t].append(model(tensor)[0].cpu().numpy().astype(float))

    return sensors, times, candidates


@pytest.fixture(scope="session")
def service_rows(reference):
    sensors, times, candidates = reference
    rows = {}
    sensor_by_time = sensors.set_index("time_sec")
    for t in times:
        data = get_json(f"/data?time_sec={t}")
        assert "embedding" in data, f"Missing 'embedding' key for timestamp {t}: {data}"
        assert isinstance(data["embedding"], list), "Embedding should be a list"
        assert len(data["embedding"]) == 4, f"Expected 4-dimensional embedding at {t}"
        embedding = np.asarray(data["embedding"], dtype=float)
        assert np.isfinite(embedding).all(), f"Non-finite embedding at timestamp {t}"
        errors = [np.max(np.abs(embedding - candidate)) for candidate in candidates[t]]
        assert min(errors) < 4e-3, f"Embedding at timestamp {t} does not match model inference (best max error {min(errors)})"

        expected_sensor = sensor_by_time.loc[t]
        for key in ("temperature", "humidity", "luminosity"):
            assert key in data, f"Missing '{key}' for timestamp {t}: {data}"
            assert abs(float(data[key]) - float(expected_sensor[key])) < 1e-5, f"Wrong {key} at timestamp {t}"
        rows[t] = data
    return rows


def test_health():
    try:
        resp = requests.get(f"{BASE_URL}/health", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to /health endpoint: {e}")

    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}. Response: {resp.text}"
    try:
        data = resp.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {resp.text}")
    assert data.get("status") == "ok", f"Unexpected response: {data}"


def test_similar_0():
    try:
        resp = requests.get(f"{BASE_URL}/similar?time_sec=0", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to /similar endpoint: {e}")

    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}. Response: {resp.text}"
    try:
        data = resp.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {resp.text}")

    assert "similar_frames" in data, f"Missing 'similar_frames' key in {data}"
    assert isinstance(data["similar_frames"], list), f"'similar_frames' must be a list, got {type(data['similar_frames'])}"
    assert len(data["similar_frames"]) == 3, f"Expected 3 similar frames, got {len(data['similar_frames'])}"
    assert 0 not in data["similar_frames"], "The queried frame (0) should be excluded from results"


def test_similar_5():
    try:
        resp = requests.get(f"{BASE_URL}/similar?time_sec=5", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to /similar endpoint: {e}")

    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}. Response: {resp.text}"
    try:
        data = resp.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {resp.text}")

    assert "similar_frames" in data, f"Missing 'similar_frames' key in {data}"
    assert isinstance(data["similar_frames"], list), f"'similar_frames' must be a list, got {type(data['similar_frames'])}"
    assert len(data["similar_frames"]) == 3, f"Expected 3 similar frames, got {len(data['similar_frames'])}"
    assert 5 not in data["similar_frames"], "The queried frame (5) should be excluded from results"


def test_plot():
    try:
        resp = requests.get(f"{BASE_URL}/plot", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to /plot endpoint: {e}")

    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}. Response: {resp.text[:100]}"
    content_type = resp.headers.get("Content-Type", "")
    assert content_type.startswith("image/png"), f"Expected image/png content type, got {content_type}"
    assert len(resp.content) > 0, "Empty image content returned from /plot"


def test_data_3():
    try:
        resp = requests.get(f"{BASE_URL}/data?time_sec=3", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to /data endpoint: {e}")

    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}. Response: {resp.text}"
    try:
        data = resp.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {resp.text}")

    assert "embedding" in data, f"Missing 'embedding' key in {data}"
    assert isinstance(data["embedding"], list), "Embedding should be a list"
    assert len(data["embedding"]) == 4, f"Expected 4-dimensional embedding, got {len(data['embedding'])}"

    assert "temperature" in data, f"Missing 'temperature' in {data}"
    assert "humidity" in data, f"Missing 'humidity' in {data}"
    assert "luminosity" in data, f"Missing 'luminosity' in {data}"

    assert abs(data["temperature"] - 22.4) < 1e-5, f"Expected temperature 22.4, got {data['temperature']}"
    assert abs(data["humidity"] - 45.3) < 1e-5, f"Expected humidity 45.3, got {data['humidity']}"
    assert abs(data["luminosity"] - 210.0) < 1e-5, f"Expected luminosity 210.0, got {data['luminosity']}"


def test_plot_file_exists():
    path = "/app/output/correlation_heatmap.png"
    assert os.path.isfile(path), f"Missing plot file: {path}. The script should have saved it to this location."
    assert os.path.getsize(path) > 0, f"Plot file {path} is empty."


def test_all_joined_rows_match_inference(service_rows):
    assert len(service_rows) == 10


def test_cosine_similarity_for_every_timestamp(service_rows):
    times = sorted(service_rows)
    matrix = np.asarray([service_rows[t]["embedding"] for t in times], dtype=float)
    norms = np.linalg.norm(matrix, axis=1)
    assert np.all(norms > 0), "Cosine similarity is undefined for a zero embedding"
    similarities = matrix @ matrix.T / np.outer(norms, norms)

    for i, t in enumerate(times):
        expected = sorted((j for j in range(len(times)) if j != i), key=lambda j: (-similarities[i, j], times[j]))[:3]
        expected_times = [times[j] for j in expected]
        data = get_json(f"/similar?time_sec={t}")
        assert "similar_frames" in data
        actual = data["similar_frames"]
        assert isinstance(actual, list)
        assert len(actual) == 3
        assert all(isinstance(x, int) and not isinstance(x, bool) for x in actual)
        assert actual == expected_times, f"Incorrect cosine-nearest neighbors for {t}: expected {expected_times}, got {actual}"


def test_fixed_plotting_script_and_heatmap(service_rows):
    script_path = "/app/plot_correlations.py"
    assert os.path.isfile(script_path), f"Missing plotting script: {script_path}"
    source = open(script_path, "r", encoding="utf-8").read()
    tree = ast.parse(source, filename=script_path)
    explicit_agg = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr in ("use", "switch_backend"):
            if node.args and isinstance(node.args[0], ast.Constant) and str(node.args[0].value).lower() == "agg":
                explicit_agg = True
    if "MPLBACKEND" in source and "Agg" in source:
        explicit_agg = True
    assert explicit_agg, "plot_correlations.py does not explicitly configure the headless Agg backend"

    times = sorted(service_rows)
    joined = pd.DataFrame([
        {
            "embedding_0": service_rows[t]["embedding"][0],
            "embedding_1": service_rows[t]["embedding"][1],
            "embedding_2": service_rows[t]["embedding"][2],
            "embedding_3": service_rows[t]["embedding"][3],
            "temperature": service_rows[t]["temperature"],
            "humidity": service_rows[t]["humidity"],
            "luminosity": service_rows[t]["luminosity"],
        }
        for t in times
    ])
    expected_corr = joined.corr(method="pearson")

    spec = importlib.util.spec_from_file_location("agent_plot_correlations", script_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, "plot_heatmap") and callable(module.plot_heatmap)

    captured = []
    original_heatmap = module.sns.heatmap
    def checked_heatmap(data, *args, **kwargs):
        captured.append(data.copy() if hasattr(data, "copy") else np.asarray(data).copy())
        return original_heatmap(data, *args, **kwargs)
    module.sns.heatmap = checked_heatmap

    output_path = "/app/output/correlation_heatmap.png"
    if os.path.exists(output_path):
        os.remove(output_path)
    module.plot_heatmap(joined)
    assert captured, "plot_heatmap did not render a seaborn heatmap"
    actual_corr = captured[0]
    assert isinstance(actual_corr, pd.DataFrame), "Heatmap must be rendered from the correlation matrix"
    pd.testing.assert_frame_equal(actual_corr, expected_corr, check_exact=False, atol=1e-7, rtol=1e-7)
    assert os.path.isfile(output_path) and os.path.getsize(output_path) > 0

    raw = open(output_path, "rb").read()
    assert raw.startswith(b"\x89PNG\r\n\x1a\n"), "Plot file is not a PNG"
    decoded = cv2.imdecode(np.frombuffer(raw, dtype=np.uint8), cv2.IMREAD_COLOR)
    assert decoded is not None, "Plot file is not a decodable image"
    assert decoded.shape[0] >= 100 and decoded.shape[1] >= 100, "Heatmap image is unexpectedly small"
    assert float(decoded.std()) > 5.0, "Heatmap image appears blank"
    assert np.mean(np.all(decoded > 250, axis=2)) < 0.98, "Heatmap image is almost entirely blank"

    resp = requests.get(f"{BASE_URL}/plot", timeout=5)
    assert resp.status_code == 200
    assert resp.headers.get("Content-Type", "").startswith("image/png")
    assert resp.content == raw, "/plot did not serve the generated correlation heatmap file"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
