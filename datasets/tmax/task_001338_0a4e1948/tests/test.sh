#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import random
import re
import shutil
import subprocess
import tempfile
import uuid


def run_processor(path):
    result = subprocess.run([path], cwd="/workspace", capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, f"Processor failed ({result.returncode})\nstdout: {result.stdout}\nstderr: {result.stderr}"
    match = re.search(r"BrightFrameCount\s*:\s*(\d+)", result.stdout)
    assert match, f"Processor did not report BrightFrameCount: {result.stdout!r}"
    return int(match.group(1))


def test_go_binary_built():
    bin_path = "/workspace/bin/processor"
    assert os.path.isfile(bin_path), f"Go binary {bin_path} was not built."
    assert os.access(bin_path, os.X_OK), f"Go binary {bin_path} is not executable."

    file_result = subprocess.run(["file", bin_path], capture_output=True, text=True)
    assert file_result.returncode == 0 and "ELF" in file_result.stdout, f"processor is not a native executable: {file_result.stdout}"
    go_info = subprocess.run(["go", "version", "-m", bin_path], capture_output=True, text=True)
    assert go_info.returncode == 0, f"processor is not a Go binary: {go_info.stderr}"

    for _ in range(3):
        assert run_processor(bin_path) == 142


def test_go_source_has_no_race_and_computes_count():
    source = "/workspace/src/main.go"
    assert os.path.isfile(source), f"Go source missing at {source}"
    with tempfile.TemporaryDirectory() as td:
        race_binary = os.path.join(td, "processor-race")
        build = subprocess.run(
            ["go", "build", "-race", "-o", race_binary, source],
            cwd="/workspace/src", capture_output=True, text=True, timeout=120
        )
        assert build.returncode == 0, f"Race-enabled Go build failed\nstdout: {build.stdout}\nstderr: {build.stderr}"
        for _ in range(3):
            result = subprocess.run([race_binary], cwd="/workspace", capture_output=True, text=True, timeout=60)
            combined = result.stdout + result.stderr
            assert result.returncode == 0, f"Race-enabled processor failed\n{combined}"
            assert "DATA RACE" not in combined, f"Go race detector found a race:\n{combined}"
            match = re.search(r"BrightFrameCount\s*:\s*(\d+)", result.stdout)
            assert match and int(match.group(1)) == 142, f"Incorrect BrightFrameCount: {result.stdout!r}"


def test_cpp_brightness_is_correct_and_memory_safe():
    source = "/workspace/src/lib/analyzer.cpp"
    assert os.path.isfile(source), f"C++ analyzer missing at {source}"
    harness = r'''
#include <cstdlib>
#include <iostream>
#include <vector>
extern "C" int calculate_brightness(unsigned char* data, int length);

static void check(const std::vector<unsigned char>& values, int expected) {
    unsigned char* p = static_cast<unsigned char*>(std::malloc(values.size()));
    if (!p) std::exit(20);
    for (size_t i = 0; i < values.size(); ++i) p[i] = values[i];
    int got = calculate_brightness(p, static_cast<int>(values.size()));
    std::free(p);
    if (got != expected) {
        std::cerr << "expected " << expected << " got " << got << std::endl;
        std::exit(21);
    }
}

int main() {
    check({0}, 0);
    check({255}, 255);
    check({10, 20, 30}, 20);
    check({0, 255, 128, 64, 32}, 95);
    std::vector<unsigned char> many(320 * 3);
    long long total = 0;
    for (size_t i = 0; i < many.size(); ++i) {
        many[i] = static_cast<unsigned char>((i * 37 + 11) % 256);
        total += many[i];
    }
    check(many, static_cast<int>(total / many.size()));
    return 0;
}
'''
    with tempfile.TemporaryDirectory() as td:
        harness_path = os.path.join(td, "harness.cpp")
        executable = os.path.join(td, "brightness_test")
        with open(harness_path, "w", encoding="utf-8") as f:
            f.write(harness)
        build = subprocess.run([
            "g++", "-std=c++17", "-O1", "-g",
            "-fsanitize=address,undefined", "-fno-sanitize-recover=all",
            source, harness_path, "-o", executable
        ], capture_output=True, text=True, timeout=120)
        assert build.returncode == 0, f"C++ sanitizer build failed\nstdout: {build.stdout}\nstderr: {build.stderr}"
        env = os.environ.copy()
        env["ASAN_OPTIONS"] = "halt_on_error=1:detect_leaks=1"
        result = subprocess.run([executable], capture_output=True, text=True, env=env, timeout=60)
        assert result.returncode == 0, f"Brightness implementation failed or triggered a sanitizer\nstdout: {result.stdout}\nstderr: {result.stderr}"


def test_python_filter_exists():
    script_path = "/workspace/filter.py"
    assert os.path.isfile(script_path), f"Python 3 filter script {script_path} is missing."


def test_filter_function_uses_signature_formula():
    script_path = "/workspace/filter.py"
    spec = importlib.util.spec_from_file_location("submitted_filter", script_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, "is_clean_record"), "filter.py does not expose is_clean_record"

    rng = random.Random(8675309)
    for _ in range(20):
        key = rng.randint(1, 5000)
        event_id = rng.randint(-100000, 100000)
        signature = (event_id * key) % 99991
        assert module.is_clean_record({"event_id": event_id, "signature": signature}, key) is True
        assert module.is_clean_record({"event_id": event_id, "signature": (signature + 1) % 99991}, key) is False


def test_adversarial_corpus_filtering():
    evil_dir = "/app/corpus/evil"
    clean_dir = "/app/corpus/clean"
    script_path = "/workspace/filter.py"
    true_key = "142"

    assert os.path.isdir(evil_dir), f"Evil corpus directory missing at {evil_dir}"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing at {clean_dir}"

    with tempfile.TemporaryDirectory() as mixed_dir, tempfile.TemporaryDirectory() as out_dir:
        evil_files = os.listdir(evil_dir)
        clean_files = os.listdir(clean_dir)

        for f in evil_files:
            shutil.copy(os.path.join(evil_dir, f), os.path.join(mixed_dir, f"evil_{f}"))
        for f in clean_files:
            shutil.copy(os.path.join(clean_dir, f), os.path.join(mixed_dir, f"clean_{f}"))

        cmd = ["python3", script_path, "--input", mixed_dir, "--output", out_dir, "--key", true_key]
        result = subprocess.run(cmd, capture_output=True, text=True)
        assert result.returncode == 0, f"Filter script failed with return code {result.returncode}\nStderr: {result.stderr}"

        out_files = set(os.listdir(out_dir))
        evil_bypassed = [f for f in evil_files if f"evil_{f}" in out_files]
        clean_modified = [f for f in clean_files if f"clean_{f}" not in out_files]

        err_msg = []
        if evil_bypassed:
            err_msg.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {evil_bypassed[:5]}")
        if clean_modified:
            err_msg.append(f"{len(clean_modified)} of {len(clean_files)} clean modified/rejected: {clean_modified[:5]}")
        assert not err_msg, " | ".join(err_msg)


def test_filter_dynamic_unlabeled_inputs_and_safe_parsing():
    script_path = "/workspace/filter.py"
    key = run_processor("/workspace/bin/processor")
    token = uuid.uuid4().hex
    marker = f"/tmp/filter_exploit_{token}"

    with tempfile.TemporaryDirectory() as input_dir, tempfile.TemporaryDirectory() as output_dir:
        clean = {}
        for i, event_id in enumerate([7, 913, -41, 100003]):
            name = f"{uuid.uuid4().hex}.json"
            record = {"event_id": event_id, "signature": (event_id * key) % 99991, "metadata": f"record-{i}"}
            clean[name] = record
            with open(os.path.join(input_dir, name), "w", encoding="utf-8") as f:
                json.dump(record, f)

        rejected_names = []
        for event_id in [8, 914, -42, 100004]:
            name = f"{uuid.uuid4().hex}.json"
            rejected_names.append(name)
            correct = (event_id * key) % 99991
            with open(os.path.join(input_dir, name), "w", encoding="utf-8") as f:
                json.dump({"event_id": event_id, "signature": (correct + 17) % 99991}, f)

        malicious_yaml = f"{uuid.uuid4().hex}.json"
        rejected_names.append(malicious_yaml)
        with open(os.path.join(input_dir, malicious_yaml), "w", encoding="utf-8") as f:
            f.write(f'!!python/object/apply:os.system ["touch {marker}"]')

        malicious_json = f"{uuid.uuid4().hex}.json"
        rejected_names.append(malicious_json)
        event_id = 55
        with open(os.path.join(input_dir, malicious_json), "w", encoding="utf-8") as f:
            json.dump({
                "event_id": event_id,
                "signature": (event_id * key) % 99991,
                "payload": "!!python/object/apply:os.system [touch /tmp/pwned]"
            }, f)

        malformed = f"{uuid.uuid4().hex}.json"
        rejected_names.append(malformed)
        with open(os.path.join(input_dir, malformed), "w", encoding="utf-8") as f:
            f.write('{"event_id": 1, "signature":')

        invalid_unicode = f"{uuid.uuid4().hex}.json"
        rejected_names.append(invalid_unicode)
        with open(os.path.join(input_dir, invalid_unicode), "wb") as f:
            f.write(b'{"event_id": 2, "signature": 284, "x": "\xff"}')

        with open(os.path.join(input_dir, f"{uuid.uuid4().hex}.txt"), "w", encoding="utf-8") as f:
            f.write(json.dumps({"event_id": 1, "signature": key}))

        result = subprocess.run([
            "python3", script_path, "--input", input_dir, "--output", output_dir, "--key", str(key)
        ], capture_output=True, text=True, timeout=60)
        assert result.returncode == 0, f"Filter failed on mixed dynamic corpus\nstdout: {result.stdout}\nstderr: {result.stderr}"
        assert not os.path.exists(marker), "Unsafe YAML payload was executed"

        output_names = set(os.listdir(output_dir))
        assert output_names == set(clean), f"Expected only valid records; got {output_names}, expected {set(clean)}"
        for name, expected in clean.items():
            with open(os.path.join(output_dir, name), "r", encoding="utf-8") as f:
                assert json.load(f) == expected
        assert not (set(rejected_names) & output_names)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
