Do not register the error handler if the DSN is null
<!--
Please provide some context on what problem you are trying to solve and how this feature is going to help.
-->

Related to https://github.com/getsentry/sentry-symfony/issues/46#issuecomment-780003387

> it should be possible to change the way the client is built during the container compilation so that if the DSN is null then we skip adding those integrations to the client.
