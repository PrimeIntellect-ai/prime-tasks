import sys
import sqlite3
import json

def build_tree(rows, parent_id):
    children = []
    for row in rows:
        if row[2] == parent_id:
            child = {
                "id": row[0],
                "name": row[1],
                "children": build_tree(rows, row[0])
            }
            children.append(child)
    return sorted(children, key=lambda x: x["id"])

def main():
    if len(sys.argv) < 2:
        sys.exit(1)
    root_id = int(sys.argv[1])
    conn = sqlite3.connect('/home/user/taxonomy.db')
    cursor = conn.execute("WITH RECURSIVE lineage AS ( "
                          "SELECT id, name, parent_id FROM taxa WHERE id = ? "
                          "UNION ALL "
                          "SELECT t.id, t.name, t.parent_id FROM taxa t "
                          "JOIN lineage l ON t.parent_id = l.id) "
                          "SELECT id, name, parent_id FROM lineage", (root_id,))
    rows = cursor.fetchall()
    if not rows:
        print(json.dumps({}))
        return

    # Root node is the one matching root_id
    root_row = next((r for r in rows if r[0] == root_id), None)
    if not root_row:
        return

    tree = {
        "id": root_row[0],
        "name": root_row[1],
        "children": build_tree(rows, root_row[0])
    }
    print(json.dumps(tree, separators=(',', ':')))

if __name__ == '__main__':
    main()
