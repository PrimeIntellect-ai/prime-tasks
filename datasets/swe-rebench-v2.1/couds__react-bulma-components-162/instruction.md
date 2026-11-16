Disable next button on Pagination when making data fetch
Currently, the previous and the next buttons are disabled when the user is on the first or last page.

Is it possible to disable the button when the user clicks NEXT so they don't have the option to continuously click through and make a bunch of async requests?  Thanks

![demo](http://g.recordit.co/7oiZwNlA0b.gif)

### Additional contract requirements

`Pagination` accepts a boolean `disabled` prop. While a page-change request is outstanding, the caller can set this prop; activating Next while it is true must not trigger another page-change action. This requirement only requires suppressing Next and does not require disabling Previous or individual page links.
