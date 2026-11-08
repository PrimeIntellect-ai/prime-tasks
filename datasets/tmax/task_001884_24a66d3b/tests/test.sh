#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import secrets
import shutil
import stat
import subprocess

import matplotlib.image as mpimg
import numpy as np
import pytest

PIPELINE = "/home/user/mlops_pipeline"
SCRIPT = os.path.join(PIPELINE, "run_experiments.sh")


def run_command(command, timeout=60):
    result = subprocess.run(
        command,
        cwd=PIPELINE,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Command failed: {command}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def test_00_execute_pipeline_from_clean_outputs():
    logs_dir = os.path.join(PIPELINE, "logs")
    if os.path.isdir(logs_dir):
        shutil.rmtree(logs_dir)
    for name in ["latency_summary.csv", "artifact_plot.png", "embeddings.csv"]:
        path = os.path.join(PIPELINE, name)
        if os.path.exists(path):
            os.remove(path)

    assert os.path.isfile(SCRIPT), f"File missing: {SCRIPT}"
    run_command([SCRIPT])


def test_latency_summary_csv():
    csv_path = "/home/user/mlops_pipeline/latency_summary.csv"
    assert os.path.isfile(csv_path), f"File missing: {csv_path}"

    expected_csv = (
        "batch_size,latency_ms\n"
        "1,20\n"
        "2,32\n"
        "4,56\n"
        "8,104\n"
        "16,200\n"
    )

    with open(csv_path, "r") as f:
        content = f.read().strip()

    expected_content = expected_csv.strip()
    assert content == expected_content, f"Content of {csv_path} does not match expected output.\nExpected:\n{expected_content}\nGot:\n{content}"


def test_artifact_plot_png():
    png_path = "/home/user/mlops_pipeline/artifact_plot.png"
    assert os.path.isfile(png_path), f"File missing: {png_path}"

    file_size = os.path.getsize(png_path)
    assert file_size > 0, f"File {png_path} is empty (0 bytes)"

    with open(png_path, "rb") as f:
        header = f.read(8)

    assert header == b"\x89PNG\r\n\x1a\n", f"File {png_path} is not a valid PNG image (invalid header)"


def test_run_experiments_script():
    script_path = "/home/user/mlops_pipeline/run_experiments.sh"
    assert os.path.isfile(script_path), f"File missing: {script_path}"

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable"

    with open(script_path, "r") as f:
        content = f.read()

    assert "generate_embeddings.py" in content, f"Script {script_path} does not run generate_embeddings.py"
    assert "plot_artifacts.py" in content, f"Script {script_path} does not run plot_artifacts.py"


def test_logs_directory_and_files():
    logs_dir = "/home/user/mlops_pipeline/logs"
    assert os.path.isdir(logs_dir), f"Directory missing: {logs_dir}"

    for size in [1, 2, 4, 8, 16]:
        log_file = os.path.join(logs_dir, f"run_{size}.log")
        assert os.path.isfile(log_file), f"Log file missing: {log_file}"

        with open(log_file, "r") as f:
            content = f.read()
        assert f"Batch Size: {size}" in content, f"Log file {log_file} does not contain correct batch size"
        assert "Latency:" in content, f"Log file {log_file} does not contain latency information"


def test_10_plot_script_renders_data_dependent_decodable_png():
    embeddings_path = os.path.join(PIPELINE, "embeddings.csv")
    png_path = os.path.join(PIPELINE, "artifact_plot.png")

    datasets = [
        [(0, 0), (1, 1), (2, 2), (3, 3), (4, 4)],
        [(0, 4), (1, 0), (2, 3), (3, 1), (4, 2)],
    ]
    rendered = []

    for points in datasets:
        with open(embeddings_path, "w") as f:
            f.write("f1,f2,f3,f4\n")
            for x, y in points:
                f.write(f"{x},{y},0,0\n")

        if os.path.exists(png_path):
            os.remove(png_path)
        run_command(["python3", "plot_artifacts.py"])
        assert os.path.isfile(png_path), "plot_artifacts.py did not create artifact_plot.png"

        try:
            image = mpimg.imread(png_path)
        except Exception as exc:
            pytest.fail(f"artifact_plot.png is not a decodable PNG: {exc}")
        assert image.ndim in (2, 3) and image.shape[0] > 10 and image.shape[1] > 10
        assert float(np.std(image)) > 0.0, "Rendered plot is blank"
        rendered.append(image.copy())

    assert rendered[0].shape != rendered[1].shape or not np.array_equal(rendered[0], rendered[1]), (
        "plot_artifacts.py produced the same pixels for materially different embedding data"
    )


def test_20_pipeline_uses_generators_parses_dynamic_latencies_and_invokes_plotter():
    generator_path = os.path.join(PIPELINE, "generate_embeddings.py")
    plotter_path = os.path.join(PIPELINE, "plot_artifacts.py")
    generator_backup = open(generator_path, "rb").read()
    plotter_backup = open(plotter_path, "rb").read()
    generator_mode = stat.S_IMODE(os.stat(generator_path).st_mode)
    plotter_mode = stat.S_IMODE(os.stat(plotter_path).st_mode)

    token = secrets.token_hex(12)
    latency_base = secrets.randbelow(40000) + 1000
    call_log = f"/tmp/generator_calls_{token}"
    plot_marker = f"/tmp/plot_called_{token}"

    probe_generator = f'''import argparse
parser = argparse.ArgumentParser()
parser.add_argument("--batch_size", type=int, required=True)
args = parser.parse_args()
with open({call_log!r}, "a") as log:
    log.write(str(args.batch_size) + chr(10))
latency = {latency_base} + args.batch_size * 7
print(f"Batch Size: {{args.batch_size}}")
print(f"Latency: {{latency}} ms")
with open("embeddings.csv", "w") as output:
    output.write("f1,f2,f3,f4" + chr(10))
    for i in range(max(2, args.batch_size)):
        output.write(f"{{i}},{{args.batch_size + i}},0,0" + chr(10))
'''

    png_data = base64.b64encode(
        b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x04\x00\x00\x00\xb5\x1c\x0c\x02"
        b"\x00\x00\x00\x0bIDATx\xda\x63\xfc\xff\x1f\x00\x03\x03\x02\x00\xef\xbf\x69\x99\x00\x00\x00\x00IEND\xaeB\x60\x82"
    ).decode("ascii")
    probe_plotter = f'''import base64
with open({plot_marker!r}, "w") as marker:
    marker.write("called")
with open("artifact_plot.png", "wb") as output:
    output.write(base64.b64decode({png_data!r}))
'''

    try:
        with open(generator_path, "w") as f:
            f.write(probe_generator)
        with open(plotter_path, "w") as f:
            f.write(probe_plotter)
        os.chmod(generator_path, generator_mode)
        os.chmod(plotter_path, plotter_mode)

        for path in [call_log, plot_marker, os.path.join(PIPELINE, "latency_summary.csv"), os.path.join(PIPELINE, "artifact_plot.png")]:
            if os.path.exists(path):
                os.remove(path)
        logs_dir = os.path.join(PIPELINE, "logs")
        if os.path.isdir(logs_dir):
            shutil.rmtree(logs_dir)

        run_command([SCRIPT])

        assert os.path.isfile(call_log), "run_experiments.sh did not execute generate_embeddings.py"
        with open(call_log) as f:
            calls = [int(line.strip()) for line in f if line.strip()]
        assert calls == [1, 2, 4, 8, 16], f"Unexpected generator calls or order: {calls}"

        expected_lines = ["batch_size,latency_ms"] + [
            f"{size},{latency_base + size * 7}" for size in [1, 2, 4, 8, 16]
        ]
        with open(os.path.join(PIPELINE, "latency_summary.csv")) as f:
            actual_lines = f.read().strip().splitlines()
        assert actual_lines == expected_lines, (
            "latency_summary.csv was not built from the dynamically generated log latencies"
        )

        for size in [1, 2, 4, 8, 16]:
            log_path = os.path.join(logs_dir, f"run_{size}.log")
            assert os.path.isfile(log_path), f"Missing dynamically generated log: {log_path}"
            with open(log_path) as f:
                content = f.read()
            assert f"Batch Size: {size}" in content
            assert f"Latency: {latency_base + size * 7} ms" in content

        assert os.path.isfile(plot_marker), "run_experiments.sh did not execute plot_artifacts.py"
        assert os.path.isfile(os.path.join(PIPELINE, "artifact_plot.png"))
    finally:
        with open(generator_path, "wb") as f:
            f.write(generator_backup)
        with open(plotter_path, "wb") as f:
            f.write(plotter_backup)
        os.chmod(generator_path, generator_mode)
        os.chmod(plotter_path, plotter_mode)
        for path in [call_log, plot_marker]:
            if os.path.exists(path):
                os.remove(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
