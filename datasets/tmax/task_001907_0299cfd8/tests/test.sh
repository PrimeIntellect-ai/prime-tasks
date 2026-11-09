#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import copy
import json
import os
import signal
import subprocess
import time
import uuid

import pytest
import yaml

HOME = "/home/user"
PROJECT = f"{HOME}/k8s_processor"
INPUT = f"{HOME}/input_manifests"
OUTPUT = f"{HOME}/output_manifests"
PIPELINE = f"{HOME}/pipeline.sh"
EVALUATOR = f"{HOME}/evaluate_manifests.py"


def clear_dir(path):
    os.makedirs(path, exist_ok=True)
    for name in os.listdir(path):
        p = os.path.join(path, name)
        if os.path.isdir(p) and not os.path.islink(p):
            import shutil
            shutil.rmtree(p)
        else:
            os.unlink(p)


def write_yaml(path, value):
    with open(path, "w") as f:
        yaml.safe_dump(value, f, sort_keys=False)


def read_yaml(path):
    with open(path) as f:
        return yaml.safe_load(f)


def wait_until(predicate, timeout=60, interval=0.25):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            if predicate():
                return
        except Exception as exc:
            last_error = exc
        time.sleep(interval)
    if last_error:
        raise AssertionError(f"Condition was not met before timeout; last error: {last_error}")
    raise AssertionError("Condition was not met before timeout")


def terminate_group(proc):
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait(timeout=5)


def build_binary():
    manifest = os.path.join(PROJECT, "Cargo.toml")
    assert os.path.isfile(manifest), "Missing Rust Cargo.toml"
    src = os.path.join(PROJECT, "src")
    assert os.path.isdir(src), "Missing Rust src directory"
    assert any(name.endswith(".rs") for _, _, files in os.walk(src) for name in files), "No Rust source files found"

    build = subprocess.run(
        ["cargo", "build", "--quiet", "--manifest-path", manifest],
        cwd=PROJECT,
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert build.returncode == 0, f"Rust project failed to compile:\n{build.stderr}"

    meta_result = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1", "--manifest-path", manifest],
        cwd=PROJECT,
        capture_output=True,
        text=True,
        timeout=30,
        check=True,
    )
    metadata = json.loads(meta_result.stdout)
    package = next((p for p in metadata["packages"] if os.path.abspath(p["manifest_path"]) == manifest), None)
    assert package is not None, "Could not identify the submitted Cargo package"
    bins = [t for t in package["targets"] if "bin" in t.get("kind", [])]
    assert bins, "Cargo project has no binary target"
    default_name = package.get("default_run")
    target = next((t for t in bins if t["name"] == default_name), bins[0])
    binary = os.path.join(metadata["target_directory"], "debug", target["name"])
    assert os.path.isfile(binary), f"Compiled Rust binary not found at {binary}"
    assert os.access(binary, os.X_OK), f"Compiled Rust binary is not executable: {binary}"
    return binary


