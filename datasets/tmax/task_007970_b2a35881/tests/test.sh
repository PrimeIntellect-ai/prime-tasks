#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shlex
import shutil
import stat
import subprocess
import tempfile
import uuid

import pytest
import rdflib

HOME = "/home/user"
FAST_QUERY = os.path.join(HOME, "fast_query.rq")
EXPORT_SCRIPT = os.path.join(HOME, "export_results.sh")
RESULTS = os.path.join(HOME, "results.csv")
DATA = os.path.join(HOME, "data.ttl")
RUNNER = os.path.join(HOME, "query_runner.py")

REFERENCE_QUERY = """
PREFIX ex: <http://example.org/>
SELECT ?coStarName
WHERE {
  ?m1 ex:type ex:Movie .
  ?m2 ex:type ex:Movie .
  ?m1 ex:hasActor ?a1 .
  ?m2 ex:hasActor ?a2 .
  FILTER(?a1 = ex:KevinBacon && ?m1 = ?m2 && ?a1 != ?a2)
  ?a2 ex:name ?coStarName .
}
"""


def query_values(graph, query):
    result = graph.query(query)
    assert [str(v) for v in result.vars] == ["coStarName"], "Query must select exactly ?coStarName"
    return [str(row[0]) for row in result]


def generated_graph():
    ex = rdflib.Namespace("http://example.org/")
    graph = rdflib.Graph()
    token = uuid.uuid4().hex
    kevin = ex.KevinBacon
    actors = [
        (ex["ActorA" + token], "Alpha " + token),
        (ex["ActorB" + token], "Middle " + token),
        (ex["ActorZ" + token], "Zulu " + token),
    ]
    movies = [ex["MovieA" + token], ex["MovieB" + token], ex["MovieC" + token]]
    for movie in movies:
        graph.add((movie, ex.type, ex.Movie))
        graph.add((movie, ex.hasActor, kevin))
    graph.add((movies[0], ex.hasActor, actors[0][0]))
    graph.add((movies[0], ex.hasActor, actors[1][0]))
    graph.add((movies[1], ex.hasActor, actors[2][0]))
    # The same co-star appears in another Kevin Bacon movie, so duplicate-result
    # semantics must also agree with the original query.
    graph.add((movies[2], ex.hasActor, actors[1][0]))
    for actor, name in actors:
        graph.add((actor, ex.name, rdflib.Literal(name)))

    unrelated_movie = ex["UnrelatedMovie" + token]
    unrelated_actor = ex["UnrelatedActor" + token]
    graph.add((unrelated_movie, ex.type, ex.Movie))
    graph.add((unrelated_movie, ex.hasActor, unrelated_actor))
    graph.add((unrelated_actor, ex.name, rdflib.Literal("Decoy " + token)))
    return graph


def test_fast_query_exists_and_optimized():
    path = FAST_QUERY
    assert os.path.isfile(path), f"File missing: {path}"

    with open(path, "r") as f:
        content = f.read()

    # Preserve the original structural assertion.
    assert "?m2" not in content, "Query was not properly optimized (still contains multiple movie variables like ?m2)."

    # Also reject the same Cartesian-join technique under renamed variables.
    without_comments = re.sub(r"(?m)#.*$", "", content)
    assert not re.search(r"\?[A-Za-z_]\w*\s*=\s*\?[A-Za-z_]\w*", without_comments), \
        "Optimized query still equates two variables instead of directly sharing the movie node."

    # Execute the submitted query and compare its result multiset with the
    # original query on both the supplied graph and an unpredictable graph.
    with open(path, "r") as f:
        fast = f.read()

    supplied = rdflib.Graph()
    supplied.parse(DATA, format="turtle")
    assert sorted(query_values(supplied, fast)) == sorted(query_values(supplied, REFERENCE_QUERY))

    generated = generated_graph()
    assert sorted(query_values(generated, fast)) == sorted(query_values(generated, REFERENCE_QUERY)), \
        "fast_query.rq is not equivalent to slow_query.rq on additional data"


