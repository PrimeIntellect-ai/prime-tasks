#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import shlex
import shutil
import subprocess
import tempfile
import urllib.request
from pathlib import Path

import h5py
import numpy as np
import scipy.stats as stats


def test_nginx_config_fixed_and_operational():
    conf_path = "/app/services/nginx/nginx.conf"
    assert os.path.isfile(conf_path), f"File {conf_path} is missing"
    with open(conf_path, "r") as f:
        content = f.read()

    # Preserve the original configuration assertions.
    assert "5001" not in content, "Nginx config still contains the incorrect port 5001"
    assert "5000" in content, "Nginx config does not contain the correct port 5000"

    checked = subprocess.run(
        ["nginx", "-t", "-c", conf_path], capture_output=True, text=True
    )
    assert checked.returncode == 0, f"Nginx configuration is invalid:\n{checked.stdout}\n{checked.stderr}"
    assert "listen 8080" in content, "Nginx is not configured to listen on port 8080"
    assert "location /api/" in content, "Nginx does not define the required /api/ route"

    # Exercise the live reverse proxy using unpredictable payloads and independently
    # calculate the values returned by the Flask backend.
    rng = np.random.default_rng(int.from_bytes(os.urandom(8), "big"))
    spectra = [rng.uniform(0.1, 100.0, size=17).tolist() for _ in range(4)]
    for spectrum in spectra:
        body = json.dumps({"spectrum": spectrum}).encode()
        request = urllib.request.Request(
            "http://127.0.0.1:8080/api/analyze_spectrum",
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=5) as response:
                assert response.status == 200
                result = json.loads(response.read().decode())
        except Exception as exc:
            raise AssertionError(f"The API is not reachable through Nginx on port 8080: {exc}")

        values = np.asarray(spectrum, dtype=float)
        z = (np.max(values) - np.mean(values)) / (np.std(values) + 1e-9)
        expected = float(stats.norm.sf(z))
        assert "p_value" in result
        assert abs(float(result["p_value"]) - expected) < 1e-12, (
            f"Nginx did not route to the expected spectrum API: {result}"
        )


