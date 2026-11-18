#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import copy
import csv
import json
import os
import re
import subprocess
import pytest

SCRIPT = '/home/user/process_etl.py'
DATA = '/home/user/data'
OUT = '/home/user/output'


def run_script():
    assert os.path.isfile(SCRIPT) and not os.path.islink(SCRIPT), f'{SCRIPT} must be a regular file.'
    for name in ('documents.json', 'pipeline.json', 'indexes.json'):
        path = os.path.join(OUT, name)
        if os.path.lexists(path):
            os.remove(path)
    result = subprocess.run(['python3', SCRIPT], capture_output=True, text=True, timeout=20)
    assert result.returncode == 0, f'Script failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}'


def load_json(name):
    path = os.path.join(OUT, name)
    assert os.path.isfile(path) and not os.path.islink(path), f'{path} does not exist as a regular file.'
    with open(path, encoding='utf-8') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f'{path} is not valid JSON: {exc}')


def expected_documents():
    with open(os.path.join(DATA, 'users.csv'), newline='', encoding='utf-8') as f:
        users = list(csv.DictReader(f))
    with open(os.path.join(DATA, 'orders.csv'), newline='', encoding='utf-8') as f:
        orders = list(csv.DictReader(f))
    with open(os.path.join(DATA, 'order_items.csv'), newline='', encoding='utf-8') as f:
        items = list(csv.DictReader(f))

    result = []
    for user in users:
        doc = {'user_id': user['user_id'], 'name': user['name']}
        user_orders = []
        for order in orders:
            if order['user_id'] != user['user_id']:
                continue
            mapped = {
                'order_id': order['order_id'],
                'order_date': order['order_date'],
                'status': order['status'],
            }
            order_items = []
            for item in items:
                if item['order_id'] == order['order_id']:
                    order_items.append({
                        'item_id': item['item_id'],
                        'product_name': item['product_name'],
                        'price': float(item['price']),
                    })
            if order_items:
                mapped['items'] = order_items
            user_orders.append(mapped)
        if user_orders:
            doc['orders'] = user_orders
        result.append(doc)
    return result


def canonical_docs(docs):
    docs = copy.deepcopy(docs)
    for doc in docs:
        if 'orders' in doc:
            for order in doc['orders']:
                if 'items' in order:
                    order['items'].sort(key=lambda x: x['item_id'])
            doc['orders'].sort(key=lambda x: x['order_id'])
    docs.sort(key=lambda x: x['user_id'])
    return docs


def values_at(value, parts):
    if not parts:
        return value
    if isinstance(value, list):
        out = []
        for entry in value:
            found = values_at(entry, parts)
            if isinstance(found, list):
                out.extend(found)
            elif found is not None:
                out.append(found)
        return out
    if not isinstance(value, dict) or parts[0] not in value:
        return None
    return values_at(value[parts[0]], parts[1:])


def expr_value(doc, expr):
    if isinstance(expr, str) and expr.startswith('$'):
        return values_at(doc, expr[1:].split('.'))
    if isinstance(expr, dict):
        return {k: expr_value(doc, v) for k, v in expr.items()}
    if isinstance(expr, list):
        return [expr_value(doc, x) for x in expr]
    return expr


def candidates(value):
    return value if isinstance(value, list) else [value]


def field_matches(value, condition):
    vals = candidates(value)
    if not isinstance(condition, dict) or not any(str(k).startswith('$') for k in condition):
        return any(v == condition for v in vals)
    options = condition.get('$options', '')
    for op, wanted in condition.items():
        if op == '$options':
            continue
        if op == '$eq' and not any(v == wanted for v in vals):
            return False
        elif op == '$ne' and not all(v != wanted for v in vals):
            return False
        elif op == '$in' and not any(v in wanted for v in vals):
            return False
        elif op == '$regex':
            flags = re.I if 'i' in options else 0
            pattern = wanted if isinstance(wanted, str) else str(wanted)
            if not any(isinstance(v, str) and re.search(pattern, v, flags) for v in vals):
                return False
        elif op == '$elemMatch':
            if not isinstance(value, list) or not any(match_doc(v, wanted) for v in value if isinstance(v, dict)):
                return False
        elif op not in ('$eq', '$ne', '$in', '$regex', '$elemMatch'):
            raise AssertionError(f'Unsupported or invalid match operator: {op}')
    return True


