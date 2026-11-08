#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import random
import re

import pandas as pd
import pytest
import pytesseract
import requests
import torch
import torch.nn as nn
from PIL import Image

API_URL = "http://127.0.0.1:8080"
AUTH_HEADER = {"Authorization": "Bearer data_ops_2024"}
VALID_PAYLOAD = {
    "temperature": 25.0,
    "humidity": 50.0,
    "pressure": 1013.0,
}


class SimpleMLP(nn.Module):
    def __init__(self):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(3, 16),
            nn.ReLU(),
            nn.Linear(16, 8),
            nn.ReLU(),
            nn.Linear(8, 1),
        )

    def forward(self, x):
        return self.net(x)


@pytest.fixture(scope="session")
def reference_model():
    model = SimpleMLP()
    try:
        state_dict = torch.load(
            "/home/user/model/weights.pth", map_location="cpu", weights_only=True
        )
    except TypeError:
        state_dict = torch.load("/home/user/model/weights.pth", map_location="cpu")
    model.load_state_dict(state_dict)
    model.eval()
    return model


def get_expected_prediction(model, payload):
    with torch.no_grad():
        input_tensor = torch.tensor(
            [[payload["temperature"], payload["humidity"], payload["pressure"]]],
            dtype=torch.float32,
        )
        return model(input_tensor).item()


def derive_expected_stats():
    note = pytesseract.image_to_string(Image.open("/app/cleaning_rules.png"))
    note = note.replace("−", "-").replace("—", "-")

    upper_match = re.search(
        r"temperature\s*>\s*(-?\d+(?:\.\d+)?)", note, flags=re.IGNORECASE
    )
    lower_match = re.search(
        r"temperature\s*<\s*(-?\d+(?:\.\d+)?)", note, flags=re.IGNORECASE
    )
    impute_match = re.search(
        r"impute\s+missing\s+([A-Za-z_][A-Za-z0-9_]*)\s+with\s+(?:the\s+)?median",
        note,
        flags=re.IGNORECASE,
    )
    assert upper_match, f"Could not derive the upper temperature rule from note OCR: {note!r}"
    assert lower_match, f"Could not derive the lower temperature rule from note OCR: {note!r}"
    assert impute_match, f"Could not derive the imputation rule from note OCR: {note!r}"

    upper = float(upper_match.group(1))
    lower = float(lower_match.group(1))
    imputed_column = impute_match.group(1).lower()

    df = pd.read_csv("/home/user/data/raw_sensor_data.csv")
    columns_by_lower_name = {column.lower(): column for column in df.columns}
    assert imputed_column in columns_by_lower_name
    actual_imputed_column = columns_by_lower_name[imputed_column]

    temperature = pd.to_numeric(df[columns_by_lower_name["temperature"]], errors="coerce")
    outlier_mask = (temperature > upper) | (temperature < lower)
    retained = df.loc[~outlier_mask]

    return {
        "dropped_outliers": int(outlier_mask.sum()),
        "imputed_missing": int(retained[actual_imputed_column].isna().sum()),
    }


def request(method, path, **kwargs):
    try:
        return requests.request(method, f"{API_URL}{path}", timeout=3, **kwargs)
    except requests.exceptions.ConnectionError:
        pytest.fail("API server is not running on 127.0.0.1:8080.")


def assert_unauthorized(response):
    assert response.status_code in [401, 403], (
        f"Expected 401/403 for unauthorized request, got {response.status_code}."
    )


def test_api_unauthorized():
    """Ensure the stats API requires authentication."""
    assert_unauthorized(request("GET", "/stats"))


def test_predict_api_unauthorized():
    """Ensure prediction cannot be used without the required bearer token."""
    assert_unauthorized(request("POST", "/predict", json=VALID_PAYLOAD))
    assert_unauthorized(
        request(
            "POST",
            "/predict",
            headers={"Authorization": "Bearer wrong_token"},
            json=VALID_PAYLOAD,
        )
    )


def test_stats_rejects_wrong_token():
    assert_unauthorized(
        request("GET", "/stats", headers={"Authorization": "Bearer wrong_token"})
    )


def test_api_stats():
    """Check GET /stats against statistics derived from the supplied note and data."""
    response = request("GET", "/stats", headers=AUTH_HEADER)
    assert response.status_code == 200, (
        f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    )

    data = response.json()
    assert "dropped_outliers" in data, "Missing 'dropped_outliers' in /stats response."
    assert "imputed_missing" in data, "Missing 'imputed_missing' in /stats response."
    assert isinstance(data["dropped_outliers"], int) and not isinstance(
        data["dropped_outliers"], bool
    )
    assert isinstance(data["imputed_missing"], int) and not isinstance(
        data["imputed_missing"], bool
    )

    expected = derive_expected_stats()
    assert data["dropped_outliers"] == expected["dropped_outliers"], (
        f"Expected {expected['dropped_outliers']} dropped outliers, "
        f"got {data['dropped_outliers']}."
    )
    assert data["imputed_missing"] == expected["imputed_missing"], (
        f"Expected {expected['imputed_missing']} imputed missing values, "
        f"got {data['imputed_missing']}."
    )


def assert_prediction(payload, model):
    response = request("POST", "/predict", headers=AUTH_HEADER, json=payload)
    assert response.status_code == 200, (
        f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    )

    data = response.json()
    assert "prediction" in data, "Missing 'prediction' in /predict response."
    actual_pred = data["prediction"]
    assert isinstance(actual_pred, (int, float)) and not isinstance(actual_pred, bool)
    assert math.isfinite(float(actual_pred)), f"Prediction must be finite, got {actual_pred}."

    expected_pred = get_expected_prediction(model, payload)
    assert abs(actual_pred - expected_pred) < 1e-4, (
        f"Prediction mismatch for {payload}. Expected {expected_pred}, got {actual_pred}."
    )


def test_api_predict(reference_model):
    """Retain the original prediction assertion."""
    assert_prediction(VALID_PAYLOAD, reference_model)


def test_api_predict_general_inference(reference_model):
    """Exercise inference on unpredictable inputs derived at verification time."""
    rng = random.SystemRandom()
    payloads = [
        {
            "temperature": rng.uniform(-50.0, 140.0),
            "humidity": rng.uniform(1.0, 99.0),
            "pressure": rng.uniform(850.0, 1150.0),
        }
        for _ in range(8)
    ]
    for payload in payloads:
        assert_prediction(payload, reference_model)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
