complete abstraction on top of server data classes
Currently, some methods in `Grocy` return response objects and some methods return objects independent of the server representation. In this issue, all methods in `Grocy` should be changed to return a representation of an entity which is independent of the representation on the server side. It may be needed to create additional classes to achieve this.

### Additional contract requirements

- `Grocy.product(product_id)` returns a `Product` domain object (or `None` when the server returns no data), not a raw server response object.
- The `Chore` object returned by `Grocy.chore(chore_id)` exposes `id` (int), `last_tracked_time` (datetime), `next_estimated_execution_time` (datetime), `name` (str) and `last_done_by` (UserDto), populated from the chore-details response.
