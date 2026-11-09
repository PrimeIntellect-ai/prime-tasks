#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import secrets
import subprocess
import tempfile
from lib2to3.refactor import RefactoringTool

import pytest

MIGRATOR = "/home/user/migrator.py"
REFRACTOR = RefactoringTool([
    "lib2to3.fixes.fix_print",
    "lib2to3.fixes.fix_xrange",
    "lib2to3.fixes.fix_dict",
])


def reference_tree(source):
    source = source.rstrip("\n") + "\n"
    converted = str(REFRACTOR.refactor_string(source, "input.py"))
    return ast.parse(converted)


class CanonicalizeDictIteration(ast.NodeTransformer):
    """Accept both items() and 2to3's equivalent iter(items()) form."""
    def visit_Call(self, node):
        node = self.generic_visit(node)
        if (
            isinstance(node.func, ast.Name)
            and node.func.id == "iter"
            and len(node.args) == 1
            and not node.keywords
            and isinstance(node.args[0], ast.Call)
            and isinstance(node.args[0].func, ast.Attribute)
            and node.args[0].func.attr in {"items", "keys", "values"}
            and not node.args[0].args
            and not node.args[0].keywords
        ):
            return node.args[0]
        return node


def canonical_dump(tree):
    tree = CanonicalizeDictIteration().visit(tree)
    ast.fix_missing_locations(tree)
    return ast.dump(tree, include_attributes=False)


def run_migrator(input_path, output_path):
    return subprocess.run(
        ["python3", MIGRATOR, input_path, output_path],
        capture_output=True,
        timeout=10,
    )


def assert_correct_migration(source, label="generated input"):
    token = secrets.token_hex(8)
    with tempfile.TemporaryDirectory() as tmpdir:
        input_path = os.path.join(tmpdir, f"input_{token}.py")
        output_path = os.path.join(tmpdir, f"output_{token}.py")
        with open(input_path, "w") as f:
            f.write(source)

        result = run_migrator(input_path, output_path)
        assert result.returncode == 0, (
            f"Migrator rejected safe {label}: {result.stderr.decode(errors='replace')}"
        )
        assert os.path.isfile(output_path), f"Migrator did not create output for safe {label}"

        with open(output_path, "r") as f:
            output_code = f.read()
        assert output_code.strip(), f"Migrator emitted empty code for safe {label}"

        try:
            actual = ast.parse(output_code)
        except SyntaxError as exc:
            pytest.fail(f"Migrator emitted invalid Python 3 for safe {label}: {exc}")

        expected = reference_tree(source)
        assert canonical_dump(actual) == canonical_dump(expected), (
            f"Migrated code did not preserve the program structure and Python 2-to-3 "
            f"rewrites for {label}. Output was: {output_code!r}"
        )


def test_schema_version_txt():
    schema_file = "/home/user/schema_version.txt"
    assert os.path.exists(schema_file), f"Missing output artifact: {schema_file}"

    with open(schema_file, "r") as f:
        content = f.read().strip()

    assert content == "42", f"Expected schema version '42', but found '{content}' in {schema_file}"


def test_migrator_exists():
    migrator_script = "/home/user/migrator.py"
    assert os.path.exists(migrator_script), f"Missing migrator script: {migrator_script}"
    assert os.path.isfile(migrator_script), f"Path is not a file: {migrator_script}"


def test_migrator_evil_corpus():
    evil_dir = "/app/corpus/evil/"
    assert os.path.exists(evil_dir), f"Missing evil corpus directory: {evil_dir}"
    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    bypassed_files = []
    dirty_outputs = []

    with tempfile.TemporaryDirectory() as tmpdir:
        for filename in evil_files:
            input_path = os.path.join(evil_dir, filename)
            output_path = os.path.join(tmpdir, filename)
            result = run_migrator(input_path, output_path)

            if result.returncode != 1:
                bypassed_files.append(filename)
            if os.path.exists(output_path) and os.path.getsize(output_path) != 0:
                dirty_outputs.append(filename)

    assert not bypassed_files, (
        f"{len(bypassed_files)} of {len(evil_files)} evil files bypassed rejection: "
        f"{', '.join(bypassed_files)}"
    )
    assert not dirty_outputs, (
        "Rejected evil inputs must not leave non-empty output files: " + ", ".join(dirty_outputs)
    )


