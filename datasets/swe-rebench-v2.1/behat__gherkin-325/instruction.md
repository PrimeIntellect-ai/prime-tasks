CucumberNDJsonAstLoader does not parse tables and pystrings for tests
From https://github.com/Behat/Gherkin/issues/319#issuecomment-2876628868 -
currently we are not comparing `arguments` (TableNode and PyString) in the cucumber CompatibilityTest.

This is because because [CucumberNDJsonAstLoader](https://github.com/Behat/Gherkin/blob/master/src/Loader/CucumberNDJsonAstLoader.php#L139) doesn't attempt to load/parse step arguments.

It looks like those are present in the NDJson (as either `docString` or `dataTable` keys) so I'm not sure whether there was a problem parsing them originally, or whether it was just felt that it was not required.

If possible, we should parse those arguments and compare them to ensure that our parser treats these the same as cucumber/gherkin.
