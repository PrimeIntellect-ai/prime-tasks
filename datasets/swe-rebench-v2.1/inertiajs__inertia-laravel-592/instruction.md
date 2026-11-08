Error in view data / url prop
Currently if the project has the base url `localhost/test` and we navigate to `some/sub/page` the result is a url change to `localhost/test/test/some/sub/page` in the brower by inertiajs. This url no longer matches the route we are currently at.

The issue seems to be that a path as part of the base url is not handled correctly.

This line in \Inertia\Response causes the issue.

`[HIDDEN]`
Subdirectory urls broken
#347 breaks Laravel projects that run in a subdirectory.

src/Response.php was changed at line 128 but nothing in the commit message details why. Symfony don't seem to have changed what these methods do and this now returns the incorrect URL which causes the Inertia client adapter to push an incorrect path to the history. So an Inertia app running at https://example.com/app will have https://example.com/app/app pushed to the history on the initial page render automatically.

The issue is also described here: https://laracasts.com/discuss/channels/laravel/root-directory-is-displayed-twice-in-url-on-load-and-reload

PR on the way

### Additional contract requirements

- For a request served under a subdirectory, the page URL must identify the current route and include the deployment-path prefix exactly once, so client-side history does not append a duplicated prefix.
