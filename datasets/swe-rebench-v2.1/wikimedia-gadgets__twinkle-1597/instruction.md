protect: fails to write /* {{pp|small=y}} */ when protecting page model Sanitized CSS
Requested by Izno on Discord.

When attempting to protect a .css page and asking Twinkle to tag it with a protection template, no protection templates are written and some errors are thrown.

Desired behavior: Append `/* {{pp|small=y}} */` to the top of the Wikicode.

Diff: https://en.wikipedia.org/w/index.php?title=Template:Contains_special_characters/styles.css&diff=1092331828&oldid=1092331785

Steps to reproduce:
- go to https://test.wikipedia.org/wiki/Template:Contains_special_characters/styles.css
- unprotect
- reprotect at template editor level for both edit and move

Is throwing API error templatestyles-error-invalid-selector-list

![2022-06-09_114628](https://user-images.githubusercontent.com/79697282/172923003-2ae346ca-f326-473f-8459-6c22f665a0e1.png)

![2022-06-09_114848](https://user-images.githubusercontent.com/79697282/172923013-91eb01e7-a737-4e3d-bb0d-f445a1acf475.png)
