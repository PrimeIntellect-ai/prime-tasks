Ignore "_" vars in "Unused Variable" check

*Original report by [archardlias](https://launchpad.net/~archardlias) on [Launchpad](https://bugs.launchpad.net/bugs/1328169):*

------------------------------------

Would it be possible to ignore variables named "_" from "Unused Variable" checks?

I'm not really sure whether "_" is officially specified anywhere. But I do see it a lot and in a lot of languages including python to denote a variable to be ignored (place holder dummy). PyLint implements this pseudo(?)-convention (? second-hand knowledge).

Would be great, since I would love to be explicit about "things returned but not used" instead of just calling without assignment which looks tantamount to "this function does never return anything / does not contain a return statement". A great plus in signature visibility throughout the code, specially for first-time readers.

Best regards,
~arlias
