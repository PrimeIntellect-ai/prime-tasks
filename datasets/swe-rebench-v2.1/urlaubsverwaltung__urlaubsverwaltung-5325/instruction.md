Überstunden: Ohne bearbeiten Kommentar hinzufügen
**Is your feature request related to a problem? Please describe.**

Beim Urlaubsantrag und Krankmeldungen können Kommentare ohne editieren des Urlaubsantrags bzw. Krankmeldung direkt hinzugefügt werden über folgende Funktionalität:

![Image](https://github.com/user-attachments/assets/57685e2a-858b-49b7-924d-67b9a695bd45)

Dieses Verhalten ist auch bei Überstunden gewünscht.

### Additional contract requirements

- The enum `OvertimeCommentAction` in package `org.synyx.urlaubsverwaltung.overtime` gains the value `COMMENTED`.
- The public interface `org.synyx.urlaubsverwaltung.overtime.OvertimeService` gains the method `OvertimeComment saveComment(Overtime overtime, OvertimeCommentAction action, String comment, Person author)`. It persists a new comment for the given overtime record and returns the saved comment.
- A POST endpoint at `/web/overtime/{id}/comment` accepts a form field `text` with the comment content. If the overtime record identified by `{id}` does not exist, it fails with `UnknownOvertimeException`. If the signed-in user is not allowed to write on the overtime record, it fails with `AccessDeniedException`. On success it saves the comment with action `COMMENTED` and redirects to `/web/overtime/{id}`.
