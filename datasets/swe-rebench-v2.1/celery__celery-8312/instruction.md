Why has the CLI worker command flag `optimizations` changed from `--optimizations` in 5.*?
This question is referencing this code:

https://github.com/celery/celery/blob/3b1c768c39f641a70d3086bd5a1079a421f94344/celery/bin/worker.py#L169
```
@click.option('optimization',
              '-O',
              default='default',
              cls=CeleryOption,
              type=click.Choice(('default', 'fair')),
              help_group="Worker Options",
              help="Apply optimization profile.")
```
Why has the flag removed the double hyphen? It seems like a bug, but I assume there was a reason for it? The reason I'm asking is that this change breaks a bunch of code we have, so I'd like to understand the change.

### Additional contract requirements

- The `celery worker` optimization option must also accept the long form `--optimization` in addition to the short `-O`. Both spellings accept the same values (`default` or `fair`); when the option is omitted the value is `default`.