def test_migrator_clean_corpus():
    clean_dir = "/app/corpus/clean/"
    assert os.path.exists(clean_dir), f"Missing clean corpus directory: {clean_dir}"
    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    failed_files = []
    invalid_ast_files = []
    incorrect_files = []

    with tempfile.TemporaryDirectory() as tmpdir:
        for filename in clean_files:
            input_path = os.path.join(clean_dir, filename)
            output_path = os.path.join(tmpdir, filename)
            result = run_migrator(input_path, output_path)

            if result.returncode != 0:
                failed_files.append(filename)
                continue

            if not os.path.exists(output_path):
                failed_files.append(filename)
                continue

            with open(output_path, "r") as f:
                output_code = f.read()

            try:
                output_tree = ast.parse(output_code)
            except SyntaxError:
                invalid_ast_files.append(filename)
                continue

            with open(input_path, "r") as f:
                source = f.read()
            if not output_code.strip() or canonical_dump(output_tree) != canonical_dump(reference_tree(source)):
                incorrect_files.append(filename)

    error_msg = []
    if failed_files:
        error_msg.append(f"{len(failed_files)} of {len(clean_files)} clean files failed migration (non-zero exit code or missing output): {', '.join(failed_files)}")
    if invalid_ast_files:
        error_msg.append(f"{len(invalid_ast_files)} of {len(clean_files)} clean files resulted in invalid Python 3 code: {', '.join(invalid_ast_files)}")
    if incorrect_files:
        error_msg.append(f"{len(incorrect_files)} of {len(clean_files)} clean files were not correctly transpiled or had their program structure changed: {', '.join(incorrect_files)}")

    assert not failed_files and not invalid_ast_files and not incorrect_files, " | ".join(error_msg)


def test_unseen_safe_programs_are_transpiled_without_semantic_loss():
    a = secrets.randbelow(80) + 11
    b = secrets.randbelow(30) + 2
    n = secrets.randbelow(7) + 2
    key = "k_" + secrets.token_hex(4)

    safe_sources = [
        f'print "value", {a} + {b}',
        f'for idx_{secrets.token_hex(3)} in xrange({n}): print idx_{secrets.token_hex(3)}',
        f'values_{secrets.token_hex(3)} = xrange({n})',
        f'd_{secrets.token_hex(3)} = {{"{key}": {a}}}; d_{secrets.token_hex(3)}.iterkeys()',
        f'print ({a} * {b}) > ({a} - {b})',
    ]

    # Build the two statements that need the same randomized identifier separately.
    loop_name = "i_" + secrets.token_hex(4)
    dict_name = "d_" + secrets.token_hex(4)
    safe_sources[1] = f'for {loop_name} in xrange({n}): print {loop_name}'
    safe_sources[3] = f'{dict_name} = {{"{key}": {a}}}; {dict_name}.iteritems()'

    for index, source in enumerate(safe_sources):
        assert_correct_migration(source, f"unseen safe case {index}")


def test_unseen_unsafe_programs_are_rejected_and_do_not_overwrite_output():
    marker = "DO_NOT_REPLACE_" + secrets.token_hex(12)
    module = "o" + "s"
    unsafe_sources = [
        f'__import__("{module}").system("echo {marker}")',
        f'(__import__)("{module}").popen("id").read()',
        f'eval ("{secrets.randbelow(999)} + 1")',
        f'exec ("x_{secrets.token_hex(3)} = 1")',
        f'import {module} as m_{secrets.token_hex(3)}; m_{secrets.token_hex(3)}.system("id")',
        f'getattr(__builtins__, "ev" + "al")("1")',
        f'open("/tmp/{marker}", "w").write("bad")',
        f'(lambda: {secrets.randbelow(100)})()',
        f'().__class__.__base__.__subclasses__()',
        f'[__import__("{module}") for x_{secrets.token_hex(3)} in range(1)]',
    ]

    # Ensure the import alias is internally consistent.
    alias = "m_" + secrets.token_hex(4)
    unsafe_sources[4] = f'import {module} as {alias}; {alias}.system("id")'

    with tempfile.TemporaryDirectory() as tmpdir:
        for index, source in enumerate(unsafe_sources):
            input_path = os.path.join(tmpdir, f"unsafe_{secrets.token_hex(8)}.py")
            output_path = os.path.join(tmpdir, f"out_{secrets.token_hex(8)}.py")
            with open(input_path, "w") as f:
                f.write(source)
            with open(output_path, "w") as f:
                f.write(marker)

            result = run_migrator(input_path, output_path)
            assert result.returncode == 1, f"Unsafe generated case {index} was not rejected"
            with open(output_path, "r") as f:
                remaining = f.read()
            assert remaining in ("", marker), (
                f"Unsafe generated case {index} improperly wrote output"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
