#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import tempfile
import uuid

import pytest


def test_video_incident_analysis():
    timestamps_file = "/home/user/502_timestamps.txt"
    assert os.path.isfile(timestamps_file), f"Expected file {timestamps_file} to exist."

    try:
        with open(timestamps_file, "r") as f:
            pred = [float(line.strip()) for line in f if line.strip()]
    except Exception as e:
        pytest.fail(f"Could not parse {timestamps_file} as floats: {e}")

    gt = [12.0, 24.0, 37.0, 45.0, 58.0]
    matched_gt = set()
    tp = 0
    for p in pred:
        for i, g in enumerate(gt):
            if i not in matched_gt and abs(p - g) <= 1.0:
                tp += 1
                matched_gt.add(i)
                break

    fp = len(pred) - tp
    fn = len(gt) - tp

    if tp == 0:
        f1 = 0.0
    else:
        precision = tp / (tp + fp)
        recall = tp / (tp + fn)
        f1 = 2 * (precision * recall) / (precision + recall)

    assert f1 >= 0.85, f"F1 score for timestamp detection is {f1:.3f}, expected >= 0.85. Pred: {pred}"


def test_k8s_operator_fix():
    operator_script = "/home/user/k8s_operator.py"
    manifests_dir = "/home/user/manifests"
    configs_dir = "/home/user/configs"
    assert os.path.isfile(operator_script), f"Operator script {operator_script} is missing."

    os.makedirs(configs_dir, exist_ok=True)

    # Preserve the original shipped-manifest assertion.
    result = subprocess.run(["/usr/bin/python3", operator_script], capture_output=True, text=True)
    assert result.returncode == 0, f"Operator script failed with error: {result.stderr}"

    conf_file = "/home/user/configs/app1.conf"
    assert os.path.isfile(conf_file), f"Expected generated config file {conf_file} is missing."
    with open(conf_file, "r") as f:
        content = f.read()
    expected_line = "proxy_pass http://unix:/var/run/custom-app.sock;"
    assert expected_line in content, f"Expected '{expected_line}' in {conf_file}, but got:\n{content}"

    # Exercise fresh, unpredictable manifests so a fixed app1.conf cannot pass.
    backup_root = tempfile.mkdtemp(prefix="operator-test-")
    backup_manifests = os.path.join(backup_root, "manifests")
    backup_configs = os.path.join(backup_root, "configs")
    shutil.copytree(manifests_dir, backup_manifests)
    shutil.copytree(configs_dir, backup_configs)

    try:
        shutil.rmtree(manifests_dir)
        shutil.rmtree(configs_dir)
        os.makedirs(manifests_dir)
        os.makedirs(configs_dir)

        token = uuid.uuid4().hex
        cases = [
            (f"annotated-a-{token}", f"/run/{token}/first.sock", True),
            (f"annotated-b-{token}", f"/var/tmp/{token}-second.sock", True),
            (f"fallback-{token}", "/tmp/default.sock", False),
        ]

        import json
        for index, (name, socket_path, annotated) in enumerate(cases):
            metadata = {"name": name}
            if annotated:
                metadata["annotations"] = {
                    "nginx.ingress.kubernetes.io/socket-path": socket_path
                }
            manifest = {"metadata": metadata}
            with open(os.path.join(manifests_dir, f"case-{index}-{token}.json"), "w") as f:
                json.dump(manifest, f)

        result = subprocess.run(["/usr/bin/python3", operator_script], capture_output=True, text=True)
        assert result.returncode == 0, f"Operator script failed on generated manifests: {result.stderr}"

        for name, socket_path, _ in cases:
            generated = os.path.join(configs_dir, f"{name}.conf")
            assert os.path.isfile(generated), f"Expected generated config {generated} is missing."
            with open(generated, "r") as f:
                generated_content = f.read()
            expected_proxy = f"proxy_pass http://unix:{socket_path};"
            assert expected_proxy in generated_content, (
                f"Expected '{expected_proxy}' in {generated}, but got:\n{generated_content}"
            )
    finally:
        shutil.rmtree(manifests_dir, ignore_errors=True)
        shutil.rmtree(configs_dir, ignore_errors=True)
        shutil.copytree(backup_manifests, manifests_dir)
        shutil.copytree(backup_configs, configs_dir)
        shutil.rmtree(backup_root, ignore_errors=True)


def test_setup_env_idempotency_and_cron():
    setup_script = "/home/user/setup_env.sh"
    assert os.path.isfile(setup_script), f"Setup script {setup_script} is missing."
    assert os.access(setup_script, os.X_OK), f"Setup script {setup_script} must be executable."

    configs_dir = "/home/user/configs"
    os.makedirs(configs_dir, exist_ok=True)

    old_cron = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    had_cron = old_cron.returncode == 0
    old_cron_text = old_cron.stdout
    marker = uuid.uuid4().hex
    unrelated_cron = f"17 2 * * * /bin/echo {marker}"

    try:
        seeded = subprocess.run(["crontab", "-"], input=unrelated_cron + "\n", capture_output=True, text=True)
        assert seeded.returncode == 0, f"Could not seed crontab: {seeded.stderr}"

        dummy_file = os.path.join(configs_dir, "dummy.txt")
        with open(dummy_file, "w") as f:
            f.write("test")
        with open(os.path.join(configs_dir, f"extra-{marker}.conf"), "w") as f:
            f.write("test")
        with open(os.path.join(configs_dir, f".hidden-{marker}"), "w") as f:
            f.write("test")
        nested = os.path.join(configs_dir, f"nested-{marker}")
        os.makedirs(nested)
        with open(os.path.join(nested, "file.txt"), "w") as f:
            f.write("test")

        res1 = subprocess.run(["bash", setup_script], capture_output=True, text=True)
        assert res1.returncode == 0, f"Setup script failed: {res1.stderr}"
        assert os.path.isdir(configs_dir), f"Setup script did not ensure {configs_dir} exists."
        assert not os.path.exists(dummy_file), f"Setup script did not clear existing files in {configs_dir}."
        assert os.listdir(configs_dir) == [], f"Setup script did not fully clear {configs_dir}: {os.listdir(configs_dir)}"

        # Remove the directory before the second run to verify it is recreated as well as idempotent.
        shutil.rmtree(configs_dir)
        res2 = subprocess.run(["bash", setup_script], capture_output=True, text=True)
        assert res2.returncode == 0, f"Setup script failed on second run: {res2.stderr}"
        assert os.path.isdir(configs_dir), f"Setup script did not recreate {configs_dir}."
        assert os.listdir(configs_dir) == [], f"Recreated config directory is not empty: {os.listdir(configs_dir)}"

        cron_res = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
        assert cron_res.returncode == 0, f"Could not read crontab: {cron_res.stderr}"
        cron_output = cron_res.stdout.strip()
        expected_cron_job = "*/3 * * * * /usr/bin/python3 /home/user/k8s_operator.py"

        assert expected_cron_job in cron_output, f"Expected cron job '{expected_cron_job}' not found in crontab:\n{cron_output}"
        cron_lines = [line.strip() for line in cron_output.split("\n") if line.strip()]
        job_count = cron_lines.count(expected_cron_job)
        assert job_count == 1, f"Setup script is not idempotent. Found {job_count} instances of the cron job in crontab."
        assert unrelated_cron in cron_lines, "Setup script removed an unrelated existing crontab entry."
    finally:
        if had_cron:
            subprocess.run(["crontab", "-"], input=old_cron_text, capture_output=True, text=True)
        else:
            subprocess.run(["crontab", "-r"], capture_output=True, text=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
