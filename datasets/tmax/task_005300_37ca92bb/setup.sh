#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest setuptools

mkdir -p /app/pycypher-ast-1.2.0/pycypher_ast

cat << 'EOF' > /app/pycypher-ast-1.2.0/setup.py
from setuptools import setup, find_packages

setup(
    name='pycypher-ast',
    version='1.2.0',
    packages=find_packages(),
)
EOF

cat << 'EOF' > /app/pycypher-ast-1.2.0/pycypher_ast/__init__.py
from .lexer import parse, AST_PARSE_ERROR
EOF

cat << 'EOF' > /app/pycypher-ast-1.2.0/pycypher_ast/lexer.py
import re

PARAMETER_REGEX = r'\#([A-Za-z0-9_]+)'

class AST_PARSE_ERROR(Exception):
    pass

def parse(query):
    if '$' in query and not re.search(PARAMETER_REGEX, query):
        raise AST_PARSE_ERROR("Unexpected character $")
    return {"type": "AST", "params": re.findall(PARAMETER_REGEX, query)}
EOF

# Install the broken package
cd /app/pycypher-ast-1.2.0
pip3 install -e .

cat << 'EOF' > /app/oracle_schema_mapper.py
import sys
import json

def generate_cypher(json_str):
    data = json.loads(json_str)
    entity = data["entity"]
    filters = data.get("filters", {})
    return_fields = data.get("return_fields", [])

    match_clauses = []
    where_clauses = []

    if entity == "Paper":
        if "author_id" in filters:
            match_clauses.append("(n:Paper)-[:AUTHORED_BY]->(a:Author {id: $author_id})")
        if "grant_id" in filters:
            match_clauses.append("(n:Paper)-[:FUNDED_BY]->(g:Grant {id: $grant_id})")
        if not match_clauses:
            match_clauses.append("(n:Paper)")
    elif entity == "Author":
        if "institution_id" in filters:
            match_clauses.append("(n:Author)-[:AFFILIATED_WITH]->(i:Institution {id: $institution_id})")
        if not match_clauses:
            match_clauses.append("(n:Author)")
    elif entity == "Grant":
        match_clauses.append("(n:Grant)")
    else:
        match_clauses.append(f"(n:{entity})")

    for k, v in filters.items():
        if k not in ["author_id", "grant_id", "institution_id"]:
            where_clauses.append(f"n.{k} = ${k}")

    query = "MATCH " + ", ".join(match_clauses)
    if where_clauses:
        query += " WHERE " + " AND ".join(where_clauses)
    if return_fields:
        returns = ", ".join([f"n.{f}" for f in return_fields])
        query += f" RETURN {returns}"

    return query

if __name__ == "__main__":
    print(generate_cypher(sys.argv[1]))
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
