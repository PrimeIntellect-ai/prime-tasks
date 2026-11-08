Errors thrown by ImapParser during Folder::idle
PHP 8.4.3
ImapEngine 1.0.1
Custom


I am getting some of these randomly:



```bash

************CATCH Throwable DirectoryTree\ImapEngine\Exceptions\ImapParserException: Empty response in /vendor/directorytree/imapengine/src/Connection/ImapParser.php:54
Stack trace:
#0 /vendor/directorytree/imapengine/src/Connection/ImapConnection.php(720): DirectoryTree\ImapEngine\Connection\ImapParser->next()
#1 /vendor/directorytree/imapengine/src/Connection/ImapConnection.php(527): DirectoryTree\ImapEngine\Connection\ImapConnection->nextReply()
#2 /vendor/directorytree/imapengine/src/Idle.php(149): DirectoryTree\ImapEngine\Connection\ImapConnection->idle(60)
#3 /vendor/directorytree/imapengine/src/Idle.php(58): DirectoryTree\ImapEngine\Idle->idle()
#4 /vendor/directorytree/imapengine/src/Idle.php(43): DirectoryTree\ImapEngine\Idle->listen(Object(Closure), Object(Carbon\Carbon))
#5 /vendor/directorytree/imapengine/src/Folder.php(105): DirectoryTree\ImapEngine\Idle->await(Object(Closure))
#6 /listener.php(181): DirectoryTree\ImapEngine\Folder->idle(Object(Closure), Object(Closure), 60)
#7 {main}
```
I have enabled debug to provide more context to you when these happen.

Just catched one, see (they seem to be way more often that the very random ones I was getting before with your 5.x previous library):

```bash

2025-02-13 10:56:38: >> TAG3 SELECT "INBOX"
2025-02-13 10:56:38: << * FLAGS (\Answered \Flagged \Draft \Deleted \Seen)
2025-02-13 10:56:38: << * OK [PERMANENTFLAGS (\Answered \Flagged \Draft \Deleted \Seen \*)]
2025-02-13 10:56:38: << * 157 EXISTS
2025-02-13 10:56:38: << * 0 RECENT
2025-02-13 10:56:38: << * OK [UNSEEN 1]
2025-02-13 10:56:38: << * OK [UIDVALIDITY 1279614776]
2025-02-13 10:56:38: << * OK [UIDNEXT 301026]
2025-02-13 10:56:38: << TAG3 OK [READ-WRITE] Completed
2025-02-13 10:56:38: >> TAG4 IDLE
2025-02-13 10:56:38: << idling
2025-02-13 10:58:37: >> DONE
2025-02-13 10:58:37: << TAG4 OK Completed
2025-02-13 10:58:37: >> TAG5 LOGOUT


************CATCH Throwable DirectoryTree\ImapEngine\Exceptions\ImapParserException: Empty response in phpengine/vendor/directorytree/imapengine/src/Connection/ImapParser.php:54
Stack trace:
#0 phpengine/vendor/directorytree/imapengine/src/Connection/ImapConnection.php(720): DirectoryTree\ImapEngine\Connection\ImapParser->next()
#1 phpengine/vendor/directorytree/imapengine/src/Connection/ImapConnection.php(527): DirectoryTree\ImapEngine\Connection\ImapConnection->nextReply()
#2 phpengine/vendor/directorytree/imapengine/src/Idle.php(149): DirectoryTree\ImapEngine\Connection\ImapConnection->idle(60)
#3 phpengine/vendor/directorytree/imapengine/src/Idle.php(58): DirectoryTree\ImapEngine\Idle->idle()
#4 phpengine/vendor/directorytree/imapengine/src/Idle.php(43): DirectoryTree\ImapEngine\Idle->listen(Object(Closure), Object(Carbon\Carbon))
#5 phpengine/vendor/directorytree/imapengine/src/Folder.php(105): DirectoryTree\ImapEngine\Idle->await(Object(Closure))
#6 phpengine/listener.php(181): DirectoryTree\ImapEngine\Folder->idle(Object(Closure), Object(Closure), 60)
#7 {main}******account ONE**********10:58:37

2025-02-13 10:58:37: >> DONE
2025-02-13 10:58:37: << TAG4 OK Completed
2025-02-13 10:58:37: >> TAG5 LOGOUT


************CATCH Throwable DirectoryTree\ImapEngine\Exceptions\ImapParserException: Empty response in phpengine/vendor/directorytree/imapengine/src/Connection/ImapParser.php:54
Stack trace:
#0 phpengine/vendor/directorytree/imapengine/src/Connection/ImapConnection.php(720): DirectoryTree\ImapEngine\Connection\ImapParser->next()
#1 phpengine/vendor/directorytree/imapengine/src/Connection/ImapConnection.php(527): DirectoryTree\ImapEngine\Connection\ImapConnection->nextReply()
#2 phpengine/vendor/directorytree/imapengine/src/Idle.php(149): DirectoryTree\ImapEngine\Connection\ImapConnection->idle(60)
#3 phpengine/vendor/directorytree/imapengine/src/Idle.php(58): DirectoryTree\ImapEngine\Idle->idle()
#4 phpengine/vendor/directorytree/imapengine/src/Idle.php(43): DirectoryTree\ImapEngine\Idle->listen(Object(Closure), Object(Carbon\Carbon))
#5 phpengine/vendor/directorytree/imapengine/src/Folder.php(105): DirectoryTree\ImapEngine\Idle->await(Object(Closure))
#6 phpengine/listener.php(181): DirectoryTree\ImapEngine\Folder->idle(Object(Closure), Object(Closure), 60)
#7 {main}*****account TWO**********10:58:37

2025-02-13 10:58:38: >> DONE
2025-02-13 10:58:38: << TAG4 OK Completed
2025-02-13 10:58:38: >> TAG5 LOGOUT
```