def match_doc(doc, query):
    assert isinstance(query, dict), '$match must contain an object.'
    for key, condition in query.items():
        if key == '$and':
            if not isinstance(condition, list) or not all(match_doc(doc, q) for q in condition):
                return False
        elif key == '$or':
            if not isinstance(condition, list) or not any(match_doc(doc, q) for q in condition):
                return False
        elif key.startswith('$'):
            raise AssertionError(f'Unsupported or invalid top-level match operator: {key}')
        elif not field_matches(values_at(doc, key.split('.')), condition):
            return False
    return True


def set_path(doc, path, value):
    parts = path.split('.')
    cur = doc
    for part in parts[:-1]:
        if part not in cur or not isinstance(cur[part], dict):
            cur[part] = {}
        cur = cur[part]
    cur[parts[-1]] = value


def freeze(value):
    if isinstance(value, dict):
        return tuple((k, freeze(v)) for k, v in sorted(value.items()))
    if isinstance(value, list):
        return tuple(freeze(v) for v in value)
    return value


def execute_pipeline(source, pipeline):
    assert isinstance(pipeline, list) and pipeline, 'Pipeline must be a nonempty JSON array.'
    rows = copy.deepcopy(source)
    for stage in pipeline:
        assert isinstance(stage, dict) and len(stage) == 1, 'Each pipeline stage must be a one-key object.'
        op, spec = next(iter(stage.items()))
        if op == '$match':
            rows = [d for d in rows if match_doc(d, spec)]
        elif op == '$unwind':
            path = spec if isinstance(spec, str) else spec.get('path') if isinstance(spec, dict) else None
            assert isinstance(path, str) and path.startswith('$'), 'Invalid $unwind path.'
            path = path[1:]
            new_rows = []
            for row in rows:
                value = values_at(row, path.split('.'))
                assert value is None or isinstance(value, list), f'$unwind target {path} is not an array.'
                for entry in value or []:
                    new_row = copy.deepcopy(row)
                    set_path(new_row, path, entry)
                    new_rows.append(new_row)
            rows = new_rows
        elif op == '$group':
            assert isinstance(spec, dict) and '_id' in spec, '$group must define _id.'
            groups = {}
            for row in rows:
                group_id = expr_value(row, spec['_id'])
                key = freeze(group_id)
                if key not in groups:
                    groups[key] = {'_id': group_id}
                    for name, accumulator in spec.items():
                        if name != '_id':
                            assert isinstance(accumulator, dict) and set(accumulator) == {'$sum'}, 'Only a valid $sum accumulator is accepted.'
                            groups[key][name] = 0
                for name, accumulator in spec.items():
                    if name == '_id':
                        continue
                    amount = expr_value(row, accumulator['$sum'])
                    assert isinstance(amount, (int, float)) and not isinstance(amount, bool), '$sum must resolve to a number.'
                    groups[key][name] += amount
            rows = list(groups.values())
        elif op in ('$project', '$set', '$addFields'):
            assert isinstance(spec, dict), f'{op} must contain an object.'
            transformed = []
            for row in rows:
                if op == '$project':
                    inclusion = any(v not in (0, False) for k, v in spec.items() if k != '_id')
                    new_row = {} if inclusion else copy.deepcopy(row)
                    for name, rule in spec.items():
                        if rule in (0, False):
                            new_row.pop(name, None)
                        elif rule in (1, True):
                            val = values_at(row, name.split('.'))
                            if val is not None:
                                set_path(new_row, name, val)
                        else:
                            set_path(new_row, name, expr_value(row, rule))
                else:
                    new_row = copy.deepcopy(row)
                    for name, rule in spec.items():
                        set_path(new_row, name, expr_value(row, rule))
                transformed.append(new_row)
            rows = transformed
        elif op == '$sort':
            assert isinstance(spec, dict) and spec, '$sort must contain sort keys.'
            for field, direction in reversed(list(spec.items())):
                assert direction in (1, -1), 'Sort direction must be 1 or -1.'
                rows.sort(key=lambda d: (values_at(d, field.split('.')) is None, values_at(d, field.split('.'))), reverse=direction == -1)
        elif op == '$limit':
            assert isinstance(spec, int) and not isinstance(spec, bool) and spec >= 0, '$limit must be a nonnegative integer.'
            rows = rows[:spec]
        else:
            raise AssertionError(f'Unsupported or inappropriate pipeline stage: {op}')
    return rows


