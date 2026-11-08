Question about query with date that includes "+"
Hello!

I tried to use `Search.Repositories` function.
I see it almost works well, but I tried to use query string `created:` that includes "+" doesn't work well.
Could you please give me some advice to use query in such situation.

Here's snippet I tried:

```go
// c is *github.Client
result, resp, err := c.Search.Repositories(
            context.Background(),                                                                                                       | 18             context.Background(),
            "user:pankona created:2019-01-18T17:35:34+09:00..2019-02-18T17:35:34+09:00 fork:true",                                      | 19             "user:pankona created:2019-01-18T17:35:34+09:00..2019-02-18T17:35:34+09:00 fork:true",
            &github.SearchOptions{                                                                                                      | 20             &github.SearchOptions{
                ListOptions: github.ListOptions{                                                                                        | 21                 ListOptions: github.ListOptions{
                    PerPage: 100,                                                                                                       | 22                     PerPage: 100,
                    Page:    page,                                                                                                      | 23                     Page:    page,
                }})
```

According to result of `httpuitl.DumpRequestOut`, the escaped query seems as follows:
`GET /search/repositories?q=user:pankona+created:2019-01-18T17:35:34+09:00..2019-02-18T17:35:34+09:00+fork:true&page=1&per_page=100 HTTP/1.1`

I expects 1 results by this search but it returns 0.

(I think "+" included in query's date part is not escaped correctly. I guess it should be `%2B`. Is my assuming correct?)

### Additional contract requirements

- A literal `+` character in a search query (for example the date qualifier `created:2019-01-18T17:35:34+09:00` used with `Search.Repositories`) must be percent-encoded as `%2B` in the request URL, so the server receives the original `+` character.