_________________________ another one


```bash

Removing : 4465732
Removing : 44657312025-02-13 11:03:37: << * 2 RECENT
2025-02-13 11:03:38: >> DONE
2025-02-13 11:03:38: << TAG4 OK Completed
2025-02-13 11:03:38: >> TAG5 LOGOUT


************CATCH Throwable DirectoryTree\ImapEngine\Exceptions\ImapParserException: Empty response in phpengine/vendor/directorytree/imapengine/src/Connection/ImapParser.php:54
Stack trace:
#0 phpengine/vendor/directorytree/imapengine/src/Connection/ImapConnection.php(720): DirectoryTree\ImapEngine\Connection\ImapParser->next()
#1 phpengine/vendor/directorytree/imapengine/src/Connection/ImapConnection.php(527): DirectoryTree\ImapEngine\Connection\ImapConnection->nextReply()
#2 phpengine/vendor/directorytree/imapengine/src/Idle.php(149): DirectoryTree\ImapEngine\Connection\ImapConnection->idle(60)
#3 phpengine/vendor/directorytree/imapengine/src/Idle.php(58): DirectoryTree\ImapEngine\Idle->idle()
#4 phpengine/vendor/directorytree/imapengine/src/Idle.php(43): DirectoryTree\ImapEngine\Idle->listen(Object(Closure), Object(Carbon\Carbon))
#5 phpengine/vendor/directorytree/imapengine/src/Folder.php(105): DirectoryTree\ImapEngine\Idle->await(Object(Closure))
#6 phpengine/listener.php(181): DirectoryTree\ImapEngine\Folder->idle(Object(Closure), Object(Closure), 60)
#7 {main}******account ONE**********11:03:38

2025-02-13 11:03:42: >> DONE
2025-02-13 11:03:42: << TAG4 OK Completed
2025-02-13 11:03:42: >> TAG5 LOGOUT


************CATCH Throwable DirectoryTree\ImapEngine\Exceptions\ImapParserException: Empty response in phpengine/vendor/directorytree/imapengine/src/Connection/ImapParser.php:54
Stack trace:
#0 phpengine/vendor/directorytree/imapengine/src/Connection/ImapConnection.php(720): DirectoryTree\ImapEngine\Connection\ImapParser->next()
#1 phpengine/vendor/directorytree/imapengine/src/Connection/ImapConnection.php(527): DirectoryTree\ImapEngine\Connection\ImapConnection->nextReply()
#2 phpengine/vendor/directorytree/imapengine/src/Idle.php(149): DirectoryTree\ImapEngine\Connection\ImapConnection->idle(60)
#3 phpengine/vendor/directorytree/imapengine/src/Idle.php(58): DirectoryTree\ImapEngine\Idle->idle()
#4 phpengine/vendor/directorytree/imapengine/src/Idle.php(43): DirectoryTree\ImapEngine\Idle->listen(Object(Closure), Object(Carbon\Carbon))
#5 phpengine/vendor/directorytree/imapengine/src/Folder.php(105): DirectoryTree\ImapEngine\Idle->await(Object(Closure))
#6 phpengine/listener.php(181): DirectoryTree\ImapEngine\Folder->idle(Object(Closure), Object(Closure), 60)
#7 {main}******ACCOUNT TWO**********11:03:42

2025-02-13 11:03:48: << * 234 FETCH (FLAGS (\Recent \Seen))
2025-02-13 11:03:48: << * 234 FETCH (FLAGS (\Recent \Deleted \Seen))
2025-02-13 11:03:48: << * 234 EXPUNGE
2025-02-13 11:03:48: << * 233 EXISTS
2025-02-13 11:03:48: >> TAG54 SELECT "INBOX"
2025-02-13 11:03:48: << * 234 FETCH (FLAGS (\Seen))
2025-02-13 11:03:48: << * 234 FETCH (FLAGS (\Deleted \Seen))
2025-02-13 11:03:48: << * FLAGS (\Answered \Flagged \Draft \Deleted \Seen $Junk $Forwarded)
```


