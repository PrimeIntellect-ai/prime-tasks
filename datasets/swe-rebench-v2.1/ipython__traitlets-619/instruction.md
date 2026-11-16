consider allowing logging.LoggingAdapter to be a LoggingConfigurable.log
Sphinx uses `logging.LoggingAdapter` as its own logger, while nbconvert classes all inherit from traitlets `LoggingConfigurable`, and require the `log` trait to be a `logging.Logger`. This prevents passing sphinx logger to nbconvert classes. At the same time, docs [state](https://docs.python.org/3/library/logging.html#logging.LoggerAdapter):

> ...These methods have the same signatures as their counterparts in Logger, so you can use the two types of instances interchangeably.
