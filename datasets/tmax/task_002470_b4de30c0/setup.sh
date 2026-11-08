#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /app/pygraph_etl-1.2.0/pygraph_etl
    mkdir -p /home/user/data

    # Create vendored package setup.py
    cat << 'EOF' > /app/pygraph_etl-1.2.0/setup.py
from setuptools import setup, find_packages
setup(name='pygraph_etl', version='1.2.0', packages=find_packages())
EOF

    # Create vendored package __init__.py
    cat << 'EOF' > /app/pygraph_etl-1.2.0/pygraph_etl/__init__.py
from .mapper import GraphProjector
EOF

    # Create vendored package mapper.py with the bug
    cat << 'EOF' > /app/pygraph_etl-1.2.0/pygraph_etl/mapper.py
class GraphProjector:
    def __init__(self, schema):
        self.schema = schema
        self.edges = []

    def expand_has_many(self, source_id, target_list, edge_type, nested_schema=None):
        edges = []
        # BUG: truncates the array iteration prematurely
        for item in target_list[:1]:
            edges.append((source_id, item['id'], edge_type))
            if nested_schema:
                for k, v in nested_schema.items():
                    if k in item:
                        if isinstance(item[k], list) and v.get('type') == 'has_many':
                            for target in item[k]:
                                target_id = target['id'] if isinstance(target, dict) else target
                                edges.append((item['id'], target_id, v['edge_type']))
        return edges

    def materialize(self, data):
        for doc in data:
            for node_type, node_schema in self.schema.items():
                if doc.get('type') == node_type:
                    source_id = doc['id']
                    for k, v in node_schema.items():
                        if k in doc and v.get('type') == 'has_many':
                            self.edges.extend(self.expand_has_many(source_id, doc[k], v['edge_type'], v.get('nested')))
        return self.edges
EOF

    # Create data file
    cat << 'EOF' > /home/user/data/entities.jsonl
{"type": "Company", "id": "C1", "employees": [{"id": "E1", "projects": ["P1", "P2"]}, {"id": "E2", "projects": ["P2", "P3"]}]}
{"type": "Company", "id": "C2", "employees": [{"id": "E3", "projects": ["P1"]}, {"id": "E4", "projects": ["P4"]}]}
{"type": "Company", "id": "C3", "employees": [{"id": "E5", "projects": ["P5"]}, {"id": "E6", "projects": ["P6"]}]}
EOF

    # Create the user and fix permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
