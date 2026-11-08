flag_value converted to str in Click 8
Consider the following code:

```python
import click

@click.command()
@click.option("--answer", flag_value=42)
def main(answer):
    click.echo(repr(answer))

if __name__ == '__main__':
    main()
```

Under click 7, passing the `--answer` option to this script prints `42` (an int), as expected.  Under click 8, it prints `'42'` (a str).

Environment:

- Python version: 3.9.5
- Click version: 7.1.2 vs. 8.0.0

### Additional contract requirements

- When an option has an integer `flag_value` and no explicit `type` is given, the option's public `type` attribute must be `click.INT`.
