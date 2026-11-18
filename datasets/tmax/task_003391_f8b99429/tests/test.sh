#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import shutil
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFont


def render_dashboard(threshold):
    img = Image.new("RGB", (800, 300), color=(255, 255, 255))
    draw = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype(
            "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", 32
        )
    except IOError:
        font = ImageFont.load_default()
    text = (
        "STORAGE POLICY DASHBOARD\n"
        "Alerts: Active\n"
        f"Max Utilization Threshold: {threshold:.1f}%\n"
        "Action: Isolate unoptimized volumes."
    )
    draw.text((20, 20), text, fill=(0, 0, 0), font=font)
    img.save("/app/dashboard.png")


def read_utilizations(test_dir):
    utilizations = {}
    files = sorted(f for f in os.listdir(test_dir) if f.endswith(".qcow2"))
    for filename in files:
        filepath = os.path.join(test_dir, filename)
        result = subprocess.run(
            ["qemu-img", "info", "--output=json", filepath],
            capture_output=True,
            text=True,
            check=True,
        )
        info = json.loads(result.stdout)
        utilizations[filename] = (info["actual-size"] / info["virtual-size"]) * 100
    return utilizations


def expected_lines(utilizations, threshold):
    valid = [
        filename
        for filename in sorted(utilizations)
        if utilizations[filename] < threshold
    ]
    return [
        f"/dev/nbd{idx} /mnt/services/{os.path.splitext(filename)[0]} ext4 defaults,usrquota 0 2"
        for idx, filename in enumerate(valid)
    ]


def run_and_check(script_path, test_dir, threshold, utilizations):
    render_dashboard(threshold)

    fstab_path = "/home/user/fstab_generated"
    if os.path.exists(fstab_path):
        os.remove(fstab_path)

    result = subprocess.run(
        ["python3", script_path, test_dir], capture_output=True, text=True, timeout=120
    )
    assert result.returncode == 0, (
        f"Script failed with error:\n{result.stderr}\nOutput:\n{result.stdout}"
    )
    assert os.path.exists(fstab_path), f"{fstab_path} was not generated."
    assert os.path.isfile(fstab_path), f"{fstab_path} is not a regular file."

    with open(fstab_path, "r") as handle:
        generated = [line.strip() for line in handle if line.strip()]

    expected = expected_lines(utilizations, threshold)
    accuracy = 1.0 if expected == generated else 0.0
    assert expected == generated, (
        "Generated fstab does not match expected.\n"
        f"Accuracy: {accuracy} (Threshold: 1.0)\n"
        f"Policy threshold shown in dashboard: {threshold:.1f}%\n"
        f"Expected {len(expected)} lines, got {len(generated)} lines.\n"
        f"Expected first line: {expected[0] if expected else 'None'}\n"
        f"Generated first line: {generated[0] if generated else 'None'}"
    )


def test_manage_storage_accuracy():
    script_path = "/home/user/manage_storage.py"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(script_path), f"Script {script_path} is not a regular file."

    test_dir = tempfile.mkdtemp(prefix="hidden_vms_", dir="/tmp")
    dashboard_path = "/app/dashboard.png"
    with open(dashboard_path, "rb") as handle:
        original_dashboard = handle.read()

    rng = random.SystemRandom()
    try:
        virtual_size = 8 * 1024 * 1024
        indices = list(range(100))
        rng.shuffle(indices)

        for sequence, level in enumerate(indices):
            filename = f"svc_{secrets.token_hex(5)}_{sequence:03d}.qcow2"
            filepath = os.path.join(test_dir, filename)
            subprocess.run(
                ["qemu-img", "create", "-f", "qcow2", filepath, str(virtual_size)],
                check=True,
                capture_output=True,
            )

            # Randomized, broadly distributed allocation amounts make the expected
            # subset unknowable without inspecting these actual hidden images.
            fraction = (level + rng.random()) / 104.0
            write_size = int(virtual_size * fraction)
            if write_size > 0:
                subprocess.run(
                    ["qemu-io", "-c", f"write 0 {write_size}", filepath],
                    check=True,
                    capture_output=True,
                )

        utilizations = read_utilizations(test_dir)
        assert len(utilizations) == 100

        # Select two independently randomized policy values that produce clearly
        # different, nontrivial valid subsets. The only runtime source of each
        # value available to the submitted program is dashboard.png.
        candidates = [value / 10.0 for value in range(50, 1110)]
        low_candidates = [
            value
            for value in candidates
            if 20 <= sum(util < value for util in utilizations.values()) <= 40
        ]
        high_candidates = [
            value
            for value in candidates
            if 60 <= sum(util < value for util in utilizations.values()) <= 80
        ]
        assert low_candidates and high_candidates, "Could not construct policy test cases"

        low_threshold = rng.choice(low_candidates)
        high_threshold = rng.choice(high_candidates)
        assert expected_lines(utilizations, low_threshold) != expected_lines(
            utilizations, high_threshold
        )

        run_and_check(script_path, test_dir, low_threshold, utilizations)
        run_and_check(script_path, test_dir, high_threshold, utilizations)
    finally:
        with open(dashboard_path, "wb") as handle:
            handle.write(original_dashboard)
        shutil.rmtree(test_dir, ignore_errors=True)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
