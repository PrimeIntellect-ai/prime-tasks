Ghost issue in data types when adding several extensions makes sushi give up
When we declare an extension that has a valueExpression, if there are other extensions of other types, sushi complains that the other extensions are missing the valueExtension.language.
The conversion works, and goFSH seems to convert it back ok. If we try the roundtrip conversion everything is well.
But sushi complains about errors - it seems these are ghost errors.
And Sushi reports the errors upon exit, which blocks the IG build.

To reproduce:
Try to convert this from fsh to json. Conversion goes ok (and goFSH works which confirms the code is ok), but there are 2 errors:
Removing lines 21 and 22 and/or 23-25 remove the errors, even if those lines are ok.
https://fshschool.org/FSHOnline/#/share/3sU6cfX
