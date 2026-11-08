EDIFACT Support empty (trigger) segments
Support empty segments like the "SRC" one in IATA PADIS EDIFACT (https://www.iata.org/contentassets/18a5fdb2dc144d619a8c10dc1472ae80/pnrgov20edifact20implementation20guide2016_1.pdf).

When an empty segment (SRC') is reached, this exception is thrown:
`Message: EDIE003 - Invalid processing state: INVALID (previous: TAG_3); input: '''`

We have "fixed" it, but we don't know if it's the best solution :)
