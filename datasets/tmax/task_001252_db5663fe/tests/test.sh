#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import glob
import json
import os
import re
import time

import pytest
import requests

MANIFEST_PATH = "/home/user/deployment.yaml"
LOG_PATH = "/home/user/service.log"
URL = "http://127.0.0.1:8080/manifest.yaml"


def _strip_yaml_comment(text):
    quote = None
    escaped = False
    for i, ch in enumerate(text):
        if escaped:
            escaped = False
            continue
        if ch == "\\" and quote == '"':
            escaped = True
            continue
        if quote:
            if ch == quote:
                quote = None
            continue
        if ch in ("'", '"'):
            quote = ch
        elif ch == "#" and (i == 0 or text[i - 1].isspace()):
            return text[:i].rstrip()
    return text.rstrip()


def _yaml_scalar(value):
    value = value.strip()
    if not value:
        return ""
    if value[0:1] in ("'", '"'):
        try:
            parsed = ast.literal_eval(value)
        except (SyntaxError, ValueError) as exc:
            raise AssertionError(f"Invalid quoted YAML scalar: {value}") from exc
        assert isinstance(parsed, str), f"Unsupported YAML scalar: {value}"
        return parsed
    if re.fullmatch(r"[-+]?\d+", value):
        return int(value)
    if value.lower() in ("true", "false"):
        return value.lower() == "true"
    if value.lower() in ("null", "~"):
        return None
    return value


def _parse_yaml_subset(content):
    """Parse the ordinary block-style YAML used by Kubernetes manifests."""
    stripped = content.lstrip()
    if stripped.startswith("{"):
        try:
            return json.loads(content)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"Manifest is not valid JSON/YAML: {exc}") from exc

    lines = []
    for lineno, raw in enumerate(content.splitlines(), 1):
        assert "\t" not in raw[:len(raw) - len(raw.lstrip())], \
            f"Tabs are not valid indentation (line {lineno})"
        text = _strip_yaml_comment(raw)
        if not text.strip() or text.strip() in ("---", "..."):
            continue
        indent = len(text) - len(text.lstrip(" "))
        lines.append((indent, text[indent:], lineno))

    assert lines, "Manifest is empty"

    def split_mapping(text, lineno):
        match = re.match(r"^([A-Za-z0-9_.-]+)\s*:(?:\s*(.*))?$", text)
        assert match, f"Invalid YAML mapping entry on line {lineno}: {text!r}"
        return match.group(1), match.group(2) or ""

    def parse_block(index, indent):
        assert index < len(lines), "Missing nested YAML value"
        assert lines[index][0] == indent, "Inconsistent YAML indentation"
        is_list = lines[index][1] == "-" or lines[index][1].startswith("- ")
        result = [] if is_list else {}

        while index < len(lines):
            current_indent, text, lineno = lines[index]
            if current_indent < indent:
                break
            assert current_indent == indent, f"Unexpected indentation on line {lineno}"

            if is_list:
                assert text == "-" or text.startswith("- "), \
                    f"Mixed YAML list and mapping on line {lineno}"
                rest = text[1:].strip()
                index += 1
                if not rest:
                    assert index < len(lines) and lines[index][0] > indent, \
                        f"Empty YAML list item on line {lineno}"
                    item, index = parse_block(index, lines[index][0])
                elif re.match(r"^[A-Za-z0-9_.-]+\s*:", rest):
                    key, value = split_mapping(rest, lineno)
                    item = {}
                    if value:
                        item[key] = _yaml_scalar(value)
                    else:
                        assert index < len(lines) and lines[index][0] > indent, \
                            f"Missing nested value for {key!r} on line {lineno}"
                        item[key], index = parse_block(index, lines[index][0])
                    if index < len(lines) and lines[index][0] > indent:
                        continuation, index = parse_block(index, lines[index][0])
                        assert isinstance(continuation, dict), \
                            f"List mapping continuation must be a mapping near line {lineno}"
                        assert not set(item).intersection(continuation), \
                            f"Duplicate YAML key near line {lineno}"
                        item.update(continuation)
                else:
                    item = _yaml_scalar(rest)
                result.append(item)
            else:
                assert not (text == "-" or text.startswith("- ")), \
                    f"Mixed YAML mapping and list on line {lineno}"
                key, value = split_mapping(text, lineno)
                assert key not in result, f"Duplicate YAML key {key!r} on line {lineno}"
                index += 1
                if value:
                    result[key] = _yaml_scalar(value)
                else:
                    assert index < len(lines) and lines[index][0] > indent, \
                        f"Missing nested value for {key!r} on line {lineno}"
                    result[key], index = parse_block(index, lines[index][0])

        return result, index

    document, end = parse_block(0, lines[0][0])
    assert end == len(lines), "Manifest contains trailing invalid YAML"
    return document