def test_calc_spectrum_compiled_and_correct():
    bin_path = "/home/user/bin/calc_spectrum"
    assert os.path.isfile(bin_path), f"Executable {bin_path} is missing. Did you compile the C code?"
    assert os.access(bin_path, os.X_OK), f"File {bin_path} is not executable."
    with open(bin_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "calc_spectrum is not a compiled executable"

    rng = np.random.default_rng(int.from_bytes(os.urandom(8), "big"))
    sequence = rng.normal(size=1024)
    with tempfile.TemporaryDirectory(prefix="spectrum_check_") as tmp:
        input_path = os.path.join(tmp, secrets.token_hex(8) + ".h5")
        with h5py.File(input_path, "w") as h5:
            h5.create_dataset("/sequence", data=sequence)

        result = subprocess.run([bin_path, input_path], capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, f"calc_spectrum failed:\n{result.stderr}"
        try:
            actual = np.asarray([float(x) for x in result.stdout.strip().split(",")])
        except ValueError as exc:
            raise AssertionError(f"calc_spectrum did not emit comma-separated numbers: {exc}")

        expected = np.abs(np.fft.rfft(sequence)) ** 2
        assert actual.shape == (513,), f"Expected 513 power values, got {actual.size}"
        assert np.all(np.isfinite(actual)), "calc_spectrum emitted non-finite values"
        assert np.allclose(actual, expected, rtol=2e-5, atol=2e-4), (
            "calc_spectrum output does not match an independently calculated FFT power spectrum"
        )


def test_filter_seqs_script_exists():
    script_path = "/home/user/filter_seqs.sh"
    assert os.path.isfile(script_path), f"Script {script_path} is missing"
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable"


def test_adversarial_corpus_from_unpredictable_paths():
    script_path = "/home/user/filter_seqs.sh"
    source_clean = "/app/data/clean"
    source_evil = "/app/data/evil"

    clean_sources = [f for f in os.listdir(source_clean) if f.endswith(".h5")]
    evil_sources = [f for f in os.listdir(source_evil) if f.endswith(".h5")]
    assert clean_sources, "Clean corpus is empty"
    assert evil_sources, "Evil corpus is empty"

    calc_path = "/home/user/bin/calc_spectrum"
    hidden_real = os.path.join(
        os.path.dirname(calc_path), ".calc_spectrum.verifier." + secrets.token_hex(12)
    )

    with tempfile.TemporaryDirectory(prefix="classification_") as root:
        input_a = os.path.join(root, "in_" + secrets.token_hex(8))
        input_b = os.path.join(root, "in_" + secrets.token_hex(8))
        output_a = os.path.join(root, "out_" + secrets.token_hex(8))
        output_b = os.path.join(root, "out_" + secrets.token_hex(8))
        os.makedirs(input_a)
        os.makedirs(input_b)
        os.makedirs(output_a)
        os.makedirs(output_b)

        clean_files = set()
        evil_files = set()
        for source_name in clean_sources:
            new_name = secrets.token_hex(12) + ".h5"
            shutil.copy2(os.path.join(source_clean, source_name), os.path.join(input_a, new_name))
            clean_files.add(new_name)
        for source_name in evil_sources:
            new_name = secrets.token_hex(12) + ".h5"
            shutil.copy2(os.path.join(source_evil, source_name), os.path.join(input_b, new_name))
            evil_files.add(new_name)

        log_path = os.path.join(root, "calc_calls.log")
        os.rename(calc_path, hidden_real)
        wrapper = """#!/bin/bash
p=$(readlink -f -- "$1")
printf '%s\\n' "$p" >> {log}
exec {real} "$@"
""".format(log=shlex.quote(log_path), real=shlex.quote(hidden_real))
        with open(calc_path, "w") as f:
            f.write(wrapper)
        os.chmod(calc_path, 0o755)

        try:
            jobs = [
                (input_a, output_a, "clean"),
                (input_b, output_b, "evil"),
            ]
            random.SystemRandom().shuffle(jobs)
            results = {}
            for input_dir, output_dir, label in jobs:
                result = subprocess.run(
                    [script_path, input_dir, output_dir],
                    capture_output=True,
                    text=True,
                    timeout=60,
                )
                results[label] = result

            res_clean = results["clean"]
            res_evil = results["evil"]
            assert res_clean.returncode == 0, f"Script failed on clean corpus with error:\n{res_clean.stderr}"
            assert res_evil.returncode == 0, f"Script failed on evil corpus with error:\n{res_evil.stderr}"

            clean_out_files = {f for f in os.listdir(output_a) if f.endswith(".h5")}
            evil_out_files = {f for f in os.listdir(output_b) if f.endswith(".h5")}

            # Preserve the original classification assertions.
            missing_clean = clean_files - clean_out_files
            assert not missing_clean, (
                f"{len(missing_clean)} of {len(clean_files)} clean files modified/rejected. "
                f"Missing clean files: {', '.join(missing_clean)}"
            )
            bypassed_evil = evil_out_files.intersection(evil_files)
            assert not bypassed_evil, (
                f"{len(bypassed_evil)} of {len(evil_files)} evil files bypassed. "
                f"Bypassed evil files: {', '.join(bypassed_evil)}"
            )

            assert clean_out_files == clean_files, "Classifier produced unexpected HDF5 output files"
            assert not evil_out_files, "Classifier copied HDF5 files from the evil corpus"
            for name in clean_files:
                with open(os.path.join(input_a, name), "rb") as original:
                    original_bytes = original.read()
                with open(os.path.join(output_a, name), "rb") as copied:
                    assert copied.read() == original_bytes, f"Copied file {name} was modified"

            called = set()
            if os.path.exists(log_path):
                with open(log_path) as f:
                    called = {line.strip() for line in f if line.strip()}
            expected_calls = {
                str(Path(input_a, name).resolve()) for name in clean_files
            } | {
                str(Path(input_b, name).resolve()) for name in evil_files
            }
            missing_calls = expected_calls - called
            assert not missing_calls, (
                "filter_seqs.sh did not run calc_spectrum for every input HDF5 file: "
                + ", ".join(sorted(missing_calls))
            )
        finally:
            if os.path.lexists(calc_path):
                os.unlink(calc_path)
            os.rename(hidden_real, calc_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
