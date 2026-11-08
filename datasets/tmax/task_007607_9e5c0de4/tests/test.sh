#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pathlib
import secrets
import shutil
import subprocess

BASE = pathlib.Path('/home/user/release_prep')
DEPLOY = BASE / 'deploy.py'
RULES = BASE / 'deploy_rules.txt'
METRICS = BASE / 'metrics.json'
PATCHES = BASE / 'patches'
SETTINGS = BASE / 'config' / 'settings.ini'
CONSOLIDATED = BASE / 'consolidated.patch'
REPORT = pathlib.Path('/home/user/deploy_report.json')

BASE_SETTINGS = '''[database]
host = localhost
port = 5432

[cache]
enabled = false
'''


def run_deploy():
    assert DEPLOY.is_file(), f'deploy.py missing at {DEPLOY}'
    result = subprocess.run(
        ['python3', str(DEPLOY)],
        cwd=str(BASE),
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f'deploy.py failed with exit code {result.returncode}\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def read_report():
    assert REPORT.is_file(), f'Deploy report missing at {REPORT}'
    try:
        return json.loads(REPORT.read_text())
    except json.JSONDecodeError as exc:
        raise AssertionError(f'Deploy report is not valid JSON: {exc}')


def clear_outputs():
    CONSOLIDATED.unlink(missing_ok=True)
    REPORT.unlink(missing_ok=True)


def test_deploy_script_and_agent_tests_execute():
    assert DEPLOY.is_file(), f'deploy.py missing at {DEPLOY}'
    assert DEPLOY.is_file() and not DEPLOY.is_dir(), 'deploy.py must be a regular file'

    test_path = BASE / 'test_deploy.py'
    assert test_path.is_file(), f'Test file missing at {test_path}'
    result = subprocess.run(
        ['python3', '-m', 'pytest', '-q', str(test_path)],
        cwd=str(BASE),
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f'Agent tests were not successfully executed\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def test_deploy_behavior_on_derived_inputs_and_restore_final_state():
    saved_rules = RULES.read_bytes()
    saved_metrics = METRICS.read_bytes()
    saved_patches = {p.name: p.read_bytes() for p in PATCHES.iterdir() if p.is_file()}
    token = secrets.token_hex(4)

    try:
        # First exercise a false expression. No patch may be created or applied.
        SETTINGS.write_text(BASE_SETTINGS)
        clear_outputs()
        METRICS.write_text(json.dumps({
            'coverage': 41,
            'tests_passed': True,
            'lint_errors': 3,
        }))
        RULES.write_text('(coverage >= 90) OR (tests_passed == false)\n')
        run_deploy()
        false_report = read_report()
        assert false_report.get('rules_evaluated_to') is False
        assert false_report.get('applied_patches') == []
        assert false_report.get('final_patch_created') is False
        assert not CONSOLIDATED.exists(), 'False rules must not create consolidated.patch'
        assert SETTINGS.read_text() == BASE_SETTINGS, 'False rules must not alter settings.ini'

        # Replace the patch set with unpredictable filenames and values so the
        # implementation must discover, alphabetically sort, merge, and apply it.
        shutil.rmtree(PATCHES)
        PATCHES.mkdir()
        db_name = f'10-{token}-db.diff'
        cache_name = f'20-{token}-cache.diff'
        db_host = f'db-{token}.internal'
        db_diff = (
            '--- settings.ini\n'
            '+++ settings.ini\n'
            '@@ -1,3 +1,3 @@\n'
            ' [database]\n'
            '-host = localhost\n'
            f'+host = {db_host}\n'
            ' port = 5432\n'
        )
        cache_diff = (
            '--- settings.ini\n'
            '+++ settings.ini\n'
            '@@ -5,2 +5,2 @@\n'
            ' [cache]\n'
            '-enabled = false\n'
            '+enabled = true\n'
        )
        # Deliberately create them in reverse lexical order.
        (PATCHES / cache_name).write_text(cache_diff)
        (PATCHES / db_name).write_text(db_diff)

        SETTINGS.write_text(BASE_SETTINGS)
        clear_outputs()
        METRICS.write_text(json.dumps({
            'coverage': 73,
            'tests_passed': False,
            'lint_errors': 0,
        }))
        RULES.write_text(
            '(coverage >= 73) AND ((lint_errors == 0) OR (tests_passed == true))\n'
        )
        run_deploy()

        true_report = read_report()
        expected_names = sorted([db_name, cache_name])
        expected_merged = ''.join((PATCHES / name).read_text() for name in expected_names)
        assert true_report.get('rust_compiled') is True
        assert true_report.get('rules_evaluated_to') is True
        assert true_report.get('applied_patches') == expected_names
        assert true_report.get('final_patch_created') is True
        assert CONSOLIDATED.is_file()
        assert CONSOLIDATED.read_text() == expected_merged, (
            'consolidated.patch is not the alphabetical concatenation of the .diff files'
        )
        final_settings = SETTINGS.read_text()
        assert f'host = {db_host}' in final_settings
        assert 'enabled = true' in final_settings
        assert 'host = localhost' not in final_settings
        assert 'enabled = false' not in final_settings
    finally:
        RULES.write_bytes(saved_rules)
        METRICS.write_bytes(saved_metrics)
        shutil.rmtree(PATCHES, ignore_errors=True)
        PATCHES.mkdir()
        for name, data in saved_patches.items():
            (PATCHES / name).write_bytes(data)

    # Run the requested supplied-input deployment last, leaving the final state
    # exactly as required by the task.
    SETTINGS.write_text(BASE_SETTINGS)
    clear_outputs()
    run_deploy()


def test_rust_core_compiles():
    cargo_toml = '/home/user/release_prep/core/Cargo.toml'
    assert os.path.isfile(cargo_toml), f'Cargo.toml missing at {cargo_toml}'

    result = subprocess.run(
        ['cargo', 'check', '--manifest-path', cargo_toml],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f'Rust project failed to compile:\n{result.stderr}'

    # Also execute get_config_name and prove it returns the name without moving
    # it out of the borrowed Config.
    probe = pathlib.Path('/tmp/rust_config_probe.rs')
    binary = pathlib.Path('/tmp/rust_config_probe')
    probe.write_text(r'''
#[path = "/home/user/release_prep/core/src/lib.rs"]
mod release_core;
use release_core::{Config, get_config_name};

fn main() {
    let config = Config { name: String::from("release-name") };
    let returned = get_config_name(&config);
    assert_eq!(returned, "release-name");
    assert_eq!(config.name, "release-name");
}
''')
    compiled = subprocess.run(
        ['rustc', '--edition=2021', str(probe), '-o', str(binary)],
        capture_output=True,
        text=True,
    )
    assert compiled.returncode == 0, f'Rust behavior probe did not compile:\n{compiled.stderr}'
    executed = subprocess.run([str(binary)], capture_output=True, text=True)
    assert executed.returncode == 0, f'get_config_name behavior probe failed:\n{executed.stderr}'


def test_deploy_report_exists_and_matches():
    report_path = '/home/user/deploy_report.json'
    assert os.path.isfile(report_path), f'Deploy report missing at {report_path}'

    with open(report_path, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            assert False, f'Deploy report at {report_path} is not valid JSON'

    assert report.get('rust_compiled') is True, "Expected 'rust_compiled' to be true"
    assert report.get('rules_evaluated_to') is True, "Expected 'rules_evaluated_to' to be true"
    assert report.get('applied_patches') == ['01-update-db.diff', '02-update-cache.diff'], "Expected 'applied_patches' to match the specific list"
    assert report.get('final_patch_created') is True, "Expected 'final_patch_created' to be true"


def test_consolidated_patch_created():
    patch_path = '/home/user/release_prep/consolidated.patch'
    assert os.path.isfile(patch_path), f'Consolidated patch missing at {patch_path}'


def test_settings_ini_patched():
    settings_path = '/home/user/release_prep/config/settings.ini'
    assert os.path.isfile(settings_path), f'Settings file missing at {settings_path}'

    with open(settings_path, 'r') as f:
        content = f.read()

    assert 'host = db.internal' in content, "settings.ini not patched correctly: missing 'host = db.internal'"
    assert 'enabled = true' in content, "settings.ini not patched correctly: missing 'enabled = true'"
    assert 'host = localhost' not in content, "settings.ini still contains 'host = localhost'"
    assert 'enabled = false' not in content, "settings.ini still contains 'enabled = false'"


def test_test_deploy_py_exists():
    test_path = '/home/user/release_prep/test_deploy.py'
    assert os.path.isfile(test_path), f'Test file missing at {test_path}'

    with open(test_path, 'r') as f:
        content = f.read()
        assert 'def test_' in content or 'class Test' in content, 'Test file does not appear to contain any tests'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