def expected_analytics(docs):
    result = []
    for user in docs:
        total = 0.0
        for order in user.get('orders', []):
            if order['status'] != 'completed':
                continue
            for item in order.get('items', []):
                if re.search(r'\bWidget\b', item['product_name']):
                    total += item['price']
        if total:
            result.append({'user_id': user['user_id'], 'name': user['name'], 'total_widget_spent': total})
    return sorted(result, key=lambda x: (-x['total_widget_spent'], x['user_id']))[:5]


def normalized_result(rows):
    normalized = []
    for row in rows:
        assert isinstance(row, dict), 'Every pipeline result must be an object.'
        assert set(row) == {'user_id', 'name', 'total_widget_spent'}, 'Pipeline must return exactly user_id, name, and total_widget_spent.'
        assert isinstance(row['user_id'], str) and isinstance(row['name'], str)
        assert isinstance(row['total_widget_spent'], (int, float)) and not isinstance(row['total_widget_spent'], bool)
        normalized.append({'user_id': row['user_id'], 'name': row['name'], 'total_widget_spent': float(row['total_widget_spent'])})
    return normalized


def validate_indexes(indexes):
    assert isinstance(indexes, list), f'Expected indexes.json to contain a JSON array.'
    assert len(indexes) > 0, 'Indexes array is empty.'
    first_index = indexes[0]
    assert isinstance(first_index, dict), 'Index definition must be a JSON object.'
    assert 'keys' in first_index, "Index definition must contain 'keys'."
    keys_str = json.dumps(first_index['keys'])
    assert 'orders.status' in keys_str or 'orders' in keys_str, "Optimal index should target 'orders.status' or 'orders'."

    has_status_index = False
    for index in indexes:
        assert isinstance(index, dict) and 'keys' in index, 'Each index must be an object containing keys.'
        assert set(index).issubset({'keys', 'unique', 'name', 'sparse', 'partialFilterExpression'}), 'Unknown create_index option.'
        keys = index['keys']
        assert isinstance(keys, list) and keys, 'Index keys must be a nonempty JSON list.'
        seen = set()
        for pair in keys:
            assert isinstance(pair, list) and len(pair) == 2, 'Each key must be encoded as [field, direction].'
            field, direction = pair
            assert isinstance(field, str) and field and field not in seen, 'Index field names must be unique nonempty strings.'
            assert direction in (1, -1, 'text', 'hashed', '2d', '2dsphere'), 'Invalid PyMongo index direction.'
            seen.add(field)
            if field == 'orders.status' and direction in (1, -1):
                has_status_index = True
        if 'unique' in index:
            assert isinstance(index['unique'], bool), 'unique must be boolean.'
    assert has_status_index, 'At least one usable ascending or descending index must begin from the pre-unwind filter field orders.status.'


