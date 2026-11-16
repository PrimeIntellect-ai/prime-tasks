function clause error in Flop.Phoenix.Pagination.pagination_type/1
### Summary

[info] GET /
[debug] Processing with Bla.Index.index/2
  Parameters: %{}
  Pipelines: [:browser, :require_authenticated_user]

(This is the content of flop in lib/flop_phoenix/pagination.ex:164)
%Flop{
  after: nil,
  before: nil,
  first: nil,
  last: nil,
  limit: 50,
  offset: nil,
  order_by: [:occurred_at],
  order_directions: [:desc, :asc],
  page: nil,
  page_size: nil,
  decoded_cursor: nil,
  filters: []
}
[info] Sent 500 in 81ms
[error] ** (FunctionClauseError) no function clause matching in Flop.Phoenix.Pagination.pagination_type/1
    (flop_phoenix 0.25.0) lib/flop_phoenix/pagination.ex:164: Flop.Phoenix.Pagination.pagination_type(%Flop{after: nil, before: nil, first: nil, last: nil, limit: 50, offset: nil, order_by: [:occurred_at], order_directions: [:desc, :asc], page: nil, page_size: nil, decoded_cursor: nil, filters: []})
    (flop_phoenix 0.25.0) lib/flop_phoenix/pagination.ex:113: Flop.Phoenix.Pagination.new/2
    (flop_phoenix 0.25.0) lib/flop_phoenix.ex:905: Flop.Phoenix."pagination_for (overridable 1)"/1
    (phoenix_live_view 1.0.10) lib/phoenix_live_view/tag_engine.ex:96: Phoenix.LiveView.TagEngine.component/3
    (flop_phoenix 0.25.0) lib/flop_phoenix.ex:520: anonymous fn/2 in Flop.Phoenix."pagination (overridable 1)"/1
    (bla 1.4.0) bla/index.html.heex:82: Bla.Index.render/1
    (elixir 1.18.3) lib/enum.ex:2546: Enum."-reduce/3-lists^foldl/2-0-"/3
    (phoenix_live_view 1.0.10) lib/phoenix_live_view/diff.ex:412: Phoenix.LiveView.Diff.traverse/7
    (phoenix_live_view 1.0.10) lib/phoenix_live_view/diff.ex:555: anonymous fn/4 in Phoenix.LiveView.Diff.traverse_dynamic/7
    (elixir 1.18.3) lib/enum.ex:2546: Enum."-reduce/3-lists^foldl/2-0-"/3
    (phoenix_live_view 1.0.10) lib/phoenix_live_view/diff.ex:412: Phoenix.LiveView.Diff.traverse/7
    (phoenix_live_view 1.0.10) lib/phoenix_live_view/diff.ex:555: anonymous fn/4 in Phoenix.LiveView.Diff.traverse_dynamic/7
    (elixir 1.18.3) lib/enum.ex:2546: Enum."-reduce/3-lists^foldl/2-0-"/3
    (phoenix_live_view 1.0.10) lib/phoenix_live_view/diff.ex:412: Phoenix.LiveView.Diff.traverse/7
    (phoenix_live_view 1.0.10) lib/phoenix_live_view/diff.ex:136: Phoenix.LiveView.Diff.render/3
    (phoenix_live_view 1.0.10) lib/phoenix_live_view/static.ex:289: Phoenix.LiveView.Static.to_rendered_content_tag/4
    (phoenix_live_view 1.0.10) lib/phoenix_live_view/static.ex:171: Phoenix.LiveView.Static.do_render/4
    (phoenix_live_view 1.0.10) lib/phoenix_live_view/controller.ex:39: Phoenix.LiveView.Controller.live_render/3


### Steps to reproduce

1. ...

### Expected behaviour

_No response_

### Actual behaviour

_No response_

### Elixir/Erlang version

Elixir 1.18.3 (compiled with Erlang/OTP 27)

### Flop and Ecto versions

* ecto 3.12.5 (Hex package) (mix)
* ecto_sql 3.12.1 (Hex package) (mix)
  locked at 3.12.1 (ecto_sql) aff5b958
* flop 0.26.1 (Hex package) (mix)
  locked at 0.26.1 (flop) 5fcab8a1
* flop_phoenix 0.25.0 (https://github.com/woylie/flop_phoenix.git) (mix)

### Additional context

_No response_
