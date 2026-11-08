Empty lines should not be indented
I would not expect any warnings or errors with the following code:

```
plugin.tx_gkhrssimport_pi1 = USER
plugin.tx_gkhrssimport_pi1 {
	userFunc = GertKaaeHansen\GkhRssImport\Controller\RssImportController->main

	templateFile = {$plugin.tx_gkhrssimport_pi1.templateFile}
}
```

but I get a warning that my indent on line 4 is wrong (the empy line) and expected to be 1 tab.

My requirement is that empty lines should always have no indent no matter where they are.
