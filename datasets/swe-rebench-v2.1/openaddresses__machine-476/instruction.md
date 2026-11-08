Muffle confusing output when running unit tests
A successful unittest run via `test.py` still outputs a bunch of confusing junk. Make the tests easier for new developers to feel confident about by muffling all that output from `logging` module.

### Additional contract requirements

- Add a public function `reset_logger()` in module `openaddr.ci` that takes no arguments and restores the `openaddr` logger to the state it had before the most recent call to `setup_logger`, restoring its previous logging level and removing the handlers that `setup_logger` added.
- The Flask application reads a `MINIMUM_LOGLEVEL` configuration key (defaulting to `logging.WARNING`) and uses it as the minimum log level for the `openaddr` logger.