def test_export_results_script_exists_and_executable():
    path = EXPORT_SCRIPT
    assert os.path.isfile(path), f"File missing: {path}"
    assert os.access(path, os.X_OK), f"Script is not executable: {path}"

    with open(path, "r") as f:
        content = f.read()
    executable_text = re.sub(r"(?m)^\s*#.*$", "", content.replace("\\\n", " "))
    assert re.search(
        r"query_runner\.py[^\n|;]*data\.ttl[^\n|;]*fast_query\.rq[^\n|;]*\|[^\n;]*\bjq\b",
        executable_text,
    ), "Script must pipe query_runner.py output to jq"


def run_script_directly():
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    result = subprocess.run(
        [EXPORT_SCRIPT],
        cwd=HOME,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"export_results.sh failed with return code {result.returncode}\nStderr: {result.stderr}"
    assert os.path.isfile(RESULTS), f"Script did not create {RESULTS}"
    with open(RESULTS, "r") as f:
        return f.read().strip().splitlines()


def test_export_results_output():
    content = run_script_directly()
    expected = [
        "Actor",
        "Bill Paxton",
        "Finn Carter",
        "Fred Ward",
        "John Lithgow",
        "Lori Singer",
        "Tom Hanks",
    ]
    # Preserve the original exact-output assertion.
    assert content == expected, f"Contents of {RESULTS} do not match the expected output. Got: {content}"


def test_export_is_computed_by_runner_and_jq_on_new_data():
    graph = generated_graph()
    expected = ["Actor"] + sorted(query_values(graph, REFERENCE_QUERY))

    original_data = open(DATA, "rb").read()
    original_runner = open(RUNNER, "rb").read()
    data_mode = stat.S_IMODE(os.stat(DATA).st_mode)
    runner_mode = stat.S_IMODE(os.stat(RUNNER).st_mode)

    with tempfile.TemporaryDirectory() as tempdir:
        runner_marker = os.path.join(tempdir, "runner-called")
        jq_marker = os.path.join(tempdir, "jq-called")
        real_jq = shutil.which("jq")
        assert real_jq, "jq is unavailable"

        trusted_runner = f'''import json
import sys
import rdflib
open({runner_marker!r}, "w").write("called")
if len(sys.argv) != 3:
    sys.exit(2)
g = rdflib.Graph()
g.parse(sys.argv[1], format="turtle")
with open(sys.argv[2]) as f:
    result = g.query(f.read())
out = {{"results": {{"bindings": []}}}}
for row in result:
    binding = {{}}
    for var in result.vars:
        value = row[var]
        if value is not None:
            binding[str(var)] = {{"value": str(value)}}
    out["results"]["bindings"].append(binding)
print(json.dumps(out))
'''

        jq_shim = os.path.join(tempdir, "jq")
        with open(jq_shim, "w") as f:
            f.write("#!/bin/sh\n")
            f.write("printf called > " + shlex.quote(jq_marker) + "\n")
            f.write("exec " + shlex.quote(real_jq) + " \"$@\"\n")
        os.chmod(jq_shim, 0o755)

        try:
            graph.serialize(destination=DATA, format="turtle")
            with open(RUNNER, "w") as f:
                f.write(trusted_runner)
            os.chmod(RUNNER, 0o755)
            if os.path.exists(RESULTS):
                os.remove(RESULTS)

            env = os.environ.copy()
            env["PATH"] = tempdir + os.pathsep + env.get("PATH", "")
            result = subprocess.run(
                ["bash", "-x", EXPORT_SCRIPT],
                cwd=HOME,
                env=env,
                capture_output=True,
                text=True,
                timeout=30,
            )
            assert result.returncode == 0, f"export_results.sh failed on generated data:\n{result.stderr}"
            assert os.path.exists(runner_marker), "export_results.sh did not execute query_runner.py"
            assert os.path.exists(jq_marker) or re.search(r"(?m)^\+ .*?/jq(?:\s|$)", result.stderr), \
                "export_results.sh did not execute jq"
            assert os.path.isfile(RESULTS), f"Script did not create {RESULTS}"
            with open(RESULTS) as f:
                actual = f.read().strip().splitlines()
            assert actual == expected, \
                f"Export was not derived from the generated query results. Expected {expected}, got {actual}"
        finally:
            with open(DATA, "wb") as f:
                f.write(original_data)
            with open(RUNNER, "wb") as f:
                f.write(original_runner)
            os.chmod(DATA, data_mode)
            os.chmod(RUNNER, runner_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
