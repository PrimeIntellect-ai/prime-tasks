Row.lpush/rpush behavior is reversed
As discovered while testing #450, `Row.lpush` is appending, while `Row.rpush` is prepending, which is counter-intuitive (and doesn't match the `Dataset.lpush/rpush`behavior).