def _load_and_validate_manifest(content):
    manifest = _parse_yaml_subset(content)
    assert isinstance(manifest, dict), "Manifest root must be a mapping"
    assert isinstance(manifest.get("apiVersion"), str) and manifest["apiVersion"], \
        "Manifest must contain apiVersion"
    assert manifest.get("kind") == "Deployment", "Manifest kind must be Deployment"

    metadata = manifest.get("metadata")
    assert isinstance(metadata, dict), "metadata must be a mapping"
    assert metadata.get("name") == "cache-deployment", \
        "metadata.name must be cache-deployment"

    spec = manifest.get("spec")
    assert isinstance(spec, dict), "spec must be a mapping"
    assert spec.get("replicas") == 4 and not isinstance(spec.get("replicas"), bool), \
        "spec.replicas must be the integer 4"
    assert isinstance(spec.get("selector"), dict) and spec["selector"], \
        "A Deployment spec must have a non-empty selector"

    template = spec.get("template")
    assert isinstance(template, dict), "spec.template must be a mapping"
    assert isinstance(template.get("metadata"), dict), \
        "spec.template.metadata must be a mapping"
    template_spec = template.get("spec")
    assert isinstance(template_spec, dict), "spec.template.spec must be a mapping"

    containers = template_spec.get("containers")
    assert isinstance(containers, list), "spec.template.spec.containers must be a list"
    assert len(containers) == 1, "Deployment must contain exactly one container"
    container = containers[0]
    assert isinstance(container, dict), "Container entry must be a mapping"
    assert container.get("name") == "cache", "Container name must be cache"
    assert container.get("image") == "redis:6.0", "Container image must be redis:6.0"
    return manifest


def test_manifest_file_exists():
    """Test that the deployment manifest file was created."""
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file is missing: {MANIFEST_PATH}"


def test_manifest_content():
    """Keep the original content assertions and validate the actual YAML structure."""
    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    assert re.search(r"kind:\s*Deployment", content), "Manifest missing 'kind: Deployment'"
    assert re.search(r"name:\s*cache-deployment", content), "Manifest missing 'metadata.name: cache-deployment'"
    assert re.search(r"replicas:\s*4", content), "Manifest missing 'spec.replicas: 4'"
    assert re.search(r"image:\s*redis:6\.0", content), "Manifest missing 'image: redis:6.0'"
    assert re.search(r"name:\s*cache", content), "Manifest missing container 'name: cache'"

    _load_and_validate_manifest(content)


