Custom default label ignored if default is None
I found out that custom default label is not shown when `default` is `None`. In some cases `default = None` is intentional, but custom default label would be still helpful.

An example with `--limit` option, with `None` as `default` meaning no limit:
```python
import click

@click.command()
@click.option('--limit', type=int, show_default='unlimited')
def main(limit: int):
    print('Limit: {}'.format(limit))

if __name__ == '__main__':
    main()
```

### Expected Behavior
Tell us what should happen.

```sh
$ python3 /tmp/foo.py --help
Usage: foo.py [OPTIONS]

Options:
  --limit INTEGER  [default: unlimited]
  --help           Show this message and exit.
```

### Actual Behavior
Tell us what happens instead.

```sh
$ python3 /tmp/foo.py --help
Usage: foo.py [OPTIONS]

Options:
  --limit INTEGER
  --help           Show this message and exit.
```
Default is not shown, making the description less useful.

### Environment

* Python version: 3.9.1
* Click version: 7.1.2