Some more context of the catches…

These always happen with I get TAG4 and then 5

Seem to happen when the messages are received between a few seconds from each other… these are different accounts but the same server.

I am running the library in forked processes from the same parent php code with pcntl… so there shall be no sharing from my side.
I think I sent you the high level code of how I am doing it.

Perhaps this can help the troubleshooting and fixing. Perhaps I need to run these differently and differentiate some more variables inside the fork?

Thanks.

```bash
2025-02-13 13:44:47: >> DONE
2025-02-13 13:44:47: << TAG4 OK Completed
2025-02-13 13:44:47: >> TAG5 LOGOUT


************CATCH Throwable DirectoryTree\ImapEngine\Exceptions\ImapParserException: Empty response in /phpengine/vendor/directorytree/imapengine/src/Connection/ImapParser.php:54
Stack trace:
#0 /phpengine/vendor/directorytree/imapengine/src/Connection/ImapConnection.php(720): DirectoryTree\ImapEngine\Connection\ImapParser->next()
#1 /phpengine/vendor/directorytree/imapengine/src/Connection/ImapConnection.php(527): DirectoryTree\ImapEngine\Connection\ImapConnection->nextReply()
#2 /phpengine/vendor/directorytree/imapengine/src/Idle.php(149): DirectoryTree\ImapEngine\Connection\ImapConnection->idle(60)
#3 /phpengine/vendor/directorytree/imapengine/src/Idle.php(58): DirectoryTree\ImapEngine\Idle->idle()
#4 /phpengine/vendor/directorytree/imapengine/src/Idle.php(43): DirectoryTree\ImapEngine\Idle->listen(Object(Closure), Object(Carbon\Carbon))
#5 /phpengine/vendor/directorytree/imapengine/src/Folder.php(105): DirectoryTree\ImapEngine\Idle->await(Object(Closure))
#6 /phpengine/listener.php(181): DirectoryTree\ImapEngine\Folder->idle(Object(Closure), Object(Closure), 60)
#7 {main}******ACCOUNT 1**********13:44:47

2025-02-13 13:44:55: >> DONE
2025-02-13 13:44:55: << TAG4 OK Completed
2025-02-13 13:44:55: >> TAG5 LOGOUT


************CATCH Throwable DirectoryTree\ImapEngine\Exceptions\ImapParserException: Empty response in /phpengine/vendor/directorytree/imapengine/src/Connection/ImapParser.php:54
Stack trace:
#0 /phpengine/vendor/directorytree/imapengine/src/Connection/ImapConnection.php(720): DirectoryTree\ImapEngine\Connection\ImapParser->next()
#1 /phpengine/vendor/directorytree/imapengine/src/Connection/ImapConnection.php(527): DirectoryTree\ImapEngine\Connection\ImapConnection->nextReply()
#2 /phpengine/vendor/directorytree/imapengine/src/Idle.php(149): DirectoryTree\ImapEngine\Connection\ImapConnection->idle(60)
#3 /phpengine/vendor/directorytree/imapengine/src/Idle.php(58): DirectoryTree\ImapEngine\Idle->idle()
#4 /phpengine/vendor/directorytree/imapengine/src/Idle.php(43): DirectoryTree\ImapEngine\Idle->listen(Object(Closure), Object(Carbon\Carbon))
#5 /phpengine/vendor/directorytree/imapengine/src/Folder.php(105): DirectoryTree\ImapEngine\Idle->await(Object(Closure))
#6 /phpengine/listener.php(181): DirectoryTree\ImapEngine\Folder->idle(Object(Closure), Object(Closure), 60)
#7 {main}******ACCOUNT TWO**********13:44:55
```