def write_csv(name, header, rows):
    with open(os.path.join(DATA, name), 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(header)
        writer.writerows(rows)


def test_script_executes_and_generates_files():
    run_script()


def test_documents_json():
    filepath = '/home/user/output/documents.json'
    assert os.path.isfile(filepath), f"{filepath} does not exist. Did the script run and create it?"
    docs = load_json('documents.json')
    assert isinstance(docs, list), f"Expected {filepath} to contain a JSON array."
    assert len(docs) == 3, f"Expected 3 users in {filepath}, found {len(docs)}."

    alice = next((d for d in docs if d.get('user_id') == '1'), None)
    assert alice is not None, "User '1' (Alice) not found in documents.json."
    assert alice.get('name') == 'Alice', "User '1' name should be 'Alice'."
    orders = alice.get('orders', [])
    assert isinstance(orders, list), "Alice's 'orders' should be a list."
    assert len(orders) == 2, f"Expected 2 orders for Alice, found {len(orders)}."
    order_101 = next((o for o in orders if o.get('order_id') == '101'), None)
    assert order_101 is not None, "Order '101' not found for Alice."
    assert order_101.get('status') == 'completed', "Order '101' status should be 'completed'."
    items = order_101.get('items', [])
    assert isinstance(items, list), "Order '101' 'items' should be a list."
    assert len(items) == 2, f"Expected 2 items in order '101', found {len(items)}."
    item_501 = next((i for i in items if i.get('item_id') == '501'), None)
    assert item_501 is not None, "Item '501' not found in order '101'."
    assert item_501.get('product_name') == 'Widget A', "Item '501' product_name should be 'Widget A'."
    assert isinstance(item_501.get('price'), float), 'Price should be a float.'
    assert item_501['price'] == 25.50, "Price for item '501' should be 25.50."
    assert canonical_docs(docs) == canonical_docs(expected_documents()), 'documents.json does not exactly map all CSV rows and fields.'


def test_pipeline_json():
    filepath = '/home/user/output/pipeline.json'
    assert os.path.isfile(filepath), f'{filepath} does not exist.'
    pipeline = load_json('pipeline.json')
    assert isinstance(pipeline, list), f'Expected {filepath} to contain a JSON array.'
    assert len(pipeline) > 0, 'Pipeline array is empty.'
    pipeline_str = json.dumps(pipeline)
    assert '$unwind' in pipeline_str, 'Pipeline must contain at least one $unwind stage.'
    assert '$match' in pipeline_str, 'Pipeline must contain at least one $match stage.'
    assert '$group' in pipeline_str, 'Pipeline must contain a $group stage.'
    assert '$sort' in pipeline_str, 'Pipeline must contain a $sort stage.'
    assert '$limit' in pipeline_str, 'Pipeline must contain a $limit stage.'
    assert 'Widget' in pipeline_str, "Pipeline must filter by 'Widget'."
    assert 'completed' in pipeline_str, "Pipeline must filter by 'completed' status."
    docs = load_json('documents.json')
    actual = normalized_result(execute_pipeline(docs, pipeline))
    assert actual == expected_analytics(docs), 'Pipeline does not compute the required completed-Widget totals, ordering, fields, and limit.'


def test_indexes_json():
    validate_indexes(load_json('indexes.json'))


def test_dynamic_end_to_end():
    filenames = ('users.csv', 'orders.csv', 'order_items.csv')
    backups = {}
    for name in filenames:
        with open(os.path.join(DATA, name), 'rb') as f:
            backups[name] = f.read()
    try:
        users = [[str(i), f'Person {i}'] for i in range(10, 18)] + [['99', 'No Orders']]
        orders = []
        items = []
        for rank, i in enumerate(range(10, 18), start=1):
            oid = str(800 + i)
            orders.append([oid, str(i), f'2025-04-{rank:02d}', 'completed'])
            items.append([str(9000 + i), oid, f'Widget Model {i}', f'{rank * 7 + 0.25:.2f}'])
            items.append([str(9100 + i), oid, 'Gadget', '999.00'])
        orders.extend([
            ['990', '10', '2025-05-01', 'pending'],
            ['991', '11', '2025-05-02', 'completed'],
            ['992', '12', '2025-05-03', 'completed'],
        ])
        items.extend([
            ['9990', '990', 'Widget Huge', '5000.00'],
            ['9991', '991', 'Plain Tool', '4000.00'],
        ])
        write_csv('users.csv', ['user_id', 'name'], users)
        write_csv('orders.csv', ['order_id', 'user_id', 'order_date', 'status'], orders)
        write_csv('order_items.csv', ['item_id', 'order_id', 'product_name', 'price'], items)

        run_script()
        docs = load_json('documents.json')
        assert canonical_docs(docs) == canonical_docs(expected_documents()), 'The script does not perform ETL from the supplied CSV contents.'
        pipeline = load_json('pipeline.json')
        actual = normalized_result(execute_pipeline(docs, pipeline))
        assert actual == expected_analytics(docs), 'Pipeline fails when exercised on independently derived data.'
        validate_indexes(load_json('indexes.json'))
    finally:
        for name, content in backups.items():
            with open(os.path.join(DATA, name), 'wb') as f:
                f.write(content)
        subprocess.run(['python3', SCRIPT], capture_output=True, text=True, timeout=20)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
