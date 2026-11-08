Sync issue with darwin calendar server
This issue was moved from the issue tracker at GitLab.

---

I am trying creating a todo and then syncing it with darwin calendar server.
That fails with following error from darwin calendar server:

    2016-04-15 02:55:17+0300 [-] [caldav-1]  [-] [twistedcaldav.method.put_common#error] Invalid calendar data: Calendar data had unfixable problems:
    2016-04-15 02:55:17+0300 [-] [caldav-1]           [VTODO] Missing or too many required property: DTSTAMP

What I did:
1. I installed current version of todoman with pip.
1. Set up sync with darwin calendar server with vdirsyncer. Setup works (I can sync calendar/todo items, edit todos created from other sources, etc).
1. Tried to create new todo with following line: __todo new -l calendar "test todo"__
1. Todo is created locally and can be seen/modified
1. Sync fails with quoted error in server logs.

Resulting file (and file with same summary, but created from android "tasks" application, that syncs successfully are attached.
[fail.ics](/uploads/71ee030b4c82d2a875d43bd0b2e9953c/fail.ics)
[success.ics](/uploads/2208fb32e07c21c549f0aa2fdd75f586/success.ics)

The successful one does contain DTSTAMP field.
