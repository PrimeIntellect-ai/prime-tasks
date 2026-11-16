Error while using multiple data tables in single spec
I am reporting this as bug, as suggested by shrikant. See https://groups.google.com/forum/m/#!topic/getgauge/dXYqv6e_ZvA

Hello,
I am trying to run simple specification Gauge and Taiko, but getting error

organisation.spec:9 Multiple data table present, ignoring table

------------- SPEC File (Organisation.spec)  ----------------
# Organisationsverwaltung

table: logindata.csv

* Als Benutzer <users> mit Passwort <pwd> anmelden

## Organisation auswählen

table: orgdata.csv

* Gehe zu Partnerdaten
* Suche Organisation mit Organisationanummer <Organisationanummer>
* Eine Organisation mit Name <Organisationsname> wird angezeigt
----------------------------------------------------------------

Gauge version: 1.1.1
Commit Hash: 6e0d83f

Plugins
-------
html-report (4.0.12)
java (0.7.9)
js (2.3.12)
screenshot (0.0.1)
spectacle (0.1.4)

---------------------------------------------

Can someone help me on this or any workaround ?

Thanks
Sanjay

### Additional contract requirements

- When `env.AllowScenarioDatatable` is enabled, a scenario-level external data table must be accepted for its scenario even when the same specification has a specification-level data table; it must not be rejected as a duplicate.
- When `env.AllowScenarioDatatable` is disabled, scenario-level external data tables remain disallowed.
