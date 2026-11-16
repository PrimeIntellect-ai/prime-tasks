Problems with `self` pagination link
Hi. We're trying to upgrade to a version that includes https://github.com/jeregrine/jsonapi/pull/189, but have run into some problems.

Here's an example of some test regressions we have:
```elixir
  9) test index respects the page number 7 and size 3 (OurAppWeb.FooControllerTest)
     test/our_app_web/controllers/foo_controller_test.exs:342
     Assertion with == failed
     code:  assert resp["links"] == expected_pagination_links("foos", page_params)
     left:  %{"first" => "/api/v1/foos?page[page]=1&page[page-size]=3", "last" => "/api/v1/foos?page[page]=10&page[page-size]=3", "next" => "/api/v1/foos?page[page]=8&page[page-size]=3", "prev" => "/api/v1/foos?page[page]=6&page[page-size]=3", "self" => "http://localhost/foos"}
     right: %{"first" => "/api/v1/foos?page[page]=1&page[page-size]=3", "last" => "/api/v1/foos?page[page]=10&page[page-size]=3", "next" => "/api/v1/foos?page[page]=8&page[page-size]=3", "prev" => "/api/v1/foos?page[page]=6&page[page-size]=3", "self" => "/api/v1/foos?page[page]=7&page[page-size]=3"}
     stacktrace:
       test/our_app_web/controllers/foo_controller_test.exs:361: (test)
```

You see that the `self` value lacks the pagination params, pointing instead to a raw top-level `/foos` endpoint. I presume this comes from [view.url_for/2 here](https://github.com/jeregrine/jsonapi/pull/189/files?file-filters%5B%5D=.ex&file-filters%5B%5D=.exs&hide-deleted-files=true#diff-c6eda26dd75d06ea8b08bf45cb6f3f33R167)

In addition, I notice that [`@type links` in `paginator.ex` lacks the `self` key](https://github.com/jeregrine/jsonapi/pull/189/files?file-filters%5B%5D=.ex&file-filters%5B%5D=.exs&hide-deleted-files=true#diff-0e2f0db679e38d3135ee38439ff91b52R12). This seems at least tangentially related.
