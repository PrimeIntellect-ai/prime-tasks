#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import uuid


def test_valid_files_txt():
    valid_files_path = "/home/user/valid_files.txt"
    assert os.path.isfile(valid_files_path), f"Missing {valid_files_path}"

    with open(valid_files_path, 'r') as f:
        content = f.read().splitlines()

    # doc_a1.md, doc_c3.md, and doc_d4.md are > 50 bytes
    assert "doc_a1.md" in content, "doc_a1.md should be in valid_files.txt"
    assert "doc_c3.md" in content, "doc_c3.md should be in valid_files.txt"
    assert "doc_d4.md" in content, "doc_d4.md should be in valid_files.txt"
    assert "doc_b2.md" not in content, "doc_b2.md should NOT be in valid_files.txt (<= 50 bytes)"


def test_organized_docs_structure():
    eng_file = "/home/user/organized_docs/Engineering/API_V2_Specs_r4.md"
    mkt_file = "/home/user/organized_docs/Marketing/Brand_Guide_r2.md"
    hr_file = "/home/user/organized_docs/HR/Leave_Policy_r1.md"

    assert os.path.isfile(eng_file), f"Missing {eng_file}"
    assert os.path.isfile(mkt_file), f"Missing {mkt_file}"
    assert not os.path.exists(hr_file), f"File {hr_file} should not exist (doc_b2.md was <= 50 bytes)"

    with open(eng_file, 'r') as f:
        eng_content = f.read()
    assert "This is a valid engineering document" in eng_content, "Incorrect content in Engineering doc"

    with open(mkt_file, 'r') as f:
        mkt_content = f.read()
    assert "Marketing guidelines for Q3" in mkt_content, "Incorrect content in Marketing doc"


def test_final_inventory():
    inventory_path = "/home/user/final_inventory.txt"
    assert os.path.isfile(inventory_path), f"Missing {inventory_path}"

    with open(inventory_path, 'r') as f:
        lines = [line.strip() for line in f.read().splitlines() if line.strip()]

    expected_lines = [
        "Engineering/API_V2_Specs_r4.md",
        "Marketing/Brand_Guide_r2.md"
    ]

    assert lines == expected_lines, f"Expected {inventory_path} to contain exactly {expected_lines}, but got {lines}"


def test_c_program_exists():
    c_source = "/home/user/organizer.c"
    c_bin = "/home/user/organizer"

    assert os.path.isfile(c_source), f"Missing C source file {c_source}"
    assert os.path.isfile(c_bin), f"Missing compiled binary {c_bin}"
    assert os.access(c_bin, os.X_OK), f"Binary {c_bin} is not executable"


def test_z_c_program_on_fresh_unpredictable_input():
    home = "/home/user"
    source = os.path.join(home, "organizer.c")
    binary = os.path.join(home, "organizer")

    # Compile the submitted source so the behavior being exercised must come
    # from organizer.c, then execute the required artifact at its required path.
    result = subprocess.run(
        ["gcc", "-std=c11", "-Wall", "-Wextra", source, "-o", binary],
        text=True, capture_output=True, timeout=20
    )
    assert result.returncode == 0, f"organizer.c did not compile:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(binary) and os.access(binary, os.X_OK)

    token = uuid.uuid4().hex[:10]
    first = f"alpha_{token}.md"
    second = f"beta_{token}.md"
    listed_without_metadata = f"orphan_{token}.md"
    metadata_but_not_listed = f"excluded_{token}.md"
    dept1 = f"DeptA_{token}"
    dept2 = f"DeptB_{token}"
    title1 = f"Generated_Title_A_{token}"
    title2 = f"Generated_Title_B_{token}"
    excluded_title = f"Must_Not_Move_{token}"
    content1 = f"dynamic first document {token}\n"
    content2 = f"dynamic second document {token}\n"
    orphan_content = f"dynamic orphan document {token}\n"
    excluded_content = f"dynamic excluded document {token}\n"

    raw_dir = os.path.join(home, "raw_docs")
    organized_dir = os.path.join(home, "organized_docs")
    shutil.rmtree(raw_dir, ignore_errors=True)
    shutil.rmtree(organized_dir, ignore_errors=True)
    os.makedirs(raw_dir)

    files = {
        first: content1,
        second: content2,
        listed_without_metadata: orphan_content,
        metadata_but_not_listed: excluded_content,
    }
    for name, data in files.items():
        with open(os.path.join(raw_dir, name), "w") as f:
            f.write(data)

    with open(os.path.join(home, "metadata.csv"), "w") as f:
        f.write(f"{first},{dept1},{title1},7\n")
        f.write(f"{second},{dept2},{title2},13\n")
        f.write(f"{metadata_but_not_listed},{dept1},{excluded_title},99\n")

    # The orphan is valid/listed but has no CSV row. The excluded file has a
    # CSV row but is not valid/listed. Neither may be organized.
    with open(os.path.join(home, "valid_files.txt"), "w") as f:
        f.write(first + "\n")
        f.write(second + "\n")
        f.write(listed_without_metadata + "\n")

    run = subprocess.run(
        [binary], cwd=home, text=True, capture_output=True, timeout=20
    )
    assert run.returncode == 0, f"organizer failed:\n{run.stdout}\n{run.stderr}"

    expected1 = os.path.join(organized_dir, dept1, f"{title1}_r7.md")
    expected2 = os.path.join(organized_dir, dept2, f"{title2}_r13.md")
    assert os.path.isfile(expected1), f"Missing dynamically organized file {expected1}"
    assert os.path.isfile(expected2), f"Missing dynamically organized file {expected2}"
    with open(expected1) as f:
        assert f.read() == content1
    with open(expected2) as f:
        assert f.read() == content2

    assert not os.path.exists(os.path.join(raw_dir, first)), "First matched source was not moved"
    assert not os.path.exists(os.path.join(raw_dir, second)), "Second matched source was not moved"
    assert os.path.isfile(os.path.join(raw_dir, listed_without_metadata)), "Listed file without metadata must be ignored"
    assert os.path.isfile(os.path.join(raw_dir, metadata_but_not_listed)), "Metadata file absent from valid_files.txt must be ignored"
    assert not os.path.exists(os.path.join(organized_dir, dept1, f"{excluded_title}_r99.md"))

    actual = []
    for root, _, names in os.walk(organized_dir):
        for name in names:
            actual.append(os.path.relpath(os.path.join(root, name), organized_dir))
    expected = sorted([
        os.path.join(dept1, f"{title1}_r7.md"),
        os.path.join(dept2, f"{title2}_r13.md"),
    ])
    assert sorted(actual) == expected, f"Unexpected dynamically organized files: {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