def make_cases():
    token = uuid.uuid4().hex
    cases = {}
    index = 0

    def add(doc):
        nonlocal index
        name = f"case-{token}-{index}.yaml"
        index += 1
        cases[name] = doc

    for ns, replicas in [("backend", 1), ("backend", 5), ("backend", 9), ("frontend", 2), ("default", 3)]:
        add({
            "apiVersion": "apps/v1",
            "kind": "Deployment",
            "metadata": {
                "name": f"deploy-{token}-{index}",
                "namespace": ns,
                "labels": {"app": f"app-{index}", "retain-label": token},
                "annotations": {"retain.example/value": f"d-{index}"},
            },
            "spec": {
                "replicas": replicas,
                "selector": {"matchLabels": {"app": f"app-{index}"}},
                "strategy": {"type": "RollingUpdate"},
                "template": {
                    "metadata": {"labels": {"app": f"app-{index}"}},
                    "spec": {"containers": [{"name": "main", "image": f"nginx:{index}", "env": [{"name": "KEEP", "value": token}]}]},
                },
            },
            "x-preserve": {"token": token, "number": index},
        })

    for ns, existing in [("default", None), ("backend", "insecure"), ("frontend", "secure"), ("backend", "legacy")]:
        labels = {"app": f"svc-{index}", "retain-label": token}
        if existing is not None:
            labels["network-tier"] = existing
        add({
            "apiVersion": "v1",
            "kind": "Service",
            "metadata": {
                "name": f"service-{token}-{index}",
                "namespace": ns,
                "labels": labels,
                "annotations": {"retain.example/value": f"s-{index}"},
            },
            "spec": {
                "selector": {"app": f"svc-{index}"},
                "ports": [{"name": "http", "port": 80, "targetPort": 8080}],
                "type": "ClusterIP",
            },
            "x-preserve": {"token": token, "number": index},
        })

    for ns in ["default", "backend", "frontend", "backend"]:
        old_cidr = f"192.168.{index}.0/24"
        add({
            "apiVersion": "networking.k8s.io/v1",
            "kind": "NetworkPolicy",
            "metadata": {
                "name": f"policy-{token}-{index}",
                "namespace": ns,
                "labels": {"app": f"np-{index}", "retain-label": token},
                "annotations": {"retain.example/value": f"n-{index}"},
            },
            "spec": {
                "podSelector": {"matchLabels": {"app": f"np-{index}"}},
                "policyTypes": ["Ingress"],
                "ingress": [{
                    "ports": [{"protocol": "TCP", "port": 443}],
                    "from": [
                        {"ipBlock": {"cidr": old_cidr, "except": [f"192.168.{index}.128/25"]}},
                        {"namespaceSelector": {"matchLabels": {"zone": token}}},
                    ],
                }],
            },
            "x-preserve": {"token": token, "number": index},
        })

    add({
        "apiVersion": "v1",
        "kind": "ConfigMap",
        "metadata": {
            "name": f"untouched-{token}",
            "namespace": "backend",
            "labels": {"app": "untouched", "retain-label": token},
            "annotations": {"retain.example/value": "config"},
        },
        "data": {"payload": token, "nested-looking": "a: b"},
        "binaryData": {"item": "YWJj"},
        "x-preserve": {"token": token},
    })
    return cases


def contains_cidr(doc, cidr):
    for rule in doc.get("spec", {}).get("ingress", []) or []:
        for source in rule.get("from", []) or []:
            if source.get("ipBlock", {}).get("cidr") == cidr:
                return True
    return False


def assert_processed(original, actual):
    assert isinstance(actual, dict)
    assert actual.get("apiVersion") == original.get("apiVersion")
    assert actual.get("kind") == original.get("kind"), "Output kind must match its corresponding input"
    assert actual.get("x-preserve") == original.get("x-preserve")

    old_meta = original["metadata"]
    new_meta = actual.get("metadata", {})
    for key in ("name", "namespace", "annotations"):
        assert new_meta.get(key) == old_meta.get(key), f"metadata.{key} was not preserved"
    for key, value in old_meta.get("labels", {}).items():
        if original["kind"] == "Service" and key == "network-tier":
            continue
        assert new_meta.get("labels", {}).get(key) == value, f"metadata label {key} was not preserved"

    kind = original["kind"]
    if kind == "Deployment":
        expected = copy.deepcopy(original)
        if old_meta.get("namespace", "default") == "backend":
            expected["spec"]["replicas"] = 5
        assert actual == expected, "Deployment must be preserved except for the required backend replica change"
    elif kind == "Service":
        expected = copy.deepcopy(original)
        expected["metadata"].setdefault("labels", {})["network-tier"] = "secure"
        assert actual == expected, "Service must be preserved except for the required network-tier label"
    elif kind == "NetworkPolicy":
        assert contains_cidr(actual, "10.0.0.0/8"), "NetworkPolicy lacks the required ingress CIDR"
        assert actual.get("spec", {}).get("podSelector") == original["spec"]["podSelector"]
        assert actual.get("spec", {}).get("policyTypes") == original["spec"]["policyTypes"]
        new_rules = actual.get("spec", {}).get("ingress", []) or []
        new_sources = [source for rule in new_rules for source in (rule.get("from", []) or [])]
        for old_rule in original["spec"]["ingress"]:
            assert any(rule.get("ports") == old_rule.get("ports") for rule in new_rules), "Existing ingress ports were lost"
            for source in old_rule.get("from", []):
                assert source in new_sources, "Existing ingress source was lost"
    else:
        assert actual == original, "Manifest not covered by a rule must remain unchanged"


@pytest.fixture(scope="session")
def compiled_binary():
    return build_binary()


def test_01_pipeline_script_exists():
    assert os.path.isfile(PIPELINE), f"The pipeline script {PIPELINE} does not exist."
    assert os.access(PIPELINE, os.X_OK), f"The pipeline script {PIPELINE} is not executable."


