#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import subprocess


def make_query(subject, min_year, sort_by, limit, offset):
    return "\n".join([
        "PREFIX ex: <http://example.org/>",
        "PREFIX foaf: <http://xmlns.com/foaf/0.1/>",
        "",
        "SELECT ?paper ?title ?year ?citations",
        "WHERE {",
        f"  ?paper ex:hasSubject <{subject}> .",
        "  ?paper foaf:title ?title .",
        "  ?paper ex:year ?year .",
        "  ?paper ex:citations ?citations .",
        f"  FILTER(?year >= {min_year})",
        "}",
        f"ORDER BY DESC(?{sort_by}) ASC(?paper)",
        f"LIMIT {limit}",
        f"OFFSET {offset}",
        "",
    ])


def run_generator(path, subject, min_year, sort_by, limit, offset):
    result = subprocess.run([
        path,
        "--subject", subject,
        "--min-year", str(min_year),
        "--sort-by", sort_by,
        "--limit", str(limit),
        "--offset", str(offset),
    ], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10)
    assert result.returncode == 0, result.stderr
    return result.stdout


def fixed_expected_content():
    return """PREFIX ex: <http://example.org/>
PREFIX foaf: <http://xmlns.com/foaf/0.1/>

SELECT ?paper ?title ?year ?citations
WHERE {
  ?paper ex:hasSubject <ex:MachineLearning> .
  ?paper foaf:title ?title .
  ?paper ex:year ?year .
  ?paper ex:citations ?citations .
  FILTER(?year >= 2018)
}
ORDER BY DESC(?citations) ASC(?paper)
LIMIT 50
OFFSET 0

PREFIX ex: <http://example.org/>
PREFIX foaf: <http://xmlns.com/foaf/0.1/>

SELECT ?paper ?title ?year ?citations
WHERE {
  ?paper ex:hasSubject <ex:Bioinformatics> .
  ?paper foaf:title ?title .
  ?paper ex:year ?year .
  ?paper ex:citations ?citations .
  FILTER(?year >= 2020)
}
ORDER BY DESC(?year) ASC(?paper)
LIMIT 10
OFFSET 20

PREFIX ex: <http://example.org/>
PREFIX foaf: <http://xmlns.com/foaf/0.1/>

SELECT ?paper ?title ?year ?citations
WHERE {
  ?paper ex:hasSubject <ex:QuantumComputing> .
  ?paper foaf:title ?title .
  ?paper ex:year ?year .
  ?paper ex:citations ?citations .
  FILTER(?year >= 2015)
}
ORDER BY DESC(?citations) ASC(?paper)
LIMIT 100
OFFSET 50
"""


def test_files_exist():
    """Ensure all required files exist."""
    assert os.path.isfile("/home/user/sparql_gen.cpp"), "Source file /home/user/sparql_gen.cpp is missing."
    assert os.path.isfile("/home/user/sparql_gen"), "Executable /home/user/sparql_gen is missing."
    assert os.path.isfile("/home/user/generate.sh"), "Script /home/user/generate.sh is missing."
    assert os.path.isfile("/home/user/queries.sparql"), "Output file /home/user/queries.sparql is missing."


def test_executables():
    """Ensure the compiled binary and bash script are executable."""
    gen_stat = os.stat("/home/user/sparql_gen")
    assert gen_stat.st_mode & stat.S_IXUSR, "/home/user/sparql_gen is not executable."

    sh_stat = os.stat("/home/user/generate.sh")
    assert sh_stat.st_mode & stat.S_IXUSR, "/home/user/generate.sh is not executable."

    with open("/home/user/sparql_gen", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/sparql_gen is not a compiled executable."


def test_queries_sparql_content():
    """Check that the generated SPARQL queries match the expected output exactly."""
    with open("/home/user/queries.sparql", "r") as f:
        actual_content = f.read()

    assert actual_content.strip() == fixed_expected_content().strip(), "The contents of /home/user/queries.sparql do not match the expected output."


def test_cpp_source_and_binary_handle_dynamic_arguments():
    """Compile the submitted source and exercise both artifacts on unpredictable inputs."""
    rebuilt = f"/tmp/sparql_gen_rebuilt_{os.getpid()}"
    result = subprocess.run([
        "g++", "-std=c++17", "-o", rebuilt, "/home/user/sparql_gen.cpp"
    ], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30)
    assert result.returncode == 0, "sparql_gen.cpp does not compile as C++17:\n" + result.stderr

    try:
        cases = []
        for i in range(4):
            cases.append((
                f"urn:verification:{secrets.token_hex(12)}",
                1700 + secrets.randbelow(500),
                "year" if i % 2 else "citations",
                1 + secrets.randbelow(500),
                secrets.randbelow(1000),
            ))

        for case in cases:
            expected = make_query(*case)
            assert run_generator("/home/user/sparql_gen", *case) == expected
            assert run_generator(rebuilt, *case) == expected
    finally:
        if os.path.exists(rebuilt):
            os.remove(rebuilt)


def test_generate_script_executes_generator_three_times():
    """Run generate.sh and verify its generator invocations and resulting file."""
    binary = "/home/user/sparql_gen"
    saved_binary = f"/tmp/sparql_gen_saved_{os.getpid()}"
    call_log = f"/tmp/sparql_gen_calls_{os.getpid()}.jsonl"
    os.replace(binary, saved_binary)

    wrapper = f'''#!/usr/bin/python3
import json
import os
import sys
with open({call_log!r}, "a") as f:
    json.dump(sys.argv[1:], f)
    f.write("\\n")
os.execv({saved_binary!r}, [{saved_binary!r}] + sys.argv[1:])
'''
    try:
        with open(binary, "w") as f:
            f.write(wrapper)
        os.chmod(binary, 0o755)

        with open("/home/user/queries.sparql", "w") as f:
            f.write("SENTINEL THAT THE SCRIPT MUST REPLACE\n")

        result = subprocess.run([
            "/home/user/generate.sh"
        ], cwd="/home/user", stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30)
        assert result.returncode == 0, "generate.sh failed:\n" + result.stderr

        with open(call_log) as f:
            calls = [json.loads(line) for line in f if line.strip()]
        assert len(calls) == 3, f"generate.sh must execute sparql_gen exactly three times, but made {len(calls)} calls"

        expected_parameter_sets = [
            {"--subject": "ex:MachineLearning", "--min-year": "2018", "--sort-by": "citations", "--limit": "50", "--offset": "0"},
            {"--subject": "ex:Bioinformatics", "--min-year": "2020", "--sort-by": "year", "--limit": "10", "--offset": "20"},
            {"--subject": "ex:QuantumComputing", "--min-year": "2015", "--sort-by": "citations", "--limit": "100", "--offset": "50"},
        ]

        actual_parameter_sets = []
        for args in calls:
            assert len(args) == 10, f"Unexpected generator arguments: {args}"
            parsed = {}
            for i in range(0, len(args), 2):
                assert args[i] not in parsed, f"Duplicate generator option: {args[i]}"
                parsed[args[i]] = args[i + 1]
            actual_parameter_sets.append(parsed)
        assert actual_parameter_sets == expected_parameter_sets, "generate.sh used incorrect parameter sets or order"

        with open("/home/user/queries.sparql") as f:
            generated = f.read()
        assert generated.strip() == fixed_expected_content().strip(), "generate.sh did not produce the required queries.sparql content"
    finally:
        if os.path.exists(binary):
            os.remove(binary)
        os.replace(saved_binary, binary)
        if os.path.exists(call_log):
            os.remove(call_log)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
