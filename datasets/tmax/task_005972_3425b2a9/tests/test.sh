#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import hashlib
import json
import base64
import io
import math
import pytest
import yaml
from PIL import Image, ImageFile

ImageFile.LOAD_TRUNCATED_IMAGES = True

RAW_ASSETS_DIR = "/home/user/project/raw_assets"
PROCESSED_DIR = "/home/user/project/processed_assets"
MANIFEST_PATH = "/home/user/project/manifest.csv"

EXPECTED_FILES = {
    "hero_banner.webp": "Hero Banner.jpg",
    "server_config.yaml": "Server-Config.json",
    "ui_settings.yaml": "UI Settings.json",
    "user_avatar_01.webp": "User-Avatar 01.PNG"
}

EXPECTED_RAW_BYTES = {
    "User-Avatar 01.PNG": base64.b64decode(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    ),
    "Hero Banner.jpg": base64.b64decode(
        "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA="
    ),
    "Server-Config.json": (
        b'{\n'
        b'  "host": "localhost",\n'
        b'  "port": 8080,\n'
        b'  "debug": true,\n'
        b'  "features": ["auth", "logging"]\n'
        b'}\n'
    ),
    "UI Settings.json": (
        b'{\n'
        b'  "theme": "dark",\n'
        b'  "animations": false\n'
        b'}\n'
    ),
}

IMAGE_SOURCES = {
    "hero_banner.webp": "Hero Banner.jpg",
    "user_avatar_01.webp": "User-Avatar 01.PNG",
}

YAML_SOURCES = {
    "server_config.yaml": "Server-Config.json",
    "ui_settings.yaml": "UI Settings.json",
}


def test_processed_directory_and_files():
    assert os.path.exists(PROCESSED_DIR), f"Processed directory missing: {PROCESSED_DIR}"
    assert os.path.isdir(PROCESSED_DIR), f"Not a directory: {PROCESSED_DIR}"

    actual_files = set(os.listdir(PROCESSED_DIR))
    expected_files = set(EXPECTED_FILES.keys())

    assert actual_files == expected_files, f"Expected files {expected_files}, but got {actual_files}"


def test_webp_format():
    for filename in ["hero_banner.webp", "user_avatar_01.webp"]:
        filepath = os.path.join(PROCESSED_DIR, filename)
        assert os.path.exists(filepath), f"Missing file: {filepath}"

        with open(filepath, "rb") as f:
            output_bytes = f.read()

        header = output_bytes[:12]
        assert len(header) >= 12, f"File too small to be WebP: {filename}"
        assert header[0:4] == b"RIFF", f"Missing RIFF header in {filename}"
        assert header[8:12] == b"WEBP", f"Missing WEBP signature in {filename}"

        with Image.open(io.BytesIO(output_bytes)) as probe:
            assert probe.format == "WEBP", f"Pillow did not recognize {filename} as WebP"
            probe.verify()

        with Image.open(io.BytesIO(output_bytes)) as processed_image:
            assert processed_image.format == "WEBP", f"Incorrect image format for {filename}"
            processed_image.load()
            processed_rgb = processed_image.convert("RGB")

        source_name = IMAGE_SOURCES[filename]
        with Image.open(io.BytesIO(EXPECTED_RAW_BYTES[source_name])) as source_image:
            source_image.load()
            source_rgb = source_image.convert("RGB")

        assert processed_rgb.size == source_rgb.size, (
            f"Image dimensions changed for {filename}: "
            f"expected {source_rgb.size}, got {processed_rgb.size}"
        )

        source_pixels = list(source_rgb.getdata())
        processed_pixels = list(processed_rgb.getdata())
        squared_error = sum(
            (actual - expected) ** 2
            for source_pixel, processed_pixel in zip(source_pixels, processed_pixels)
            for expected, actual in zip(source_pixel, processed_pixel)
        )
        rmse = math.sqrt(squared_error / (len(source_pixels) * 3))
        assert rmse <= 90, f"Converted image content differs excessively from source for {filename}: RMSE={rmse}"


def test_yaml_content():
    server_config_path = os.path.join(PROCESSED_DIR, "server_config.yaml")
    assert os.path.exists(server_config_path), f"Missing file: {server_config_path}"
    with open(server_config_path, "r") as f:
        content = f.read()
        assert "localhost" in content, "Missing 'localhost' in server_config.yaml"
        assert "8080" in content, "Missing '8080' in server_config.yaml"
        assert "auth" in content, "Missing 'auth' in server_config.yaml"
        assert "logging" in content, "Missing 'logging' in server_config.yaml"

    ui_settings_path = os.path.join(PROCESSED_DIR, "ui_settings.yaml")
    assert os.path.exists(ui_settings_path), f"Missing file: {ui_settings_path}"
    with open(ui_settings_path, "r") as f:
        content = f.read()
        assert "dark" in content, "Missing 'dark' in ui_settings.yaml"
        assert "false" in content.lower(), "Missing 'false' in ui_settings.yaml"

    for yaml_name, json_name in YAML_SOURCES.items():
        yaml_path = os.path.join(PROCESSED_DIR, yaml_name)
        with open(yaml_path, "r", encoding="utf-8") as f:
            converted_data = yaml.safe_load(f)
        source_data = json.loads(EXPECTED_RAW_BYTES[json_name].decode("utf-8"))
        assert converted_data == source_data, (
            f"YAML data in {yaml_name} does not match source JSON {json_name}"
        )


def test_manifest_exists_and_format():
    assert os.path.exists(MANIFEST_PATH), f"Manifest file missing: {MANIFEST_PATH}"

    with open(MANIFEST_PATH, "r", newline="") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "Manifest is empty"
    assert rows[0] == ["processed_filename", "original_filename", "sha256"], \
        f"Incorrect CSV header. Got: {rows[0]}"

    data_rows = rows[1:]
    assert len(data_rows) == 4, f"Expected 4 data rows, got {len(data_rows)}"

    processed_names = [row[0] for row in data_rows]
    assert processed_names == sorted(processed_names), "Manifest rows are not sorted alphabetically by processed_filename"

    for row in data_rows:
        assert len(row) == 3, f"Row does not have exactly 3 columns: {row}"
        p_file, o_file, file_hash = row

        assert p_file in EXPECTED_FILES, f"Unexpected processed filename in manifest: {p_file}"
        assert EXPECTED_FILES[p_file] == o_file, f"Incorrect original filename mapping for {p_file}. Expected {EXPECTED_FILES[p_file]}, got {o_file}"

        filepath = os.path.join(PROCESSED_DIR, p_file)
        assert os.path.exists(filepath), f"File referenced in manifest does not exist: {filepath}"

        with open(filepath, "rb") as f_img:
            actual_hash = hashlib.sha256(f_img.read()).hexdigest()

        assert actual_hash == file_hash, f"SHA256 hash mismatch for {p_file}. Expected {actual_hash}, got {file_hash}"


def test_raw_assets_unmodified():
    expected_raw_files = ["Hero Banner.jpg", "Server-Config.json", "UI Settings.json", "User-Avatar 01.PNG"]
    assert os.path.exists(RAW_ASSETS_DIR), f"Raw assets directory missing: {RAW_ASSETS_DIR}"

    actual_raw_files = os.listdir(RAW_ASSETS_DIR)
    for f in expected_raw_files:
        assert f in actual_raw_files, f"Original file missing from raw_assets: {f}"
        with open(os.path.join(RAW_ASSETS_DIR, f), "rb") as raw_file:
            actual_bytes = raw_file.read()
        assert actual_bytes == EXPECTED_RAW_BYTES[f], f"Original raw asset was modified: {f}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