def test_02_compiled_rust_processor_behavior(compiled_binary):
    cases = make_cases()
    clear_dir(INPUT)
    clear_dir(OUTPUT)
    for name, doc in cases.items():
        write_yaml(os.path.join(INPUT, name), doc)

    proc = subprocess.Popen(
        [compiled_binary],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        def complete():
            for name in cases:
                path = os.path.join(OUTPUT, name)
                if not os.path.isfile(path):
                    return False
                if read_yaml(path) is None:
                    return False
            return True
        wait_until(complete, timeout=45)
        if proc.poll() is not None:
            assert proc.returncode == 0, f"Rust processor exited with status {proc.returncode}: {proc.stderr.read()}"
    finally:
        if proc.poll() is None:
            terminate_group(proc)

    produced = {n for n in os.listdir(OUTPUT) if n.endswith((".yaml", ".yml"))}
    assert produced == set(cases), "Processor must produce one corresponding YAML output per input"
    for name, original in cases.items():
        assert_processed(original, read_yaml(os.path.join(OUTPUT, name)))


def test_03_pipeline_supervises_and_recovers_from_malformed_input():
    token = uuid.uuid4().hex
    clear_dir(INPUT)
    clear_dir(OUTPUT)

    base_name = f"base-{token}.yaml"
    recovery_name = f"recovery-{token}.yaml"
    base = {
        "apiVersion": "v1",
        "kind": "Service",
        "metadata": {"name": f"base-{token}", "namespace": "default", "labels": {"keep": token}},
        "spec": {"ports": [{"port": 81}], "selector": {"app": token}},
    }
    recovered = {
        "apiVersion": "apps/v1",
        "kind": "Deployment",
        "metadata": {"name": f"recovered-{token}", "namespace": "backend", "labels": {"keep": token}},
        "spec": {"replicas": 1, "template": {"spec": {"containers": [{"name": "c", "image": "nginx"}]}}},
    }
    write_yaml(os.path.join(INPUT, base_name), base)
    with open(os.path.join(INPUT, recovery_name), "w") as f:
        f.write("kind: Deployment\nmetadata: [this is: malformed\n")

    proc = subprocess.Popen(
        [PIPELINE],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        wait_until(lambda: os.path.isfile(os.path.join(OUTPUT, base_name)), timeout=90)
        assert_processed(base, read_yaml(os.path.join(OUTPUT, base_name)))

        time.sleep(3)
        try:
            os.killpg(proc.pid, 0)
        except ProcessLookupError:
            pytest.fail("pipeline.sh stopped instead of supervising the processor after malformed input")

        write_yaml(os.path.join(INPUT, recovery_name), recovered)

        def recovered_correctly():
            path = os.path.join(OUTPUT, recovery_name)
            if not os.path.isfile(path):
                return False
            doc = read_yaml(path)
            return doc.get("kind") == "Deployment" and doc.get("spec", {}).get("replicas") == 5
        wait_until(recovered_correctly, timeout=30)
        assert_processed(recovered, read_yaml(os.path.join(OUTPUT, recovery_name)))

        try:
            os.killpg(proc.pid, 0)
        except ProcessLookupError:
            pytest.fail("pipeline.sh did not remain supervised after recovery")
    finally:
        terminate_group(proc)


def test_04_output_manifests_generated():
    assert os.path.isdir(OUTPUT), f"The output directory {OUTPUT} does not exist."
    files = [f for f in os.listdir(OUTPUT) if f.endswith((".yaml", ".yml"))]
    assert len(files) > 0, f"No YAML files found in {OUTPUT}. The Rust processor did not generate outputs."


def test_05_manifest_accuracy_metric():
    assert os.path.isfile(EVALUATOR), f"The evaluator script {EVALUATOR} is missing."
    try:
        result = subprocess.run(
            ["python3", EVALUATOR, "--metric-only"],
            capture_output=True,
            text=True,
            check=True,
            timeout=30,
        )
    except subprocess.CalledProcessError as exc:
        pytest.fail(f"Evaluator script failed to run. stderr: {exc.stderr}")

    output = result.stdout.strip()
    try:
        metric_value = float(output)
    except ValueError:
        pytest.fail(f"Evaluator script did not output a valid float. Output was: '{output}'")

    threshold = 0.95
    assert metric_value >= threshold, (
        f"Manifest accuracy metric is {metric_value}, which is below the required threshold of {threshold}. "
        "Ensure the Rust program correctly parses and applies all rules from the image."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
