Day 11
Good morning! Here's your coding interview problem for today.

This problem was asked by Twitter.

Implement an autocomplete system. That is, given a query string s and a set of all possible query strings, return all strings in the set that have s as a prefix.

For example, given the query string de and the set of strings [dog, deer, deal], return [deer, deal].

Hint: Try preprocessing the dictionary into a more efficient data structure to speed up queries.

### Additional contract requirements

- Provide a public function `NewTrie(words []string) *Trie` in package `day11` that constructs a trie containing the supplied words.
- Provide a public method `Match(prefix string) []string` on `*Trie` in package `day11` that returns all stored words that have `prefix` as a prefix, in no particular order.
- The query `prefix` is a non-empty valid UTF-8 string; matching is by Unicode code point, so prefixes containing non-ASCII characters are supported.
- If no stored word has `prefix` as a prefix, `Match` returns a nil slice.
