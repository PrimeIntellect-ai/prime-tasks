WhatFailureGroupHandler does not catch errors from method close
Monolog version 2

`\Monolog\Handler\WhatFailureGroupHandler` does not catch errors from method `\Monolog\Handler\HandlerInterface::close`.
That means when close is called on handler and handler tries for example send remaining buffer to remote service but fails, then failure propagates though WhatFailureGroupHandler and execution ends with fatal error.
