Kein ics-Anhang in der Bestätigungs-Mail bei Urlauben ohne Genehmigungsprozess
**Describe the bug**
Bei Urlauben **mit** Genehmigungsprozess bekommt der Antragsteller nach der Genehmigung eine "Deine Abwesenheit wurde genehmigt"-Mail  mit einem calender.ics im Anhang.
Bei Urlauben **ohne** Genehmigungsprozess bekommt der Antragsteller eine "Deine Abwesenheit wurde erstellt"-Mail, die aber keinen .ics-Anhang enthält.

**Expected behavior**
Bestätigungsmails **mit** .ics-Anhang auch bei Urlauben ohne Genehmigungsprozess

### Additional contract requirements

- The confirmation email sent to the applicant for an absence without an approval process ("Deine Abwesenheit wurde erstellt") includes the calendar attachment under the exact attachment name `calendar.ics`.
