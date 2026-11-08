Autoconfigure resettable processors with the kernel.reset tag
Hi,

As of writing this, handlers implementing the monolog `ResettableInterface` are correctly configured with the Symfony `kernel.reset` service tag.

See here:
https://github.com/symfony/monolog-bundle/blob/72e798ccdcfd277a6bc88e934b43f618732e3561/DependencyInjection/MonologExtension.php#L881-L883

I suggest we should do the same thing for processors implementing the monolog `ResettableInterface`.

It could be handy for the auto-configuration of the `UidProcessor` for instance: https://github.com/Seldaek/monolog/blob/master/src/Monolog/Processor/UidProcessor.php

If it is something that you would be interested in I could write a PR, I'm just asking for your opinion about that idea first :)

Thank you!
