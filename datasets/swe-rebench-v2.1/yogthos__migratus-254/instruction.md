Using `:disable-transaction` and passing in a `Connection` object throws error
It seems like the simple combination of using `:disable-transaction` in a SQL migration along with passing in a raw `Connection` object is enough to throw an exception. This test code demonstrates:

```clojure
(deftest test-no-tx-migration-pass-conn
  (with-open [conn (jdbc/get-connection (:db config))]
    (let [test-config (assoc config
                             :migration-dir "migrations-no-tx"
                             :db {:connection conn})]
      (is (not (test-sql/verify-table-exists? test-config "foo")))
      (core/migrate test-config)
      (is (test-sql/verify-table-exists? test-config "foo"))
      (core/down test-config 20111202110600)
      (is (not (test-sql/verify-table-exists? test-config "foo"))))))
```

Error:

```clojure
#error {
 :cause "Unknown dbtype: , and :classname not provided."
 :data {:connection #object[org.h2.jdbc.JdbcConnection 0x4418e0a5 "conn214: url=jdbc:h2:./site.db user="]}
 :via
 [{:type clojure.lang.ExceptionInfo
   :message "Unknown dbtype: , and :classname not provided."
   :data {:connection #object[org.h2.jdbc.JdbcConnection 0x4418e0a5 "conn214: url=jdbc:h2:./site.db user="]}
   :at [next.jdbc.connection$spec__GT_url_PLUS_etc invokeStatic "connection.clj" 215]}]
 :trace
 [[next.jdbc.connection$spec__GT_url_PLUS_etc invokeStatic "connection.clj" 215]
  [next.jdbc.connection$spec__GT_url_PLUS_etc invoke "connection.clj" 155]
  [next.jdbc.connection$eval13419$fn__13420 invoke "connection.clj" 415]
  [next.jdbc.protocols$eval13151$fn__13152$G__13142__13157 invoke "protocols.clj" 14]
  [next.jdbc.connection$eval13441$fn__13442 invoke "connection.clj" 431]
  [next.jdbc.protocols$eval13181$fn__13182$G__13172__13189 invoke "protocols.clj" 24]
  [next.jdbc$get_connection invokeStatic "jdbc.clj" 167]
  [next.jdbc
$get_connection invoke "jdbc.clj" 146]
  [migratus.migration.sql$do_commands invokeStatic "src/migratus/migration/sql.clj" 72]
  [migratus.migration.sql$do_commands invoke "src/migratus/migration/sql.clj" 60]
  [migratus.migration.sql$execute_command$fn__20291 invoke "src/migratus/migration/sql.clj" 79]
  [migratus.migration.sql$execute_command invokeStatic "src/migratus/migration/sql.clj" 78]
  [migratus.migration.sql$execute_command invoke "src/migratus/migration/sql.clj" 75]
  [migratus.migration.sql$run_sql_STAR_ invokeStatic "src/migratus/migration/sql.clj" 96]
  [migratus.migration.sql$run_sql_STAR_ invoke "src/migratus/migration/sql.clj" 92]
  [migratus.migration.sql$run_sql invokeStatic "src/migratus/migration/sql.clj" 104]
  [migratus.migration.sql$run_sql invoke "src/migratus/migration/sql.clj" 98]
  [migratus.migration.sql.SqlMigration up "src/migratus/migration/sql.clj" 118]
  [migratus.database$migrate_up_STAR_ invokeStatic "form-init14526484179824197735.clj" 77]
  [migratus.database$migrate_up_S
TAR_ invoke "form-init14526484179824197735.clj" 70]
  [migratus.database.Database migrate_up "database.clj" 311]
  [migratus.core$up_STAR_ invokeStatic "core.clj" 103]
  [migratus.core$up_STAR_ invoke "core.clj" 101]
  [migratus.core$migrate_up_STAR_ invokeStatic "core.clj" 114]
  [migratus.core$migrate_up_STAR_ invoke "core.clj" 105]
  [migratus.core$migrate_STAR_ invokeStatic "core.clj" 127]
  [migratus.core$migrate_STAR_ invoke "core.clj" 123]
  [clojure.core$partial$fn__5839 invoke "core.clj" 2625]
  [migratus.core$run invokeStatic "core.clj" 54]
  [migratus.core$run invoke "core.clj" 50]
  [migratus.core$migrate invokeStatic "core.clj" 134]
  [migratus.core$migrate invoke "core.clj" 129]
  [migratus.test.database$fn__20397 invokeStatic "form-init14526484179824197735.clj" 410]
  [migratus.test.database$fn__20397 invoke "form-init14526484179824197735.clj" 403]
  [cider.nrepl.middleware.test$test_var$fn__17297 invoke "test.clj" 304]
  [cider.nrepl.middleware.test$test_var invokeStatic "test.clj" 303]
  [cid
er.nrepl.middleware.test$test_var invoke "test.clj" 293]
  [cider.nrepl.middleware.test$test_vars$fn__17308$fn__17309$fn__17311 invoke "test.clj" 336]
  [migratus.test.migration.sql$setup_test_db invokeStatic "sql.clj" 37]
  [migratus.test.migration.sql$setup_test_db invoke "sql.clj" 35]
  [clojure.test$compose_fixtures$fn__9731$fn__9732 invoke "test.clj" 694]
  [clojure.test$default_fixture invokeStatic "test.clj" 687]
  [clojure.test$default_fixture invoke "test.clj" 683]
  [clojure.test$compose_fixtures$fn__9731 invoke "test.clj" 694]
  [cider.nrepl.middleware.test$test_vars$fn__17308$fn__17309 invoke "test.clj" 335]
  [clojure.lang.PersistentVector reduce "PersistentVector.java" 343]
  [clojure.core$reduce invokeStatic "core.clj" 6827]
  [clojure.core$reduce invoke "core.clj" 6810]
  [cider.nrepl.middleware.test$test_vars$fn__17308 invoke "test.clj" 334]
  [clojure.test$default_fixture invokeStatic "test.clj" 687]
  [clojure.test$default_fixture invoke "test.clj" 683]
  [cider.nrepl.middleware.test$test_v
ars invokeStatic "test.clj" 332]
  [cider.nrepl.middleware.test$test_vars invoke "test.clj" 322]
  [cider.nrepl.middleware.test$test_ns invokeStatic "test.clj" 362]
  [cider.nrepl.middleware.test$test_ns invoke "test.clj" 348]
  [cider.nrepl.middleware.test$test_var_query$fn__17323 invoke "test.clj" 381]
  [clojure.core.protocols$iter_reduce invokeStatic "protocols.clj" 49]
  [clojure.core.protocols$fn__8140 invokeStatic "protocols.clj" 75]
  [clojure.core.protocols$fn__8140 invoke "protocols.clj" 75]
  [clojure.core.protocols$fn__8088$G__8083__8101 invoke "protocols.clj" 13]
  [clojure.core$reduce invokeStatic "core.clj" 6828]
  [clojure.core$reduce invoke "core.clj" 6810]
  [cider.nrepl.middleware.test$test_var_query invokeStatic "test.clj" 380]
  [cider.nrepl.middleware.test$test_var_query invoke "test.clj" 368]
  [cider.nrepl.middleware.test$handle_test_var_query_op$fn__17355$fn__17356 invoke "test.clj" 439]
  [clojure.lang.AFn applyToHelper "AFn.java" 152]
  [clojure.lang.AFn applyTo "AFn.java" 144]
  [c
lojure.core$apply invokeStatic "core.clj" 665]
  [clojure.core$with_bindings_STAR_ invokeStatic "core.clj" 1973]
  [clojure.core$with_bindings_STAR_ doInvoke "core.clj" 1973]
  [clojure.lang.RestFn invoke "RestFn.java" 425]
  [cider.nrepl.middleware.test$handle_test_var_query_op$fn__17355 invoke "test.clj" 427]
  [clojure.lang.AFn run "AFn.java" 22]
  [nrepl.middleware.session$session_exec$main_loop__1350$fn__1354 invoke "session.clj" 218]
  [nrepl.middleware.session$session_exec$main_loop__1350 invoke "session.clj" 217]
  [clojure.lang.AFn run "AFn.java" 22]
  [java.lang.Thread run "Thread.java" 832]]}
```

I tried digging in to fix it, but I'm not really sure where things are going wrong.
