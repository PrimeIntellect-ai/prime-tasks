Sentry trace Serializer issue
sentry/sentry  sdk 2.4.1

Hi guys,

We create a magento sentry integration. It works well, except in this scenario.

It requires Magento 2 knowledge

In sentry I see issue with such a name
```Cannot declare class Vendor\Customer\Plugin\Api\CustomerRepositoryPlugin, because the name is already in use```

Inside issue in the message there is a actual exception message. No real Exception trace, just trace about class redeclare.

```
 in include called at /var/www/magento/releases/20201001162424/vendor/composer/ClassLoader.php (444)
 in Composer\Autoload\includeFile called at /var/www/magento/releases/20201001162424/vendor/composer/ClassLoader.php (322)
 in Composer\Autoload\ClassLoader::loadClass called at ? (?)
 in spl_autoload_call called at ? (?)
 in is_callable called at /var/www/magento/releases/20201001162424/vendor/sentry/sentry/src/Serializer/AbstractSerializer.php (102)
 in Sentry\Serializer\AbstractSerializer::serializeRecursively called at /var/www/magento/releases/20201001162424/vendor/sentry/sentry/src/Serializer/AbstractSerializer.php (110)
 in Sentry\Serializer\AbstractSerializer::serializeRecursively called at /var/www/magento/releases/20201001162424/vendor/sentry/sentry/src/Serializer/RepresentationSerializer.php (21)
 in Sentry\Serializer\RepresentationSerializer::representationSerialize called at /var/www/magento/releases/20201001162424/vendor/sentry/sentry/src/Stacktrace.php (177)
 in Sentry\Stacktrace::addFrame called at /var/www/magento/releases/20201001162424/vendor/sentry/sentry/src/Stacktrace.php (102)
 in Sentry\Stacktrace::createFromBacktrace called at /var/www/magento/releases/20201001162424/vendor/sentry/sentry/src/EventFactory.php (149)
 in Sentry\EventFactory::addThrowableToEvent called at /var/www/magento/releases/20201001162424/vendor/sentry/sentry/src/EventFactory.php (110)
 in Sentry\EventFactory::create called at /var/www/magento/releases/20201001162424/vendor/sentry/sentry/src/Client.php (183)
 in Sentry\Client::prepareEvent called at /var/www/magento/releases/20201001162424/vendor/sentry/sentry/src/Client.php (118)
 in Sentry\Client::captureEvent called at /var/www/magento/releases/20201001162424/vendor/sentry/sentry/src/Client.php (110)
 in Sentry\Client::captureException called at /var/www/magento/releases/20201001162424/vendor/sentry/sentry/src/State/Hub.php (132)
 in Sentry\State\Hub::captureException called at /var/www/magento/releases/20201001162424/vendor/mygento/module-sentry/Model/SentryHandler.php (285)
 in Mygento\Sentry\Model\SentryHandler::Mygento\Sentry\Model\{closure} called at /var/www/magento/releases/20201001162424/vendor/sentry/sentry/src/State/Hub.php (87)
 in Sentry\State\Hub::withScope called at /var/www/magento/releases/20201001162424/vendor/mygento/module-sentry/Model/SentryHandler.php (289)
 in Mygento\Sentry\Model\SentryHandler::write called at /var/www/magento/releases/20201001162424/vendor/monolog/monolog/src/Monolog/Handler/AbstractProcessingHandler.php (39)
 in Monolog\Handler\AbstractProcessingHandler::handle called at /var/www/magento/releases/20201001162424/vendor/monolog/monolog/src/Monolog/Logger.php (344)

```

AbstractSerializer.php somehow recreates plugin class

### Additional contract requirements

- When callable inspection triggers an exception, the exception is silently ignored and serialization continues as if the value were not a callable: a string callable is represented by its own name, and an array callable is represented by its elements. No error marker is appended.
