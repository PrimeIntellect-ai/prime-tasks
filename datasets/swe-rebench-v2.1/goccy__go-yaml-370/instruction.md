Paths for quoted keys don't filter correctly
I had some cases where comments from a comment map didn't show up in the marshaled yaml, and I realized these cases all have keys that require quotes.

Here's a test demonstrating this:
https://go.dev/play/p/U7B7jbXcKg4

I traced it down to path filter not matching in these cases. There is a PR incoming.
