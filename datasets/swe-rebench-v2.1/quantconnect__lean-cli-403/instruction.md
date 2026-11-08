DataProvider not valid for `_configure_environment()` in Lean v1.0.178
When you have tried to run backtest with **any** `--data-provider` I got error below.
### Error Message
```
D:\source>lean backtest --data-provider Polygon IQFeedAlgo --verbose
Context information:
  Python version: 3.8.10 (tags/v3.8.10:3d8993a, May  3 2021, 11:48:03) [MSC v.1928 64 bit (AMD64)]
  OS: Windows-10-10.0.19045-SP0
  Lean CLI version: 1.0.178
json_module_handler.get_and_build_module(): non-interactive: essential_properties_value with module Polygon: {}
json_module_handler.get_and_build_module(): non-interactive: required_properties_value with module Polygon: {'polygon-api-key': 'XXX'}
LeanConfigConfigurer.ensure_module_installed(): installing module for module PolygonDataFeed: 306
--> POST https://www.quantconnect.com/api/v2/modules/list with data:
{
    "productId": "XXX",
    "organizationId": "XXXXXXXXX"
}
Request response:
{"files":["QuantConnect.Polygon.2.5.16107.nupkg","QuantConnect.Polygon.2.5.16111.nupkg","QuantConnect.Polygon.2.5.16118.nupkg","QuantConnect.Polygon.2.5.16120.nupkg","QuantConnect.Polygon.2.5.16121.nupkg","Quan
tConnect.Polygon.2.5.16123.nupkg","QuantConnect.Polygon.2.5.16127.nupkg","QuantConnect.Polygon.2.5.16128.nupkg","QuantConnect.Polygon.2.5.16130.nupkg","QuantConnect.Polygon.2.5.16131.nupkg","QuantConnect.Polygo
n.2.5.16133.nupkg","QuantConnect.Polygon.2.5.16135.nupkg","QuantConnect.Polygon.2.5.16138.nupkg","QuantConnect.Polygon.2.5.16140.nupkg","QuantConnect.Polygon.2.5.16142.nupkg","QuantConnect.Polygon.2.5.16144.nup
kg","QuantConnect.Polygon.2.5.16152.nupkg","QuantConnect.Polygon.2.5.16155.nupkg","QuantConnect.Polygon.2.5.16158.nupkg","QuantConnect.Polygon.2.5.16159.nupkg","QuantConnect.Polygon.2.5.16161.nupkg","QuantConne
ct.Polygon.2.5.16163.nupkg","QuantConnect.Polygon.2.5.16164.nupkg","QuantConnect.Polygon.2.5.16165.nupkg","QuantConnect.Polygon.2.5.16167.nupkg","QuantConnect.Polygon.2.5.16168.nupkg","QuantConnect.Polygon.2.5.
16169.nupkg","QuantConnect.Polygon.2.5.16173.nupkg","QuantConnect.Polygon.2.5.16175.nupkg","QuantConnect.Polygon.2.5.16178.nupkg","QuantConnect.Polygon.2.5.16182.nupkg","QuantConnect.Polygon.2.5.16183.nupkg","Q
uantConnect.Polygon.2.5.16187.nupkg"],"success":true}
ModuleManager._download_file(): C:\Users\NickoMR\.lean\modules\QuantConnect.Polygon.2.5.16187.nupkg already exists locally
Traceback (most recent call last):
  File "c:\program files\python38\lib\site-packages\lean\main.py", line 94, in main
    lean.main(standalone_mode=False)
  File "c:\program files\python38\lib\site-packages\click\core.py", line 1078, in main
    rv = self.invoke(ctx)
  File "c:\program files\python38\lib\site-packages\click\core.py", line 1688, in invoke
    return _process_result(sub_ctx.command.invoke(sub_ctx))
  File "c:\program files\python38\lib\site-packages\lean\click.py", line 159, in invoke
    result = super().invoke(ctx)
  File "c:\program files\python38\lib\site-packages\click\core.py", line 1434, in invoke
    return ctx.invoke(self.callback, **ctx.params)
  File "c:\program files\python38\lib\site-packages\click\core.py", line 783, in invoke
    return __callback(*args, **kwargs)
  File "c:\program files\python38\lib\site-packages\lean\commands\backtest.py", line 373, in backtest
    data_provider_configurer.configure(lean_config, "backtesting")
  File "c:\program files\python38\lib\site-packages\lean\models\lean_config_configurer.py", line 34, in configure
    self._configure_environment(lean_config, environment_name)
  File "c:\program files\python38\lib\site-packages\lean\models\lean_config_configurer.py", line 55, in _configure_environment
    raise ValueError(f'{self.__class__.__name__} not valid for _configure_environment()')
ValueError: DataProvider not valid for _configure_environment()
Error: DataProvider not valid for _configure_environment()
```

### Lean version
```
D:\source>pip show lean
Name: lean
Version: 1.0.178
Summary: A CLI aimed at making it easier to run QuantConnect's LEAN engine locally and in the cloud
Home-page: https://lean.io/cli
Author: QuantConnect
Author-email: support@quantconnect.com
License: UNKNOWN
Location: c:\program files\python38\lib\site-packages
Requires: requests, maskpass, docker, click, pydantic, python-dateutil, setuptools, quantconnect-stubs, joblib, json5, rich, lxml, wrapt, cryptography
Required-by:
```


See https://github.com/QuantConnect/lean-cli/pull/399
