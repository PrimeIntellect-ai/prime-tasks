Calling flush multiple times before committing causes additional audit-logs
I have an entity which should get audited and if I call flush more than once before calling commit, the audit-events will get logged with each subsequent commit again. In this example I end up with 11 identical insert audits:

```
        $this->orm->beginTransaction();
        $e = new Enity();
        $this->orm->persist($e);
        $this->orm->flush();
        $this->orm->flush();
        $this->orm->commit(); // Logs the insert once.

        // Logs an additional 10 inserts for the entity added above:
        for ($n=1;$n<=10;$n++) {
            $this->orm->beginTransaction();
            $this->orm->commit();
        }
```

I believe the issue is caused by `DoctrineSubscriber::onFlush`, which simply copies the current SQL-Logger to a class-variable and then tries to restore that value on commit, while not checking if the Audit-Logger is already installed.
