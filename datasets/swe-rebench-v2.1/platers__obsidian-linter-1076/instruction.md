Bug: forbidden character combinations while copy & pasting the text of a website to a note
I have this note:

![image](https://github.com/platers/obsidian-linter/assets/4138869/6953d532-e720-45d1-9b3b-6a5300e2fdf7)

with this markdown:


```

---
aliases: [avm, Fritz, Fritzbox, AX, Router, ntp, timeserver]
tags: [avm, FritzBox, Fritz, AX, Router, privat, account, ntp, timeserver, Zeitserver, Braunschweig]
filename: muell-Linter
erstellt: Donnerstag, 22. Februar 2024, 10:24:46 Uhr
geändert: Samstag, 06. April 2024, 22:48:11 Uhr
---

`

#`

```

If I linter it, the first "[" after "tags:" is deleted and at the end there is a ", `" instead of a "]":

![image](https://github.com/platers/obsidian-linter/assets/4138869/8f75f0ba-7e8f-4fb0-8b5e-b6727b6ff8e5)


[muell-Linter.md](https://github.com/platers/obsidian-linter/files/14894965/muell-Linter.md)

This causes after lintering again this error message:

![image](https://github.com/platers/obsidian-linter/assets/4138869/2fd60b46-540d-4304-b84d-13eed7bfefa7)

(Background: I copied the text part of this website https://www.cyberciti.biz/faq/linux-unix-bsd-is-ntp-client-working/ and pasted it into a note. This error occured, but I've narrowed it down.)

It would be nice, if your linter plugin could recognize issues like this and repair them.
