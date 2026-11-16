Plugins: surprising behaviour from schema.org fill plugin when implementation and metadata are both absent
The `lekkerensimpel` scraper includes test coverage where some test webpages contain `schema.org` recipe metadata, and some do not.

If we temporarily remove the `category` implementation -- as in the case during development of #1228 -- then we uncover a surprising change-in-behaviour: pages that do contain recipe (and category) metadata continue to return the expected result, but pages that do not now begin raising `NotImplementedError`.

That's confusing: the implementation has not changed based on the HTML input, and yet the exception seems to indicate that the method is sometimes implemented, and sometimes not.

The approximate cause appears to be this line of code: https://github.com/hhursev/recipe-scrapers/blob/141470384b9e8a486f3a14255d37e3b608d3383a/recipe_scrapers/plugins/schemaorg_fill.py#L60

Basically: if no relevant `schema.org` recipe metadata was found on the page, then regardless of whether an implementation of the method exists, we re-raise the existing exception (a `NotImplementedError`, as [raised by the abstract scraper](https://github.com/hhursev/recipe-scrapers/blob/141470384b9e8a486f3a14255d37e3b608d3383a/recipe_scrapers/_abstract.py#L117-L119)).

I think what we should probably do instead is to raise a different `SchemaOrgException` if we detect that no relevant `schema.org` recipe metadata exists -- there's no point in calling the function under those circumstances.
