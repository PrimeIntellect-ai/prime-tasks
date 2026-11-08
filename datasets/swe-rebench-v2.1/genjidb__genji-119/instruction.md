UPDATE ... SET updates the wrong array indexes
when we add a field into a document which contains an array with multiple indexes,  the field is added but the first index is replaced by the next.

`
INSERT INTO users (a) VALUES ([1, 0, 0]), ([2, 0]);
UPDATE users set min = 0;
select * from users;
{  "a": [ 1, 0, 0]}
{"a": [ 2, 0]}
`
The result is this:
`
{  "a": [ 2, 0], "min":  0}
{  "a": [ 2, 0], "min":  0}`

We can see the first index replaced by the next.

instead of
`
{  "a": [ 1, 0, 0], "min":  0}
{"a": [ 2, 0], "min":  0}
`

I probably do the correction with the issue #92
