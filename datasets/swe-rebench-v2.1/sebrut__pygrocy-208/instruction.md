Get product by Barcode
First of all, very cool project, it seems to make very straight forward to integrate grocy with other systems.

I would like to add/consume products by scanning their barcodes unfortunately I haven't found a way to retrieve the product_id by giving the barcode, is it that possible?

In the [grocy-pyscanner](https://github.com/grocy/grocy-pyscanner/blob/09e62fa8b39d14f304e71edd46fb5e1ab095cc52/barcode_reader.py#L94) they do it by a get request, so it is possible bu I haven't found how to do it in pygrocy.
Thanks a lot!

### Additional contract requirements

- `Grocy.product_by_barcode(barcode)` looks up a product by barcode and lets callers obtain the matching product ID.
- `add_product_by_barcode` sends the stock-entry request with the keys `amount` and `price` set to the requested values. When a non-None `best_before_date` is supplied, the request also includes a `best_before_date` key formatted as `YYYY-MM-DD`; when it is None the key is omitted.
- `consume_product_by_barcode` sends the consume request with the keys `amount` and `spoiled` set to the requested values.
- When `get_details=False`, the method does not fetch product details and still returns a `Product` instance for the affected product.
