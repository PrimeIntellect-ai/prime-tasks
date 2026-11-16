Tests fail at PHP 8.2
## URL address of the page where you encountered the problem

Build Tests with PHP 8.2, e.g. https://github.com/NatLibFi/Skosmos/actions/runs/4221747584/jobs/7329412738

## Description of the problem

Dynamic properties are deprecated in PHP 8.2. It looks like these are only used at two places so fixing might be easy:

> Deprecated: Creation of dynamic property PluginRegister::$pluginOrder is deprecated in /app/model/PluginRegister.php on line 8
> Deprecated: Creation of dynamic property VocabularyConfig::$globalPlugins is deprecated in /app/model/VocabularyConfig.php on line 35

But I don't use PHP 8.2 locally so it's difficult to examine.
