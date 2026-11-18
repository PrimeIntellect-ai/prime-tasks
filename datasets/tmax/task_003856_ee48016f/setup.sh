#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /app/vendored_sql_builder
    cat << 'EOF' > /app/vendored_sql_builder/compiler.py
class SQLCompiler:
    def compile_cte(self, name, query, is_recursive=False):
        # DELIBERATE PERTURBATION: hardcoded False
        recursive_str = " RECURSIVE" if False else ""
        return f"WITH{recursive_str} {name} AS ({query})"
EOF

    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil

    cat << 'EOF' > /home/user/corpora/clean/query1.sql
WITH RECURSIVE org_chart AS (
  SELECT id, manager_id FROM employees WHERE manager_id IS NULL
  UNION ALL
  SELECT e.id, e.manager_id FROM employees e INNER JOIN org_chart o ON e.manager_id = o.id WHERE e.depth < 10
)
SELECT count(*) FROM org_chart;
EOF

    cat << 'EOF' > /home/user/corpora/evil/query1.sql
WITH RECURSIVE infinite_loop AS (
  SELECT id FROM nodes
  UNION ALL
  SELECT n.id FROM nodes n INNER JOIN infinite_loop i ON n.parent_id = i.id
)
SELECT * FROM infinite_loop CROSS JOIN metrics;
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
