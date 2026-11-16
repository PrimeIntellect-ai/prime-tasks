Missing data in CurrentVolatilStockResponse._missing_products
Hi!

First of all many thanks for pygrocy, I have been using it for a while and it helped me a lot!

I think I got a parse error when I try to get the missing products using `grocy.missing_products()`

If I check the JSON I See:

```
"missing_products": [
        {
            "id": "7",
            "name": "XXXX",
            "amount_missing": "1",
            "is_partly_in_stock": "1"
        },
        {
            "id": "8",
            "name": "YYYY",
            "amount_missing": "1",
            "is_partly_in_stock": "1"
        },
        {
            "id": "75",
            "name": "ZZZZ",
            "amount_missing": "1",
            "is_partly_in_stock": "1"
        }
    ]
```

But diving in [CurrentStockResponse](https://github.com/SebRut/pygrocy/blob/47dbb07f93403500f133a13012264aa1439e68db/pygrocy/grocy_api_client.py#L177) is expecting antother property names:

```
self._product_id = parse_int(parsed_json.get('product_id'))
self._amount = parse_float(parsed_json.get('amount'))
self._best_before_date = parse_date(parsed_json.get('best_before_date'))
self._amount_opened = parse_float(parsed_json.get('amount_opened'))
```

Do we might need a new class to represent missing products?

If so, I can try to open a PR with that change.

### Additional contract requirements

- Missing products exposed by `CurrentVolatilStockResponse.missing_products` must be `MissingProductResponse` objects parsed from the `missing_products` array of the volatile stock JSON.
- `grocy.missing_products()` must return `Product` objects whose `product_id`, `name`, `amount_missing`, and `is_partly_in_stock` reflect the corresponding fields of the missing product JSON.
