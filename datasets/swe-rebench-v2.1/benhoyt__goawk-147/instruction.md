Semicolon not allowed as terminator for normal pattern without action
Hi, I've studied the Posix awk spec (same as linked in the readme) because I noticed a parsing difference between awk and gawk. This lead me to test other implementations as well, and I noticed a bug in GoAWK's parsing.

GoAWK fails to accept semicolon as the terminator for a normal pattern without action, this is allowed by the Posix grammar and also accepted by other major awk implementations.

Example of a failing program:

```awk
normal_pattern ; item
```

The program should work the same way it does when the two items are on separate lines, but instead it gives the following parse error:

```
<cmdline>:1:16: expected , instead of ;
normal_pattern ; item
               ^
```

I've implemented a possible fix for this and could submit a PR if you wish.

<details>
<summary>The relevant parts of the Posix grammar</summary>

```
program          : item_list
                 | item_list item
                 ;

item_list        : /* empty */
                 | item_list item terminator
                 ;

item             : action
                 | pattern action
                 | normal_pattern
                 | ...
                 ;

terminator       : terminator NEWLINE
                 |            ';'
                 |            NEWLINE
                 ;
```
</details>

<details>
<summary>And the original difference that got me here with some pondering about the posix spec...</summary>

First I noticed that awk accepts the following code, but gawk (and mawk) produces a syntax error at `function`:

```awk
normal_pattern function name() {}
```

From this, I deduced that awk does not require the terminator between items at any point, but I wanted to see what would be correct according to Posix.

After reading the spec, however, it seems to me that a terminator is required between any two items.
But all major implementations seem to treat the terminator as optional when the previous item ends with a closing brace. In my opinion this is a bug in either my reading comprehension or in the Posix spec, and the status quo of the implementations is the way to go.

The only possibly applicable exception mentioned in the text (that I could find) was about function definitions, not actions in general:
> In the function definition, <newline> characters shall be optional before the opening brace and after the closing brace.
</details>
