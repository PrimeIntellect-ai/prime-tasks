Exempt protected setUp/tearDown for ClassThingsOrder
If you have a setup method, it has to be declared protected, but then we get a lint warning. Can we make an exception for the setUp method and possibly also teardown? (As they are protected, but we still likely want them at the top, #edgeCase)
