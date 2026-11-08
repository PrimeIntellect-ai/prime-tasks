Singleton `emptyList` is problematic
I just ran down a nasty bug related to this code below:

https://github.com/immutable-js/immutable-js/blob/493afba6ec17d9c999dc5a15ac80c71c6bdba1c3/src/List.js#L413

I did not realize that every time I was creating a new list with `List()`, I was getting the same _instance_ of `List`. This seems counterintuitive in a library based on the idea of immutability.

Some code in the project was mutating an instance of an empty list which caused all subsequent newly minted lists to be non-empty. Obviously the code in my project was incorrect, but I came here to suggest _not_ using a singleton pattern here regardless.
