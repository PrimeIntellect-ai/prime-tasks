Filter resources using labels not working properly when having too many items
On my instance of the Registry server I added the label "source" on all resources of type API. If I try some filters like the one below, the result might not return all matches when having too many items in the database.

`registry rpc list-apis -j --page_size 1000 --parent projects/my-project-name/locations/global --filter 'labels.source=="example-source"'`

On this example, I have 530 APIs on the database, even with the explicit page_size flag, it's always returning 500 items, so, I need to make another call to get the other 30 APIs. I did not find any limitations about the page_size when using along with filters.
