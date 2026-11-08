`group_by` is weird
I spent several hours debugging my code written using the `group_by` function.

I expected from this function the logic of grouping the same objects by a key, how surprised I was that he groups only some nearby elements while the group key has the same value.

In the documentation it is also indicated somehow strange and until the last, I was not sure if this is a bug or feature. I carefully read the documentation 5 times and it turned out to be a feature! Awful incomprehensible feature!

I do not think that this is the behavior that many expect for this method name. I demand to rename this method to something more suitable like `cons_group_by` or `lazy_group_by` not to mislead users.

[Example](https://play.integer32.com/?gist=09d53af6fff65075c756905d45400cf0&version=stable)

[I'm not the only one to think so](https://www.reddit.com/r/rust/comments/6d4no8/group_by_on_a_vect/di0j7tt/)

### Additional contract requirements

- The operation for grouping by keys must be publicly named `chunk_by`, replacing the misleading `group_by` name.
- Grouping is by consecutive runs: equal keys separated by a different key belong to separate chunks.
