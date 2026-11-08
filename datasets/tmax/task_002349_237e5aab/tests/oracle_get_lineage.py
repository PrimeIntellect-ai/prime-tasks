import sys
import json

def get_lineage(node_id, data_path):
    with open(data_path, 'r') as f:
        data = json.load(f)

    parent_index = {}
    for node in data:
        parent_index[node['id']] = node.get('parent_id', None)

    lineage = []
    curr = node_id
    while curr is not None:
        lineage.append(curr)
        curr = parent_index.get(curr)

    print(" -> ".join(lineage))

if __name__ == "__main__":
    get_lineage(sys.argv[1], "/home/user/backups.json")
