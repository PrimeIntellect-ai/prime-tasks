Exception thrown when calling $message->move() on server that does not support `UID MOVE`
$message->move() triggers fatal error.

Any chance to get it sorted ? Thank you !
Other old library I intend to replace (node) does indeed move the message to the inbox correctly.

Interestingly, $message->markSeen() does work fine when running that standalone.

$message->move('1TEST'); // where 1TEST is the name of an existing folder

**Environment**
- **PHP version:** 8.4.4
- **ImapEngine version:** 1.60
- **IMAP server:** custom

Debug log below
(removed unnecessary fluff)


```php
php listener.php
2025-03-04 16:14:34: << * OK [CAPABILITY IMAP4 IMAP4rev1 ACL RIGHTS=tekx QUOTA LITERAL+ NAMESPACE UIDPLUS CHILDREN BINARY UNSELECT SORT CATENATE URLAUTH LANGUAGE ESEARCH ESORT THREAD=ORDEREDSUBJECT THREAD=REFERENCES CONDSTORE ENABLE QRESYNC CONTEXT=SEARCH CONTEXT=SORT WITHIN SASL-IR SEARCHRES METADATA ID LIST-STATUS SPECIAL-USE CREATE-SPECIAL-USE MULTISEARCH SORT=DISPLAY UTF8=ACCEPT URL-PARTIAL STATUS=SIZE X-SUN-SORT ANNOTATE-EXPERIMENT-1 X-SUN-IMAP XUM1 IDLE XREFRESH AUTH=PLAIN]
2025-03-04 16:14:34: >> TAG1 LOGIN "account" "passwd"
2025-03-04 16:14:34: << TAG1 OK User account logged in
2025-03-04 16:14:34: >> TAG2 LIST "" "INBOX"
2025-03-04 16:14:34: << * LIST (\NoInferiors) "/" INBOX
2025-03-04 16:14:34: << TAG2 OK Completed

Connected: account (INBOX)2025-03-04 16:14:34: >> TAG3 CAPABILITY
2025-03-04 16:14:34: << * CAPABILITY IMAP4 IMAP4rev1 ACL RIGHTS=tekx QUOTA LITERAL+ NAMESPACE UIDPLUS CHILDREN BINARY UNSELECT SORT CATENATE URLAUTH LANGUAGE ESEARCH ESORT THREAD=ORDEREDSUBJECT THREAD=REFERENCES CONDSTORE ENABLE QRESYNC CONTEXT=SEARCH CONTEXT=SORT WITHIN SASL-IR SEARCHRES METADATA ID LIST-STATUS SPECIAL-USE CREATE-SPECIAL-USE MULTISEARCH SORT=DISPLAY LOGIN-REFERRALS UTF8=ACCEPT URL-PARTIAL STATUS=SIZE SAVEDATE XSNIPPET=FUZZY X-SUN-SORT ANNOTATE-EXPERIMENT-1 X-SUN-IMAP XUM1 X-ORCL-AS IDLE
2025-03-04 16:14:34: << TAG3 OK Completed
2025-03-04 16:14:34: << * OK [CAPABILITY IMAP4 IMAP4rev1 ACL RIGHTS=tekx QUOTA LITERAL+ NAMESPACE UIDPLUS CHILDREN BINARY UNSELECT SORT CATENATE URLAUTH LANGUAGE ESEARCH ESORT THREAD=ORDEREDSUBJECT THREAD=REFERENCES CONDSTORE ENABLE QRESYNC CONTEXT=SEARCH CONTEXT=SORT WITHIN SASL-IR SEARCHRES METADATA ID LIST-STATUS SPECIAL-USE CREATE-SPECIAL-USE MULTISEARCH SORT=DISPLAY UTF8=ACCEPT URL-PARTIAL STATUS=SIZE X-SUN-SORT ANNOTATE-EXPERIMENT-1 X-SUN-IMAP XUM1 IDLE XREFRESH AUTH=PLAIN]
2025-03-04 16:14:34: >> TAG1 LOGIN "account" "passwd"
2025-03-04 16:14:34: << TAG1 OK User account logged in
2025-03-04 16:14:34: >> TAG2 LIST "" "INBOX"
2025-03-04 16:14:34: << * LIST (\NoInferiors) "/" INBOX
2025-03-04 16:14:34: << TAG2 OK Completed
2025-03-04 16:14:34: >> TAG3 SELECT "INBOX"
2025-03-04 16:14:34: << * FLAGS (\Answered \Flagged \Draft \Deleted \Seen $Junk $Forwarded)
2025-03-04 16:14:34: << * OK [PERMANENTFLAGS (\Answered \Flagged \Draft \Deleted \Seen $Junk $Forwarded \*)]
2025-03-04 16:14:34: << * 154 EXISTS
2025-03-04 16:14:34: << * 0 RECENT
2025-03-04 16:14:34: << * OK [UNSEEN 1]
2025-03-04 16:14:34: << * OK [UIDVALIDITY 1117538090]
2025-03-04 16:14:34: << * OK [UIDNEXT 4489467]
2025-03-04 16:14:34: << TAG3 OK [READ-WRITE] Completed
2025-03-04 16:14:34: >> TAG4 IDLE
2025-03-04 16:14:34: << + idling
2025-03-04 16:14:38: << * 155 EXISTS
2025-03-04 16:14:38: >> TAG4 SELECT "INBOX"
2025-03-04 16:14:38: << * FLAGS (\Answered \Flagged \Draft \Deleted \Seen $Junk $Forwarded)
2025-03-04 16:14:38: << * OK [PERMANENTFLAGS (\Answered \Flagged \Draft \Deleted \Seen $Junk $Forwarded \*)]
2025-03-04 16:14:38: << * 155 EXISTS
2025-03-04 16:14:38: << * 0 RECENT
2025-03-04 16:14:38: << * OK [UNSEEN 1]
2025-03-04 16:14:38: << * OK [UIDVALIDITY 1117538090]
2025-03-04 16:14:38: << * OK [UIDNEXT 4489468]
2025-03-04 16:14:38: << TAG4 OK [READ-WRITE] Completed
2025-03-04 16:14:38: >> TAG5 FETCH 155 (UID)
2025-03-04 16:14:38: << * 155 FETCH (UID 4489467)
2025-03-04 16:14:38: << TAG5 OK Completed
2025-03-04 16:14:38: >> TAG6 UID FETCH 4489467 (FLAGS)
2025-03-04 16:14:38: << * 155 FETCH (FLAGS () UID 4489467)
2025-03-04 16:14:38: << TAG6 OK Completed
2025-03-04 16:14:38: >> TAG7 UID FETCH 4489467 (BODY.PEEK[HEADER])
2025-03-04 16:14:38: << * 155 FETCH (UID 4489467 BODY [HEADER] {2485}


2025-03-04 16:14:38: << TAG7 OK Completed
2025-03-04 16:14:38: >> TAG8 UID FETCH 4489467 (BODY.PEEK[TEXT])
2025-03-04 16:14:38: << * 155 FETCH (UID 4489467 BODY [TEXT] {14703}

--company-Mail=_9C4F939D-48E2-4F8E-8933-EF08C7F79B7E
Content-Type: multipart/alternative;
	boundary="company-Mail=_01B751D1-1024-4844-A05B-DADEDABDAA70"


--company-Mail=_01B751D1-1024-4844-A05B-DADEDABDAA70
Content-Transfer-Encoding: quoted-printable
Content-Type: text/plain;
	charset=utf-8


--company-Mail=_01B751D1-1024-4844-A05B-DADEDABDAA70
Content-Type: multipart/mixed;
	boundary="company-Mail=_D4CE593B-C50D-401B-849A-59C81CDE05A2"


--company-Mail=_D4CE593B-C50D-401B-849A-59C81CDE05A2
Content-Transfer-Encoding: quoted-printable
Content-Type: text/html;
	charset=utf-8
2025-03-04 16:14:38: << TAG8 OK Completed

Received account (INBOX) : 4489467

***16:14:39*** : account

UID		4489467
MID		3843D5FD-6053-4297-97BF-DBCB8CA5F407@company.com

2025-03-04 16:14:39: << TAG9 BAD Unrecognized command
2025-03-04 16:14:39: >> DONE
2025-03-04 16:14:39: << * 1 RECENT
2025-03-04 16:14:39: << TAG4 OK Completed
2025-03-04 16:14:39: >> TAG5 LOGOUT


************CATCH Throwable DirectoryTree\ImapEngine\Exceptions\ImapCommandException: IMAP command "TAG9 UID MOVE 4489467 "1TEST"" failed. Response: "TAG9 BAD Unrecognized command" in phpengine/vendor/directorytree/imapengine/src/Exceptions/ImapCommandException.php:25
Stack trace:
#0 phpengine/vendor/directorytree/imapengine/src/Connection/ImapConnection.php(682): DirectoryTree\ImapEngine\Exceptions\ImapCommandException::make(Object(DirectoryTree\ImapEngine\Connection\ImapCommand), Object(DirectoryTree\ImapEngine\Connection\Responses\TaggedResponse))
#1 phpengine/vendor/directorytree/imapengine/src/Connection/ImapConnection.php(702): DirectoryTree\ImapEngine\Connection\ImapConnection->{closure:DirectoryTree\ImapEngine\Connection\ImapConnection::assertTaggedResponse():681}(Object(DirectoryTree\ImapEngine\Connection\Responses\TaggedResponse))
#2 phpengine/vendor/directorytree/imapengine/src/Connection/ImapConnection.php(674): DirectoryTree\ImapEngine\Connection\ImapConnection->assertNextResponse(Object(Closure), Object(Closure), Object(Closure))
#3 phpengine/vendor/directorytree/imapengine/src/Connection/ImapConnection.php(372): DirectoryTree\ImapEngine\Connection\ImapConnection->assertTaggedResponse('TAG9')
#4 phpengine/vendor/directorytree/imapengine/src/Message.php(297): DirectoryTree\ImapEngine\Connection\ImapConnection->move('1TEST', 4489467)
#5 phpengine/listener.php(637): DirectoryTree\ImapEngine\Message->move('1TEST')
#6 phpengine/listener.php(792): process_message(Object(DirectoryTree\ImapEngine\Message), false)
#7 phpengine/vendor/directorytree/imapengine/src/Folder.php(131): {closure:phpengine/listener.php:790}(Object(DirectoryTree\ImapEngine\Message))
#8 phpengine/vendor/directorytree/imapengine/src/Idle.php(66): DirectoryTree\ImapEngine\Folder->{closure:DirectoryTree\ImapEngine\Folder::idle():112}(155)
#9 phpengine/vendor/directorytree/imapengine/src/Idle.php(43): DirectoryTree\ImapEngine\Idle->listen(Object(Closure), Object(Carbon\Carbon))
#10 phpengine/vendor/directorytree/imapengine/src/Folder.php(111): DirectoryTree\ImapEngine\Idle->await(Object(Closure))
#11 phpengine/listener.php(790): DirectoryTree\ImapEngine\Folder->idle(Object(Closure), Object(Closure), 90)
#12 {main}******account (INBOX)********16:14:39
```
