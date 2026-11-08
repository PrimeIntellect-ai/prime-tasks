#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_pipeline.py
import csv
import json
import os
import pathlib
import random
import shutil
import subprocess
import tempfile
import uuid

import cv2
import numpy as np

CSV_PATH = "/home/user/raw_loc_requests.csv"
VIDEO_PATH = "/app/ui_test.mp4"
OUTPUT_PATH = "/home/user/loc_summary.json"


def find_and_compile_pipeline():
    sources = []
    for root in ("/home/user", "/app"):
        sources.extend(pathlib.Path(root).rglob("*.cpp"))
    sources = sorted(set(sources), key=lambda p: (p.name != "pipeline.cpp", str(p)))
    assert sources, "No C++ source file was found under /home/user or /app."

    build_dir = tempfile.mkdtemp(prefix="verify_build_")
    binary = os.path.join(build_dir, "pipeline")
    attempts = []

    for source in sources:
        groups = [[source]]
        siblings = sorted(source.parent.glob("*.cpp"))
        if len(siblings) > 1:
            groups.append(siblings)
        for group in groups:
            command = ["g++", "-std=c++17", "-O2", *map(str, group), "-o", binary]
            result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            if result.returncode == 0:
                return binary, str(source.parent)
            attempts.append(result.stderr)

    raise AssertionError("The submitted C++ pipeline did not compile with g++ -std=c++17.\n" + "\n".join(attempts[-3:]))


def write_csv(rows):
    os.makedirs(os.path.dirname(CSV_PATH), exist_ok=True)
    with open(CSV_PATH, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["timestamp_ms", "screen_id", "loc_key", "english_source", "lang_target", "translation"])
        writer.writerows(rows)


def write_original_video():
    os.makedirs(os.path.dirname(VIDEO_PATH), exist_ok=True)
    if os.path.exists(VIDEO_PATH):
        os.unlink(VIDEO_PATH)
    out = cv2.VideoWriter(VIDEO_PATH, cv2.VideoWriter_fourcc(*"mp4v"), 10, (320, 240))
    assert out.isOpened(), "Could not create the original video fixture."
    for i in range(50):
        frame = np.full((240, 320, 3), 50, dtype=np.uint8)
        frame[0:10, 0:10] = 255 if i in {5, 15, 25, 40} else 0
        out.write(frame)
    out.release()


def write_lossless_video(trigger_frames, frame_count):
    os.makedirs(os.path.dirname(VIDEO_PATH), exist_ok=True)
    if os.path.exists(VIDEO_PATH):
        os.unlink(VIDEO_PATH)
    command = [
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-f", "rawvideo", "-pixel_format", "rgb24", "-video_size", "320x240",
        "-framerate", "10", "-i", "-", "-an", "-c:v", "libx264rgb",
        "-crf", "0", "-preset", "ultrafast", "-pix_fmt", "rgb24", VIDEO_PATH,
    ]
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    for i in range(frame_count):
        frame = np.full((240, 320, 3), 50, dtype=np.uint8)
        frame[0:10, 0:10] = 255 if i in trigger_frames else 0
        process.stdin.write(frame.tobytes())
    process.stdin.close()
    stderr = process.stderr.read()
    return_code = process.wait()
    assert return_code == 0, f"Could not create verification video: {stderr.decode(errors='replace')}"


def derive_expected():
    expected_screens = {}
    assert os.path.isfile(CSV_PATH), "CSV fixture disappeared before verification."
    with open(CSV_PATH, "r", newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if not row["translation"] or row["translation"] == "MISSING":
                continue
            screen = row["screen_id"]
            if screen not in expected_screens:
                expected_screens[screen] = {"keys": set(), "langs": set()}
            expected_screens[screen]["keys"].add(row["loc_key"])
            expected_screens[screen]["langs"].add(row["lang_target"])

    screens = {
        screen: {
            "unique_keys": len(data["keys"]),
            "languages_covered": sorted(data["langs"]),
        }
        for screen, data in expected_screens.items()
    }

    assert os.path.isfile(VIDEO_PATH), "Video fixture disappeared before verification."
    screen_loads = 0
    cap = cv2.VideoCapture(VIDEO_PATH)
    assert cap.isOpened(), "Could not open verification video."
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        if np.array_equal(frame[0:10, 0:10], np.full((10, 10, 3), 255, dtype=np.uint8)):
            screen_loads += 1
    cap.release()

    return {"total_screen_loads_from_video": screen_loads, "screens": screens}


def run_and_check(binary, cwd, expected, case_name):
    if os.path.exists(OUTPUT_PATH):
        os.unlink(OUTPUT_PATH)
    result = subprocess.run([binary], cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60)
    assert result.returncode == 0, (
        f"Pipeline failed for {case_name} with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), f"Pipeline did not create {OUTPUT_PATH} for {case_name}."
    try:
        with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
            actual = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"{OUTPUT_PATH} is not valid JSON for {case_name}: {exc}")
    assert actual == expected, f"Incorrect output for {case_name}. Expected {expected}, got {actual}"


def main():
    binary, cwd = find_and_compile_pipeline()

    original_rows = [
        [500, "screen_A", "greeting", "Hello", "es", "Hola"],
        [510, "screen_A", "greeting", "Hello", "es", "Hola"],
        [520, "screen_A", "farewell", "Goodbye", "fr", "Au revoir"],
        [530, "screen_A", "missing_key", "Test", "de", "MISSING"],
        [1500, "screen_B", "title", "Main Menu", "es", "Menu principal"],
        [1510, "screen_B", "start", "Start", "es", "Empezar"],
        [1520, "screen_B", "title", "Main Menu", "fr", "Menu principal"],
    ]
    write_csv(original_rows)
    write_original_video()
    original_expected = derive_expected()
    run_and_check(binary, cwd, original_expected, "original input")

    token = uuid.uuid4().hex[:10]
    screen_one = "screen_" + token
    screen_two = "dialog_" + token
    rows = [
        [100, screen_one, "alpha_" + token, "Alpha", "de", "A"],
        [110, screen_one, "alpha_" + token, "Alpha", "de", "duplicate ignored"],
        [120, screen_one, "alpha_" + token, "Alpha", "ja", "J"],
        [130, screen_one, "beta_" + token, "Beta", "fr", "B"],
        [140, screen_one, "invalid_" + token, "Invalid", "es", "MISSING"],
        [150, screen_one, "empty_" + token, "Empty", "it", ""],
        [200, screen_two, "gamma_" + token, "Gamma", "pt", "G"],
        [210, screen_two, "delta_" + token, "Delta", "ar", "D"],
        [220, screen_two, "delta_" + token, "Delta", "pt", "D2"],
    ]
    write_csv(rows)
    rng = random.SystemRandom()
    frame_count = rng.randint(26, 38)
    trigger_frames = set(rng.sample(range(1, frame_count - 1), rng.randint(2, 6)))
    write_lossless_video(trigger_frames, frame_count)
    dynamic_expected = derive_expected()
    assert dynamic_expected["total_screen_loads_from_video"] == len(trigger_frames), "Lossless video fixture was not preserved exactly."
    run_and_check(binary, cwd, dynamic_expected, "dynamic input")


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_pipeline.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
