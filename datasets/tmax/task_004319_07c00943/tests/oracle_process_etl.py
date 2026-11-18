#!/usr/bin/env python3
import sys
import json
from dateutil import parser

def main():
    input_data = sys.stdin.read().strip()
    if not input_data:
        return
    data = json.loads(input_data)
    if not data:
        print("[]")
        return

    # 1. Parsing & Sorting
    for item in data:
        item['_dt'] = parser.parse(item['date_str'])

    # Python's sort is stable, so original order is preserved for tie-breaks
    data.sort(key=lambda x: x['_dt'])

    # 2. Deduplication
    seen_ids = set()
    deduped = []
    for item in data:
        if item['id'] not in seen_ids:
            seen_ids.add(item['id'])
            deduped.append(item)

    # 3. Imputation
    for i, item in enumerate(deduped):
        if item['amount'] is None:
            prev_val = None
            next_val = None
            # Find prev
            for j in range(i-1, -1, -1):
                if deduped[j]['amount'] is not None:
                    prev_val = deduped[j]['amount']
                    break
            # Find next
            for j in range(i+1, len(deduped)):
                if deduped[j]['amount'] is not None:
                    next_val = deduped[j]['amount']
                    break

            if prev_val is not None and next_val is not None:
                item['_imputed'] = round((prev_val + next_val) / 2.0, 2)
            elif prev_val is not None:
                item['_imputed'] = round(prev_val, 2)
            elif next_val is not None:
                item['_imputed'] = round(next_val, 2)
            else:
                item['_imputed'] = 0.0

    for item in deduped:
        if item['amount'] is None:
            item['amount'] = item.pop('_imputed')

    # 4. Masking
    for item in deduped:
        parts = item['email'].split('@')
        if len(parts) == 2:
            item['email'] = parts[0][0] + "*****@" + parts[1]

    # 5. Deterministic Sampling
    final = [item for item in deduped if item['id'] % 2 == 0]

    # Clean up internal fields
    for item in final:
        item.pop('_dt', None)
        item.pop('_imputed', None)

    print(json.dumps(final, separators=(',', ':')))

if __name__ == "__main__":
    main()
