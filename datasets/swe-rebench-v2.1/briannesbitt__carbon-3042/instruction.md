Unserialize from Carbon v2 objects
Related to #3002

Running with Carbon v2:
```php
echo serialize(Carbon::parse('-2 months')->diffAsCarbonInterval());
```

We obtain:
```
O:21:"Carbon\CarbonInterval":22:{s:1:"y";i:0;s:1:"m";i:2;s:1:"d";i:0;s:1:"h";i:0;s:1:"i";i:0;s:1:"s";i:0;s:1:"f";d:5.4E-5;s:6:"invert";i:0;s:4:"days";b:0;s:11:"from_string";b:0;s:9:" * tzName";N;s:7:" * step";N;s:22:" * localMonthsOverflow";N;s:21:" * localYearsOverflow";N;s:25:" * localStrictModeEnabled";N;s:24:" * localHumanDiffOptions";N;s:22:" * localToStringFormat";N;s:18:" * localSerializer";N;s:14:" * localMacros";N;s:21:" * localGenericMacros";N;s:22:" * localFormatFunction";N;s:18:" * localTranslator";N;}
```

Then when running in Carbon v3:
```php
unserialize($string); // $string being the serialized data above
```

It chokes on `tzName` (which has been renamed `timezoneSetting`)

Carbon version: **3.3.1**

PHP version: **8.3**
