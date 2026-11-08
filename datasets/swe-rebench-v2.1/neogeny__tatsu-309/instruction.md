Surprising whitespace handling
Given this example
```python
import tatsu

parser = tatsu.compile(r'''
statement = 'SELECT' 'FROM' table $ ;
table = name:id ;
id = /[a-z]+/ ;
''')

string = 'SELECT FROM   foo'
value = parser.parse(string, parseinfo=True)

table = value[2]
assert table['name'] == 'foo'

parseinfo = table['parseinfo']
print(parseinfo.tokenizer.text)
print(f'{parseinfo.pos * " "}^')
```
I find whitespace handling a surprising. The whitespace between `FROM` and the table name is not skipped over before matching the `table` rule. This results in correct parsing but the `parseinfo` for the `table` rule. I would have expected whitespace to be skipped before attempting to match the `table` rule.
