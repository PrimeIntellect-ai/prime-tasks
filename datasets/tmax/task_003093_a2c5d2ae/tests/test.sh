#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import glob
import importlib.util
import json
import os
import secrets
import shutil
import subprocess
import tempfile


def parse_loc_reference(filepath):
    """Reference implementation to parse .loc files correctly."""
    result = {}
    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.read().splitlines()

    current_key = None
    for line in lines:
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if line.startswith('[') and line.endswith(']'):
            current_key = line[1:-1]
        elif current_key:
            result[current_key] = line
            current_key = None
    return result


def populate_reference(template_node, translations):
    """Recursively populate the template with translations."""
    if isinstance(template_node, dict):
        return {k: populate_reference(v, translations) if isinstance(v, (dict, list)) else translations.get(k, "") for k, v in template_node.items()}
    elif isinstance(template_node, list):
        return [populate_reference(v, translations) for v in template_node]
    return template_node


def flatten_dict(d, parent_key='', sep='.'):
    items = []
    for k, v in d.items():
        new_key = f"{parent_key}{sep}{k}" if parent_key else k
        if isinstance(v, dict):
            items.extend(flatten_dict(v, new_key, sep=sep).items())
        else:
            items.append((new_key, v))
    return dict(items)


def test_translation_accuracy():
    data_dir = "/home/user/data"
    output_dir = "/home/user/output"
    template_file = "/home/user/template.json"

    assert os.path.exists(template_file), f"Template file {template_file} is missing."
    with open(template_file, 'r', encoding='utf-8') as f:
        template = json.load(f)

    loc_files = glob.glob(os.path.join(data_dir, "*.loc"))
    assert len(loc_files) > 0, "No .loc files found to process."

    total_keys = 0
    correct_keys = 0

    for loc_file in loc_files:
        basename = os.path.basename(loc_file)
        lang = os.path.splitext(basename)[0]
        output_file = os.path.join(output_dir, f"{lang}.json")

        translations = parse_loc_reference(loc_file)
        expected_json = populate_reference(template, translations)
        expected_flat = flatten_dict(expected_json)

        total_keys += len(expected_flat)

        if not os.path.exists(output_file):
            continue

        try:
            with open(output_file, 'r', encoding='utf-8') as f:
                actual_json = json.load(f)
            actual_flat = flatten_dict(actual_json)

            for k, v in expected_flat.items():
                if actual_flat.get(k) == v:
                    correct_keys += 1
        except Exception:
            pass

    assert total_keys > 0, "No keys found in the template."
    accuracy = correct_keys / total_keys
    assert accuracy >= 0.98, f"Accuracy {accuracy:.4f} is below the threshold of 0.98. Correct: {correct_keys}, Total: {total_keys}"


def test_pipeline_log():
    log_file = "/home/user/pipeline.log"
    assert os.path.exists(log_file), f"Log file {log_file} does not exist."

    with open(log_file, 'r', encoding='utf-8') as f:
        log_content = f.read()

    data_dir = "/home/user/data"
    loc_files = glob.glob(os.path.join(data_dir, "*.loc"))

    for loc_file in loc_files:
        basename = os.path.basename(loc_file)
        translations = parse_loc_reference(loc_file)
        expected_log_entry = f"[INFO] Processed {basename}: extracted {len(translations)} keys."
        assert expected_log_entry in log_content, f"Expected log entry not found: {expected_log_entry}"


def test_locparse_package_is_fixed():
    package_dir = "/app/locparse/locparse"
    parser_file = os.path.join(package_dir, "parser.py")
    init_file = os.path.join(package_dir, "__init__.py")
    assert os.path.isdir(package_dir), "The locparse package directory is missing."
    assert os.path.isfile(parser_file), "locparse/parser.py is missing."
    assert os.path.isfile(init_file), "locparse/__init__.py is missing."

    spec = importlib.util.spec_from_file_location("submitted_locparse_parser", parser_file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, "parse", None)), "locparse.parser.parse is missing."

    token = secrets.token_hex(10)
    text = f"# block\n[FIRST]\nfirst-{token}\n\n[FINAL]\nfinal-{token}"
    assert module.parse(text) == {
        "FIRST": f"first-{token}",
        "FINAL": f"final-{token}",
    }, "locparse still fails to extract a translation whose value is the final line."


def _write_fixture(data_dir, filename, values):
    content = (
        "# generated verification block\n"
        f"[GREETING]\n{values['GREETING']}\n"
        f"[FAREWELL]\n{values['FAREWELL']}\n"
        f"[ERROR_404]\n{values['ERROR_404']}"
    )
    with open(os.path.join(data_dir, filename), 'w', encoding='utf-8') as f:
        f.write(content)