def test_web_service_and_log_rotation():
    """Keep the original endpoint, header, content, and rollover assertions."""
    try:
        response = requests.get(URL, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the web service at {URL}: {exc}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    content_type = response.headers.get("Content-Type", "")
    assert "application/x-yaml" in content_type, \
        f"Expected Content-Type 'application/x-yaml', got '{content_type}'"
    assert re.search(r"replicas:\s*4", response.text), "Response missing 'replicas: 4'"
    assert re.search(r"image:\s*redis:6\.0", response.text), "Response missing 'image: redis:6.0'"

    for _ in range(100):
        requests.get(URL, timeout=2)
    time.sleep(1)

    assert os.path.isfile(LOG_PATH), f"Log file missing: {LOG_PATH}"
    assert os.path.getsize(LOG_PATH) <= 1024, f"{LOG_PATH} exceeds 1024 bytes"
    backup_log_1 = LOG_PATH + ".1"
    assert os.path.isfile(backup_log_1), \
        f"Backup log file missing: {backup_log_1}. Log rotation may not be working."
    assert os.path.getsize(backup_log_1) <= 1024, f"{backup_log_1} exceeds 1024 bytes"


def test_endpoint_serves_the_actual_manifest_file():
    with open(MANIFEST_PATH, "rb") as f:
        expected = f.read()
    response = requests.get(URL, timeout=5)
    assert response.status_code == 200
    assert response.content == expected, \
        "GET /manifest.yaml must return the contents of /home/user/deployment.yaml"
    _load_and_validate_manifest(response.text)


def _constant_value(node, constants):
    if isinstance(node, ast.Constant):
        return node.value
    if isinstance(node, ast.Name) and node.id in constants:
        return constants[node.id]
    if isinstance(node, ast.BinOp):
        left = _constant_value(node.left, constants)
        right = _constant_value(node.right, constants)
        if isinstance(left, int) and isinstance(right, int):
            if isinstance(node.op, ast.Mult):
                return left * right
            if isinstance(node.op, ast.Add):
                return left + right
    return None


def test_rotating_file_handler_configuration_exists():
    """Verify the written service configures the required standard-library handler."""
    matching_calls = []
    sources = []
    for root in ("/home/user", "/app"):
        for path in glob.glob(root + "/**/*.py", recursive=True):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    source = f.read()
                tree = ast.parse(source, filename=path)
            except (OSError, UnicodeError, SyntaxError):
                continue
            sources.append(path)
            constants = {}
            for node in tree.body:
                if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
                    value = _constant_value(node.value, constants)
                    if value is not None:
                        constants[node.targets[0].id] = value
            for node in ast.walk(tree):
                if not isinstance(node, ast.Call):
                    continue
                if isinstance(node.func, ast.Name):
                    called = node.func.id
                elif isinstance(node.func, ast.Attribute):
                    called = node.func.attr
                else:
                    continue
                if called != "RotatingFileHandler":
                    continue
                values = {kw.arg: _constant_value(kw.value, constants)
                          for kw in node.keywords if kw.arg}
                if len(node.args) > 2:
                    values.setdefault("maxBytes", _constant_value(node.args[2], constants))
                if len(node.args) > 3:
                    values.setdefault("backupCount", _constant_value(node.args[3], constants))
                matching_calls.append((path, values))

    assert sources, "No Python web-service source was found"
    assert any(values.get("maxBytes") == 1024 and values.get("backupCount") == 3
               for _, values in matching_calls), \
        "Service must configure logging.handlers.RotatingFileHandler with maxBytes=1024 and backupCount=3"


def test_requests_are_really_logged_and_only_three_backups_are_retained():
    assert os.path.isfile(LOG_PATH), f"Log file missing: {LOG_PATH}"

    # Start from files created by the running logger, not precreated alleged evidence.
    with open(LOG_PATH, "wb"):
        pass
    for path in glob.glob(LOG_PATH + ".*"):
        if re.fullmatch(re.escape(LOG_PATH) + r"\.\d+", path):
            os.remove(path)

    session = requests.Session()
    previous_total = 0
    for i in range(5):
        response = session.get(URL, timeout=3)
        assert response.status_code == 200
        time.sleep(0.03)
        paths = [LOG_PATH] + glob.glob(LOG_PATH + ".[0-9]*")
        total = sum(os.path.getsize(path) for path in paths if os.path.isfile(path))
        assert total > previous_total, "Each incoming request must append a log record"
        previous_total = total

    # Long, distinct request targets make genuine request logging rotate repeatedly.
    for i in range(300):
        target = URL + "?rotation_audit=" + str(i).zfill(4) + "_" + ("x" * 180)
        session.get(target, timeout=3)
    time.sleep(0.5)

    numbered = []
    for path in glob.glob(LOG_PATH + ".*"):
        match = re.fullmatch(re.escape(LOG_PATH) + r"\.(\d+)", path)
        if match:
            numbered.append((int(match.group(1)), path))

    indices = sorted(index for index, _ in numbered)
    assert indices == [1, 2, 3], \
        f"Expected exactly three retained backups (.1, .2, .3), found {indices}"
    for path in [LOG_PATH] + [path for _, path in numbered]:
        assert os.path.isfile(path) and os.path.getsize(path) > 0, f"Log file is empty: {path}"
        assert os.path.getsize(path) <= 1024, f"{path} exceeds the configured 1024-byte limit"

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
