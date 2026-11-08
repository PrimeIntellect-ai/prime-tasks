#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import re

import numpy as np
import pandas as pd
import pytesseract
import pytest
import requests
from PIL import Image
from scipy.stats import ttest_1samp
from sklearn.decomposition import PCA


def extract_mapping():
    image = Image.open('/app/sensor_metadata.png').convert('RGB')
    images = [image, image.resize((image.width * 4, image.height * 4))]
    attempts = []

    for candidate in images:
        for config in ('--psm 6', '--psm 4'):
            text = pytesseract.image_to_string(candidate, config=config)
            attempts.append(text)
            mapping = {}
            for line in text.splitlines():
                match = re.match(r'^\s*([0-9]+)\s*[^A-Za-z0-9]*\s*(.*?)\s*$', line)
                if not match:
                    continue
                sensor_id = int(match.group(1))
                normalized = re.sub(r'[^a-z]', '', match.group(2).lower())
                if 'northwing' in normalized:
                    mapping[sensor_id] = 'North_Wing'
                elif 'southwing' in normalized:
                    mapping[sensor_id] = 'South_Wing'
            if mapping == {1: 'North_Wing', 2: 'North_Wing', 3: 'South_Wing', 4: 'South_Wing'}:
                return mapping

    pytest.fail('Could not recover the sensor metadata mapping from the image. OCR output: ' + repr(attempts))


def compute_expected(location):
    mapping = extract_mapping()
    readings = pd.read_csv('/app/sensor_readings.csv')
    metadata = pd.DataFrame(sorted(mapping.items()), columns=['sensor_id', 'location'])
    joined = readings.merge(metadata, on='sensor_id', how='inner')
    selected = joined.loc[joined['location'] == location]
    assert not selected.empty, f'No source rows found for {location}'

    features = selected[['temp', 'pressure', 'vibration']].to_numpy()
    pca_value = PCA(n_components=1).fit(features).explained_variance_ratio_[0]

    output = selected['output_metric'].to_numpy()
    rng = np.random.RandomState(42)
    bootstrap_means = rng.choice(output, size=(1000, len(output)), replace=True).mean(axis=1)
    ci_low, ci_high = np.percentile(bootstrap_means, [2.5, 97.5])
    p_value = ttest_1samp(output, popmean=50.0).pvalue

    return {
        'location': location,
        'pca_explained_variance': round(float(pca_value), 3),
        'bootstrap_ci_95': [round(float(ci_low), 3), round(float(ci_high), 3)],
        'ttest_p_value': round(float(p_value), 3),
    }


def test_api_north_wing():
    """Verify the API response for North_Wing."""
    url = "http://127.0.0.1:8000/api/v1/sensor_stats?location=North_Wing"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API at {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")

    assert "location" in data, "Missing 'location' in response"
    assert data["location"] == "North_Wing", f"Expected location 'North_Wing', got {data['location']}"

    assert "pca_explained_variance" in data, "Missing 'pca_explained_variance' in response"
    assert isinstance(data["pca_explained_variance"], (int, float)), "pca_explained_variance must be a number"
    assert 0.0 <= data["pca_explained_variance"] <= 1.0, f"pca_explained_variance should be between 0 and 1, got {data['pca_explained_variance']}"

    assert "bootstrap_ci_95" in data, "Missing 'bootstrap_ci_95' in response"
    assert isinstance(data["bootstrap_ci_95"], list) and len(data["bootstrap_ci_95"]) == 2, "bootstrap_ci_95 must be a list of 2 numbers"
    assert data["bootstrap_ci_95"][0] < data["bootstrap_ci_95"][1], "bootstrap_ci_95 lower bound must be less than upper bound"

    assert "ttest_p_value" in data, "Missing 'ttest_p_value' in response"
    assert isinstance(data["ttest_p_value"], (int, float)), "ttest_p_value must be a number"
    assert 0.0 <= data["ttest_p_value"] <= 1.0, f"ttest_p_value should be between 0 and 1, got {data['ttest_p_value']}"

    expected = compute_expected('North_Wing')
    assert data["pca_explained_variance"] == expected["pca_explained_variance"], f"Incorrect PCA result: expected {expected['pca_explained_variance']}, got {data['pca_explained_variance']}"
    assert data["bootstrap_ci_95"] == expected["bootstrap_ci_95"], f"Incorrect bootstrap CI: expected {expected['bootstrap_ci_95']}, got {data['bootstrap_ci_95']}"
    assert data["ttest_p_value"] == expected["ttest_p_value"], f"Incorrect t-test p-value: expected {expected['ttest_p_value']}, got {data['ttest_p_value']}"


def test_api_south_wing():
    """Verify the API response for South_Wing."""
    url = "http://127.0.0.1:8000/api/v1/sensor_stats?location=South_Wing"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API at {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")

    assert "location" in data, "Missing 'location' in response"
    assert data["location"] == "South_Wing", f"Expected location 'South_Wing', got {data['location']}"

    assert "pca_explained_variance" in data, "Missing 'pca_explained_variance' in response"
    assert isinstance(data["pca_explained_variance"], (int, float)), "pca_explained_variance must be a number"
    assert 0.0 <= data["pca_explained_variance"] <= 1.0, f"pca_explained_variance should be between 0 and 1, got {data['pca_explained_variance']}"

    assert "bootstrap_ci_95" in data, "Missing 'bootstrap_ci_95' in response"
    assert isinstance(data["bootstrap_ci_95"], list) and len(data["bootstrap_ci_95"]) == 2, "bootstrap_ci_95 must be a list of 2 numbers"
    assert data["bootstrap_ci_95"][0] < data["bootstrap_ci_95"][1], "bootstrap_ci_95 lower bound must be less than upper bound"

    assert "ttest_p_value" in data, "Missing 'ttest_p_value' in response"
    assert isinstance(data["ttest_p_value"], (int, float)), "ttest_p_value must be a number"
    assert 0.0 <= data["ttest_p_value"] <= 1.0, f"ttest_p_value should be between 0 and 1, got {data['ttest_p_value']}"

    expected = compute_expected('South_Wing')
    assert data["pca_explained_variance"] == expected["pca_explained_variance"], f"Incorrect PCA result: expected {expected['pca_explained_variance']}, got {data['pca_explained_variance']}"
    assert data["bootstrap_ci_95"] == expected["bootstrap_ci_95"], f"Incorrect bootstrap CI: expected {expected['bootstrap_ci_95']}, got {data['bootstrap_ci_95']}"
    assert data["ttest_p_value"] == expected["ttest_p_value"], f"Incorrect t-test p-value: expected {expected['ttest_p_value']}, got {data['ttest_p_value']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
