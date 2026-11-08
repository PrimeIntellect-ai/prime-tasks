Day 391
Good morning! Here's your coding interview problem for today.

This problem was asked by Facebook.

We have some historical clickstream data gathered from our site anonymously using cookies. The histories contain URLs that users have visited in chronological order.

Write a function that takes two users' browsing histories as input and returns the longest contiguous sequence of URLs that appear in both.

For example, given the following two users' histories:
```
user1 = ['/home', '/register', '/login', '/user', '/one', '/two']
user2 = ['/home', '/red', '/login', '/user', '/one', '/pink']
```
You should return the following:

`['/login', '/user', '/one']`

### Additional contract requirements

The operation is callable as `LongestContiguousBrowsingHistory`. It returns the longest contiguous sequence of URLs shared by both histories in their original order; when there is no shared URL, it returns no URLs.
