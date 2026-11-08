Implement Quote Tweets endpoint (GET /2/tweets/:id/quote_tweets)

### Additional contract requirements

- Add a method `QuoteTweets(ctx context.Context, tweetID string, opt ...*QuoteTweetsOption) (*QuoteTweetsResponse, error)` on `*Client` (also part of the `Tweets` interface).
- `QuoteTweetsResponse` exposes the quoting Tweets as `Tweets []*Tweet`, optional related objects as `Includes *TweetIncludes`, and metadata as `Meta *QuoteTweetsMeta`.
- `QuoteTweetsMeta` exposes `ResultCount int`, `NextToken string`, and `PreviousToken string`.
- `QuoteTweetsOption` allows query customization with `Expansions []Expansion`, `MaxResults int`, `PaginationToken string`, and field selections `TweetFields []TweetField`.
- Query parameters use the Twitter API names: `expansions`, `max_results`, `pagination_token`, and `tweet.fields`.
- A non-200 response returns an `*HTTPError`.
