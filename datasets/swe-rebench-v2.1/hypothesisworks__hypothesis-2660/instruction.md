`st.from_regex(re.compile("[\u0130_]", re.IGNORECASE))` triggers internal error
`\u0130`, Latin Capital Letter I with Dot Above, lower-cases to `i\u0307`; and in turn if we have this in a regex character set we eventually trigger an internal error by passing it to `ord()` (which requires single-character strings).

I suspect that this is symptomatic of more general mishandling of length-changing case handling and will investigate.

### Additional contract requirements

- For this pattern, the strategy must be able to generate a string of length greater than one.
- For `st.from_regex(re.compile("[^İ]+", re.IGNORECASE), fullmatch=True)`, generated strings must contain neither `i` nor `\u0307`.
