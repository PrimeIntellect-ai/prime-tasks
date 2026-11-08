Handle deprecation of the `actionLevel` argument in finger crossed strategies
Form Symfony 6, the `actionLevel` must be an inner strategy instead of plain old value / string / int.

To prevent the deprecation, when creating the definition of the bridge's strategy, we should probably [HIDDEN] as is done in the bridges ?

See https://github.com/symfony/monolog-bridge/blob/5.x/Handler/FingersCrossed/HttpCodeActivationStrategy.php#L39-L44 and https://github.com/symfony/monolog-bridge/blob/5.x/Handler/FingersCrossed/NotFoundActivationStrategy.php#L39-L44

### Additional contract requirements

When a finger-crossed handler excludes 404 responses or other HTTP codes, its configured action level must also be supplied to the bridge strategy as an activation-strategy object when using the Symfony 6 API.
