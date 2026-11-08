Hinweis auf Verfall von Urlaub ergänzen

**Mail am 01.01**
Aktuell haben wir zwar die Information drin, bis wann der Urlaub genommen werden soll (`account_cron_remind_remaining_vacation_days.txt`), allerdings nicht explizit formuliert, dass er bis XX.XX.XXXX verfällt.


**Mail im Oktober**
Ggf. könnte man den Hinweis auf Verfall in die Oktober Mail packen (`account_cron_currently_left_vacation_days.txt`), oder aber jedem Mitarbeiter zum Jahresbeginn die Information zukommen lassen.

> Nach dem BAG-Urteil aus 2019 können Arbeitgeber ihre Hinweispflicht vergleichbar einfach erfüllen. Danach reicht ein Hinweis jeweils zu Jahresbeginn aus, welcher Urlaubsanspruch für das neue Jahr entstanden ist und dass der Arbeitnehmer diesen bis Jahresende nehmen soll, damit er nicht verfällt.

https://www.juraforum.de/news/arbeitgeber-muessen-resturlaub-gegebenenfalls-ueber-jahre-nachzahlen_258516

### Additional contract requirements

- Die E-Mail mit dem Hinweis auf den offenen Urlaubsanspruch des laufenden Jahres muss den Satz „Du hast noch 10 Tage Urlaub für dieses Jahr offen. Bitte denke daran, deinen Urlaub rechtzeitig zu planen, da der nicht genommenen Resturlaub im kommenden Jahr am 10.04.2023 verfällt.“ enthalten. Ist für das kommende Jahr kein Urlaubskonto vorhanden, wird das Verfallsdatum des laufenden Urlaubskontos auf das kommende Jahr übertragen, sodass der Satz „Du hast noch 10 Tage Urlaub für dieses Jahr offen. Bitte denke daran, deinen Urlaub rechtzeitig zu planen, da der nicht genommenen Resturlaub im kommenden Jahr am 01.04.2023 verfällt.“ lautet.
- Die E-Mail mit dem Hinweis auf den Resturlaub aus dem Vorjahr muss den Satz „Du hast noch 10 Tage Resturlaub aus dem Vorjahr. Bitte plane deinen Resturlaub rechtzeitig, da dieser bis zum 31.03.2022 genommen werden muss und am 01.04.2022 verfällt.“ enthalten.
- Das Modell der E-Mail zum laufenden Jahr enthält den Schlüssel `expiryDateNextYear` mit dem Verfallsdatum.
- Das Modell der E-Mail zum Resturlaub aus dem Vorjahr enthält zusätzlich zu `dayBeforeExpiryDate` den Schlüssel `expiryDate` mit dem Verfallsdatum.
