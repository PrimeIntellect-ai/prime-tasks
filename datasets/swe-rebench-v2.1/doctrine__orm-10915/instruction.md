2.16.0 - Issue with persisting entities
<!--
Before reporting a BC break, please consult the upgrading document to make sure it's not an expected change: https://github.com/doctrine/orm/blob/2.9.x/UPGRADE.md
-->

### BC Break Report

<!-- Fill in the relevant information below to help triage your issue. -->

|    Q        |   A
|------------ | ------
| BC Break    | yes
| Version     | 2.16.0

#### Summary

I have a case in our test suite where entities are not persisted properly anymore. This worked fine on 2.15.

The insert statement does not bind any parameters and fails:

```
PDOException: SQLSTATE[42000]: Syntax error or access violation: 1064 You have an error in your SQL syntax; check the manual that corresponds to your MySQL server version for the right syntax to use near '?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)' at line 1

/var/www/app/symfony/vendor/doctrine/dbal/src/Driver/PDO/Statement.php:121
/var/www/app/symfony/vendor/doctrine/dbal/src/Driver/Middleware/AbstractStatementMiddleware.php:69
/var/www/app/symfony/vendor/doctrine/dbal/src/Logging/Statement.php:98
/var/www/app/symfony/vendor/doctrine/dbal/src/Driver/Middleware/AbstractStatementMiddleware.php:69
/var/www/app/symfony/vendor/symfony/doctrine-bridge/Middleware/Debug/Statement.php:68
/var/www/app/symfony/vendor/doctrine/dbal/src/Statement.php:190
/var/www/app/symfony/vendor/doctrine/dbal/src/Statement.php:249
/var/www/app/symfony/vendor/doctrine/orm/lib/Doctrine/ORM/Persisters/Entity/BasicEntityPersister.php:280
/var/www/app/symfony/vendor/doctrine/orm/lib/Doctrine/ORM/UnitOfWork.php:1177
/var/www/app/symfony/vendor/doctrine/orm/lib/Doctrine/ORM/UnitOfWork.php:442
/var/www/app/symfony/vendor/doctrine/orm/lib/Doctrine/ORM/EntityManager.php:403
```

The logs (see `parameters: []`):

```
10:11:57 DEBUG     [doctrine] Executing statement: INSERT INTO widget_settings (hash, enabled, language, orientation, position, widget_content, tooltip_content, header_color, detail_urls, left_title, use_left_title, right_title, use_right_title, logo, use_logo, is_primary, booking_btn_color, widget_name, booking_urls, review_config_id, account_id, parent_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) (parameters: [], types: [])
```

#### How to reproduce

I cannot provide a small reproducer yet. I had a look and somehow inside the `BasicEntityPersister` the call to `prepareInsertData($entity)` with that entity returns an empty array.

The setup part of the test code that triggers the error looks like this:

```php
        $account = $this->fixtures->createAccount();
        $this->em->persist($account);
        $this->em->persist($this->fixtures->createWidgetSettings($account, false));
        $this->em->persist($this->fixtures->createWidgetSettings($account, false));

        $this->em->flush();
```

The issue seems to come from the second `$this->em->persist($this->fixtures->createWidgetSettings($account, false));` line :thinking:

@mpdude does this information help at all to pinpoint the issue? I can try to provide a small reproducer

### Additional contract requirements

The failure described above is triggered when a `postPersist` event listener calls
`EntityManager::flush()` while other new entities are still pending insertion. In that
situation the outer flush must still persist every entity exactly once: it must not
execute an `INSERT` statement with unbound parameters, and it must not leave spurious
rows behind in the database.

`postPersist` must be dispatched only after all new entities have been inserted and
their generated identifiers have been assigned. A `postPersist` listener must therefore
be able to observe the generated identifier of every entity inserted by the same flush.
