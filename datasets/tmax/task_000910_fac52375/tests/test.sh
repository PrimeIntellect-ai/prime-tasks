#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import pytest


def get_csv_data(filepath):
    with open(filepath, 'r') as f:
        reader = csv.DictReader(f)
        return list(reader)


def test_cypher_script_content():
    cypher_path = '/home/user/graph.cypher'
    assert os.path.isfile(cypher_path), f"The file {cypher_path} is missing."

    cities = get_csv_data('/home/user/data/cities.csv')
    users = get_csv_data('/home/user/data/users.csv')
    friendships = get_csv_data('/home/user/data/friendships.csv')

    cities.sort(key=lambda x: int(x['id']))
    users.sort(key=lambda x: int(x['id']))

    expected_lines = []

    for c in cities:
        expected_lines.append(f"CREATE (:City {{id: {c['id']}, name: '{c['name']}'}});")

    for u in users:
        expected_lines.append(f"CREATE (:User {{id: {u['id']}, name: '{u['name']}'}});")

    for u in users:
        expected_lines.append(f"MATCH (u:User {{id: {u['id']}}}), (c:City {{id: {u['city_id']}}}) CREATE (u)-[:LIVES_IN]->(c);")

    knows_set = set()
    for f in friendships:
        u1, u2 = int(f['user1_id']), int(f['user2_id'])
        knows_set.add((u1, u2))
        knows_set.add((u2, u1))

    knows_list = sorted(list(knows_set))
    for u1, u2 in knows_list:
        expected_lines.append(f"MATCH (u1:User {{id: {u1}}}), (u2:User {{id: {u2}}}) CREATE (u1)-[:KNOWS]->(u2);")

    with open(cypher_path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {cypher_path}, but found {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Line {i+1} in {cypher_path} is incorrect.\nExpected: {expected}\nActual:   {actual}"


def test_answer_txt_content():
    answer_path = '/home/user/answer.txt'
    assert os.path.isfile(answer_path), f"The file {answer_path} is missing."

    cities = get_csv_data('/home/user/data/cities.csv')
    users = get_csv_data('/home/user/data/users.csv')
    friendships = get_csv_data('/home/user/data/friendships.csv')

    city_map = {c['id']: c['name'] for c in cities}
    user_map = {u['id']: u for u in users}

    adj = {u['id']: set() for u in users}
    for f in friendships:
        u1, u2 = f['user1_id'], f['user2_id']
        adj[u1].add(u2)
        adj[u2].add(u1)

    alice_id = None
    for u in users:
        if u['name'] == 'Alice':
            alice_id = u['id']
            break

    assert alice_id is not None, "Alice not found in users.csv"

    friends = adj[alice_id]

    fof = set()
    for friend in friends:
        fof.update(adj[friend])

    fof.discard(alice_id)
    fof -= friends

    graphville_id = None
    for c in cities:
        if c['name'] == 'Graphville':
            graphville_id = c['id']
            break

    valid_fof_names = []
    for uid in fof:
        if user_map[uid]['city_id'] == graphville_id:
            valid_fof_names.append(user_map[uid]['name'])

    assert len(valid_fof_names) == 1, "Expected exactly one valid friend-of-a-friend"
    expected_answer = valid_fof_names[0]

    with open(answer_path, 'r') as f:
        actual_answer = f.read().strip()

    assert actual_answer == expected_answer, f"Expected answer '{expected_answer}', but got '{actual_answer}'"
TEST_EOF

passed=1

if [[ ! -f /home/user/graph_builder/Cargo.toml || ! -s /home/user/graph_builder/src/main.rs ]]; then
    passed=0
fi

write_original_fixtures() {
    chmod 755 /home/user/data
    cat > /home/user/data/cities.csv <<'EOF'
id,name
1,Graphville
2,SQLton
EOF
    cat > /home/user/data/users.csv <<'EOF'
id,name,city_id
1,Alice,1
2,Bob,2
3,Charlie,1
4,Dave,1
5,Eve,2
EOF
    cat > /home/user/data/friendships.csv <<'EOF'
user1_id,user2_id
1,2
2,3
3,4
1,5
EOF
}

write_random_fixtures() {
    chmod 755 /home/user/data
    python3 <<'PY'
import csv
import random
import secrets

ids = random.sample(range(100, 10000), 7)
graphville_id, other_city_id = ids[:2]
alice_id, bridge_id, target_id, direct_id, other_direct_id = ids[2:]
target_name = 'FoF_' + secrets.token_hex(8)

cities = [
    [str(graphville_id), 'Graphville'],
    [str(other_city_id), 'SQLton'],
]
users = [
    [str(alice_id), 'Alice', str(graphville_id)],
    [str(bridge_id), 'Bridge_' + secrets.token_hex(4), str(other_city_id)],
    [str(target_id), target_name, str(graphville_id)],
    [str(direct_id), 'Direct_' + secrets.token_hex(4), str(graphville_id)],
    [str(other_direct_id), 'Other_' + secrets.token_hex(4), str(other_city_id)],
]
friendships = [
    [str(bridge_id), str(alice_id)],
    [str(target_id), str(bridge_id)],
    [str(alice_id), str(direct_id)],
    [str(other_direct_id), str(alice_id)],
]
random.shuffle(cities)
random.shuffle(users)
random.shuffle(friendships)

for path, header, rows in [
    ('/home/user/data/cities.csv', ['id', 'name'], cities),
    ('/home/user/data/users.csv', ['id', 'name', 'city_id'], users),
    ('/home/user/data/friendships.csv', ['user1_id', 'user2_id'], friendships),
]:
    with open(path, 'w', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(header)
        writer.writerows(rows)
PY
}

run_and_check() {
    local tag="$1"

    cp /home/user/data/cities.csv "/tmp/${tag}_cities.csv"
    cp /home/user/data/users.csv "/tmp/${tag}_users.csv"
    cp /home/user/data/friendships.csv "/tmp/${tag}_friendships.csv"

    chown root:root /home/user/data /home/user/data/*.csv
    chmod 755 /home/user/data
    chmod 444 /home/user/data/*.csv

    rm -f /home/user/graph.cypher /home/user/answer.txt

    if ! runuser -u user -- env HOME=/home/user bash -c 'cd /home/user/graph_builder && cargo run --quiet'; then
        return 1
    fi

    cmp -s /home/user/data/cities.csv "/tmp/${tag}_cities.csv" || return 1
    cmp -s /home/user/data/users.csv "/tmp/${tag}_users.csv" || return 1
    cmp -s /home/user/data/friendships.csv "/tmp/${tag}_friendships.csv" || return 1

    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1
}

if [[ "$passed" -eq 1 ]]; then
    write_original_fixtures
    if ! run_and_check original; then
        passed=0
    fi
fi

if [[ "$passed" -eq 1 ]]; then
    write_random_fixtures
    if ! run_and_check randomized; then
        passed=0
    fi
fi

if [[ "$passed" -eq 1 ]]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