def _run_script(script, env=None):
    completed = subprocess.run(
        ["python3", script],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert completed.returncode == 0, (
        f"process_loc.py failed with exit code {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )


def test_process_script_executes_and_uses_locparse():
    script = "/home/user/process_loc.py"
    assert os.path.isfile(script), f"Python script {script} does not exist."

    with open(script, 'r', encoding='utf-8') as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=script)
    except SyntaxError as exc:
        raise AssertionError(f"process_loc.py is not valid Python: {exc}")
    imports_locparse = any(
        (isinstance(node, ast.Import) and any(alias.name == "locparse" or alias.name.startswith("locparse.") for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module and (node.module == "locparse" or node.module.startswith("locparse.")))
        for node in ast.walk(tree)
    )
    assert imports_locparse, "process_loc.py must import and use the locparse package."

    data_dir = "/home/user/data"
    output_dir = "/home/user/output"
    template_file = "/home/user/template.json"
    log_file = "/home/user/pipeline.log"
    backup_root = tempfile.mkdtemp(prefix="loc-verifier-backup-")

    try:
        shutil.move(data_dir, os.path.join(backup_root, "data"))
        shutil.move(output_dir, os.path.join(backup_root, "output"))
        shutil.move(template_file, os.path.join(backup_root, "template.json"))
        if os.path.exists(log_file):
            shutil.move(log_file, os.path.join(backup_root, "pipeline.log"))

        os.makedirs(data_dir)
        os.makedirs(output_dir)
        template = {"messages": {"GREETING": "", "FAREWELL": "", "ERROR_404": ""}}
        with open(template_file, 'w', encoding='utf-8') as f:
            json.dump(template, f)

        token = secrets.token_hex(12)
        fixtures = {
            "generated_a.loc": {
                "GREETING": f"hello-{token}",
                "FAREWELL": f"bye-{token}",
                "ERROR_404": f"missing-{token}",
            },
            "generated_b.loc": {
                "GREETING": f"bonjour-{token}",
                "FAREWELL": f"salut-{token}",
                "ERROR_404": f"absent-{token}",
            },
        }
        for filename, values in fixtures.items():
            _write_fixture(data_dir, filename, values)

        _run_script(script)

        for filename, values in fixtures.items():
            language = os.path.splitext(filename)[0]
            output_file = os.path.join(output_dir, language + ".json")
            assert os.path.isfile(output_file), f"Script did not create {output_file}."
            with open(output_file, 'r', encoding='utf-8') as f:
                actual = json.load(f)
            assert actual == {"messages": values}, f"Incorrect generated JSON for {filename}."

        assert os.path.isfile(log_file), "Script did not create pipeline.log when executed."
        with open(log_file, 'r', encoding='utf-8') as f:
            log_lines = f.read().splitlines()
        for filename in fixtures:
            expected = f"[INFO] Processed {filename}: extracted 3 keys."
            assert expected in log_lines, f"Expected runtime log entry not found: {expected}"

        # Run again with a shadow locparse package whose parse result is deliberately
        # different from the file contents. The generated output must reflect the
        # package result, proving that the script actually calls and uses locparse.
        shutil.rmtree(output_dir)
        os.makedirs(output_dir)
        if os.path.exists(log_file):
            os.remove(log_file)

        stub_root = tempfile.mkdtemp(prefix="locparse-probe-")
        stub_package = os.path.join(stub_root, "locparse")
        os.makedirs(stub_package)
        call_file = os.path.join(stub_root, "calls.txt")
        probe = secrets.token_hex(10)
        stub_source = f'''import os\n\ndef parse(text):\n    with open(os.environ["LOCPARSE_CALL_FILE"], "a", encoding="utf-8") as handle:\n        handle.write("called\\n")\n    return {{"GREETING": "probe-g-{probe}", "FAREWELL": "probe-f-{probe}", "ERROR_404": "probe-e-{probe}"}}\n'''
        with open(os.path.join(stub_package, "__init__.py"), 'w', encoding='utf-8') as f:
            f.write("from .parser import parse\n")
        with open(os.path.join(stub_package, "parser.py"), 'w', encoding='utf-8') as f:
            f.write(stub_source)

        env = os.environ.copy()
        env["PYTHONPATH"] = stub_root + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
        env["LOCPARSE_CALL_FILE"] = call_file
        _run_script(script, env=env)

        assert os.path.isfile(call_file), "process_loc.py did not call locparse.parse."
        with open(call_file, 'r', encoding='utf-8') as f:
            calls = f.read().splitlines()
        assert len(calls) >= len(fixtures), "locparse.parse was not called for every .loc file."

        expected_probe = {
            "messages": {
                "GREETING": f"probe-g-{probe}",
                "FAREWELL": f"probe-f-{probe}",
                "ERROR_404": f"probe-e-{probe}",
            }
        }
        for filename in fixtures:
            language = os.path.splitext(filename)[0]
            output_file = os.path.join(output_dir, language + ".json")
            assert os.path.isfile(output_file), f"Probe run did not create {output_file}."
            with open(output_file, 'r', encoding='utf-8') as f:
                actual = json.load(f)
            assert actual == expected_probe, "process_loc.py ignored the translations returned by locparse."
    finally:
        for path in (data_dir, output_dir):
            if os.path.exists(path):
                shutil.rmtree(path)
        for path in (template_file, log_file):
            if os.path.exists(path):
                os.remove(path)

        if os.path.exists(os.path.join(backup_root, "data")):
            shutil.move(os.path.join(backup_root, "data"), data_dir)
        if os.path.exists(os.path.join(backup_root, "output")):
            shutil.move(os.path.join(backup_root, "output"), output_dir)
        if os.path.exists(os.path.join(backup_root, "template.json")):
            shutil.move(os.path.join(backup_root, "template.json"), template_file)
        if os.path.exists(os.path.join(backup_root, "pipeline.log")):
            shutil.move(os.path.join(backup_root, "pipeline.log"), log_file)
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
