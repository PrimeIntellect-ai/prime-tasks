Problem with unescaped character %
I have a little bot which was sending me a message `https://da.wikipedia.org/wiki/J%C3%A6vnd%C3%B8gn 🔭` as `https://da.wikipedia.org/wiki/J%!C(MISSING)3%!A(MISSING)6vnd%!C(MISSING)3%!B(MISSING)8gn`.

@SamWhited figured out that it probably happens due to fprintf in the library which considered % a control character. [HIDDEN]

But even with that little workaround there is still a problem as `Septemberjævndøgn ⌘ https://da.wikipedia.org/wiki/J%C3%A6vnd%C3%B8gn 🔭` turns to `Septemberjvndgn  https://da.wikipedia.org/wiki/J%C3%A6vnd%C3%B8gn`.

### Additional contract requirements

- Sending content must preserve literal `%` characters and all Unicode characters, including accented letters and emoji, without altering or dropping them.
