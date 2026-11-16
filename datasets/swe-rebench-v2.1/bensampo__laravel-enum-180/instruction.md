Adding hasFlag for elequent query builder
Hi,
i think one important feature for flagged enums would to query DB using query builder and enums.

    Order::where("client_id",Auth::id())
                   ->whereRaw("order_status"." & ?",[OrderStatus::Ready()])
                   ->get();
its what i was done.

but could have a nicer method like:

        ->whereHasFlag("order_status",OrderStatus::Ready())

it would be my pleasure to contribute and make a PR.
but i dont know where to start, to modify query builder?

### Additional contract requirements

- Eloquent query builders for a model that uses the `BenSampo\Enum\Traits\QueriesFlaggedEnums` trait must provide a fluent `hasFlag($column, $flag)` method. It keeps only the rows whose integer bitmask column contains the given flag.
- `$flag` may be an integer flag value or an enum instance (for example `SuperPowers::Flight()`), in which case its underlying value is used.
- `hasFlag` can be chained after ordinary query constraints such as `where`, and the results must respect both the constraints and the flag filter.
- Each row is judged by the bitmask currently stored in its column.
