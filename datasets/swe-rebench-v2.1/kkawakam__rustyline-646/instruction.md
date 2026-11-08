Caret key (`^`) does not work as expected in evcxr_repl in vi edit mode
I originally posted the issue in google/evcxr#239 , but it turned out to be a bug of thi scrate, rustyline.

> Caret key should jump the cursor to the first non-empty character in the current line.  But it is implemented that it instead jumps ...
```
>> abc def
       ^ here.
```
> Seems that it instead moves the cursor to the character right after the first whitespace instead.

This seems due to a wrong implementation [here](https://github.com/kkawakam/rustyline/blob/05f94b12fb94a2329d5227b10a8520a93ad4a893/src/command.rs#L52-L55):

[HIDDEN]

In this implementation, it first jumps to the beginning of the line, and then move to the "next" word considering any consecutive sequence of non-empty characters as a word.   [HIDDEN]

I am nst sure how should I properly fix it.  `s.edit_move_to_next_word` eventually calls `LineBuffer::next_word_pos` to find the actual position to jump to.   Should I modify the signature of this method to accept an additional argument for "Inclusive/Exclusive" enum?  Or shuold I call a different method in the `Move(ViFirstPrint)` match arm?

### Additional contract requirements

- In vi edit mode, pressing `^` moves the cursor to the first non-whitespace character in the current line.
