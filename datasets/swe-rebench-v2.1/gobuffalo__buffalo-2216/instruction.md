Flash messages cleared when using context.Redirect() and context.Render()
### Steps to Reproduce the Problem

This is the code used to reproduce the issue:
```
	// If there are no errors set a success message
	c.Flash().Add("danger", T.Translate(c, "success!"))
	// and redirect to the list page
	return c.Redirect(http.StatusSeeOther, "/products")
```

### Expected Behavior

The above flash message should appear on the page that the user is redirected to.

### Actual Behavior

The flash message does not appear on the page [HIDDEN]

### Info

<details>

```
-> Go: Checking installation
✓ The `go` executable was found on your system at: C:\Users\tom\sdk\go1.17.5\bin\go.exe

-> Go: Checking minimum version requirements
✓ Your version of Go, 1.17.3, meets the minimum requirements.

-> Go: Checking Package Management
✓ You are using Go Modules (`go`) for package management.

-> Go: Checking PATH
✓ Your PATH contains C:\Users\tom\go/bin.

-> Node: Checking installation
✓ The `node` executable was found on your system at: C:\Program Files\nodejs\node.exe

-> Node: Checking minimum version requirements
✓ Your version of Node, v12.22.9, meets the minimum requirements.

-> NPM: Checking installation
✓ The `npm` executable was found on your system at: C:\Program Files\nodejs\npm.cmd

-> NPM: Checking minimum version requirements
✓ Your version of NPM, 6.14.15, meets the minimum requirements.

-> Yarn: Checking installation
✓ The `yarnpkg` executable was found on your system at: C:\Users\tom\AppData\Roaming\npm\yarnpkg.cmd

-> Yarn: Checking minimum version requirements
✓ Your version of Yarn, 1.22.17, meets the minimum requirements.

-> PostgreSQL: Checking installation
✘ The `postgres` executable could not be found on your system.
For help setting up your Postgres environment please follow the instructions for you platform at:

https://www.postgresql.org/download/

-> MySQL: Checking installation
✘ The `mysql` executable could not be found on your system.
For help setting up your MySQL environment please follow the instructions for you platform at:

https://www.mysql.com/downloads/

-> SQLite3: Checking installation
✓ The `sqlite3` executable was found on your system at: C:\ProgramData\chocolatey\bin\sqlite3.exe

-> SQLite3: Checking minimum version requirements
✓ Your version of SQLite3, 3.37.0, meets the minimum requirements.

-> Cockroach: Checking installation
✘ The `cockroach` executable could not be found on your system.
For help setting up your Cockroach environment please follow the instructions for you platform at:

https://www.cockroachlabs.com/docs/stable/

-> Buffalo (CLI): Checking installation
✓ The `buffalo` executable was found on your system at: C:\Users\tom\go\bin\buffalo.exe

-> Buffalo (CLI): Checking minimum version requirements
✓ Your version of Buffalo (CLI), v0.18.1, meets the minimum requirements.

-> Buffalo: Application Details
Pwd         C:\Users\tom\go\src\code.lumity.com.au\lumity\megalodon
Root        C:\Users\tom\go\src\code.lumity.com.au\lumity\megalodon
GoPath      C:\Users\tom\go
PackagePkg  megalodon
ActionsPkg  megalodon/actions
ModelsPkg   megalodon/models
GriftsPkg   megalodon/grifts
WithModules true
Name        megalodon
Bin         bin\megalodon
VCS         git
WithPop     true
WithSQLite  true
WithDep     false
WithWebpack true
WithNodeJs  true
WithYarn    true
WithDocker  true
WithGrifts  true
AsWeb       true
AsAPI       false
InApp       true
PackageJSON {map[build:webpack --mode production --progress dev:webpack --watch]}

-> Buffalo: config/buffalo-app.toml
name = "megalodon"
bin = "bin\\megalodon"
vcs = "git"
with_pop = true
with_sqlite = true
with_dep = false
with_webpack = true
with_nodejs = true
with_yarn = true
with_docker = true
with_grifts = true
as_web = true
as_api = false

-> Buffalo: config/buffalo-plugins.toml
[[plugin]]
  binary = "buffalo-auth"
  go_get = "github.com/gobuffalo/buffalo-auth"
  tags = ["sqlite"]

[[plugin]]
  binary = "buffalo-pop"
  go_get = "github.com/gobuffalo/buffalo-pop/v3@latest"
  tags = ["sqlite"]

-> Buffalo: go.mod
module megalodon

go 1.17

require (
        code.lumity.com.au/lumity/megalodon-apis v0.0.0-20220215015727-d0b6050e4095
        github.com/gobuffalo/buffalo v0.18.2
        github.com/gobuffalo/buffalo-pop/v3 v3.0.2
        github.com/gobuffalo/envy v1.10.1
        github.com/gobuffalo/mw-forcessl v0.0.0-20200131175327-94b2bd771862
        github.com/gobuffalo/mw-i18n/v2 v2.0.1
        github.com/gobuffalo/mw-paramlogger v1.0.0
        github.com/gobuffalo/pop/v6 v6.0.1
        github.com/gobuffalo/suite/v4 v4.0.2
        github.com/gobuffalo/validate/v3 v3.3.1
        github.com/gobuffalo/x v0.1.0
        github.com/gofrs/uuid v4.2.0+incompatible
        github.com/jung-kurt/gofpdf v1.16.2
        github.com/leekchan/accounting v1.0.0
        github.com/manifoldco/promptui v0.9.0
        github.com/markbates/grift v1.5.0
        github.com/pkg/errors v0.9.1
        github.com/unrolled/secure v1.10.0
        golang.org/x/crypto v0.0.0-20220214200702-86341886e292

)

require (
        github.com/gobuffalo/mw-csrf v1.0.0 // indirect
        github.com/golang-sql/civil v0.0.0-20190719163853-cb61b32ac6fe // indirect
        github.com/golang-sql/sqlexp v0.0.0-20170517235910-f1bb20e5a188 // indirect
)

require (
        github.com/BurntSushi/toml v1.0.0 // indirect
        github.com/Masterminds/semver/v3 v3.1.1 // indirect
        github.com/aymerick/douceur v0.2.0 // indirect
        github.com/chzyer/readline v0.0.0-20180603132655-2972be24d48e // indirect
        github.com/cockroachdb/apd v1.1.0 // indirect
        github.com/davecgh/go-spew v1.1.1 // indirect
        github.com/denisenkom/go-mssqldb v0.12.0
        github.com/dustin/go-humanize v1.0.0 // indirect
        github.com/fatih/color v1.13.0 // indirect
        github.com/fatih/structs v1.1.0 // indirect
        github.com/felixge/httpsnoop v1.0.2 // indirect
        github.com/fsnotify/fsnotify v1.5.1 // indirect
        github.com/go-sql-driver/mysql v1.6.0 // indirect
        github.com/gobuffalo/events v1.4.2 // indirect
        github.com/gobuffalo/fizz v1.14.0 // indirect
        github.com/gobuffalo/flect v0.2.4 // indirect
        github.com/gobuffalo/github_flavored_markdown v1.1.1 // indirect
        github.com/gobuffalo/helpers v0.6.4 // indirect
        github.com/gobuffalo/httptest v1.5.1 // indirect
        github.com/gobuffalo/logger v1.0.6 // indirect
        github.com/gobuffalo/meta v0.3.1 // indirect
        github.com/gobuffalo/nulls v0.4.1 // indirect
        github.com/gobuffalo/plush/v4 v4.1.9 // indirect
        github.com/gobuffalo/tags/v3 v3.1.2 // indirect
        github.com/google/go-querystring v1.1.0 // indirect
        github.com/gorilla/css v1.0.0 // indirect
        github.com/gorilla/handlers v1.5.1 // indirect
        github.com/gorilla/mux v1.8.0 // indirect
        github.com/gorilla/securecookie v1.1.1 // indirect
        github.com/gorilla/sessions v1.2.1 // indirect
        github.com/inconshreveable/mousetrap v1.0.0 // indirect
        github.com/jackc/chunkreader/v2 v2.0.1 // indirect
        github.com/jackc/pgconn v1.11.0 // indirect
        github.com/jackc/pgio v1.0.0 // indirect
        github.com/jackc/pgpassfile v1.0.0 // indirect
        github.com/jackc/pgproto3/v2 v2.2.0 // indirect
        github.com/jackc/pgservicefile v0.0.0-20200714003250-2b9c44734f2b // indirect
        github.com/jackc/pgtype v1.10.0 // indirect
        github.com/jackc/pgx/v4 v4.15.0 // indirect
        github.com/jmoiron/sqlx v1.3.4 // indirect
        github.com/joho/godotenv v1.4.0 // indirect
        github.com/karrick/godirwalk v1.16.1 // indirect
        github.com/kballard/go-shellquote v0.0.0-20180428030007-95032a82bc51 // indirect
        github.com/luna-duclos/instrumentedsql v1.1.3 // indirect
        github.com/markbates/oncer v1.0.0 // indirect
        github.com/markbates/refresh v1.12.0 // indirect
        github.com/markbates/safe v1.0.1 // indirect
        github.com/markbates/sigtx v1.0.0 // indirect
        github.com/mattn/go-colorable v0.1.12 // indirect
        github.com/mattn/go-isatty v0.0.14 // indirect
        github.com/mattn/go-sqlite3 v1.14.11 // indirect
        github.com/microcosm-cc/bluemonday v1.0.18 // indirect
        github.com/mitchellh/go-homedir v1.1.0 // indirect
        github.com/monoculum/formam v3.5.5+incompatible // indirect
        github.com/nicksnyder/go-i18n v1.10.1 // indirect
        github.com/pelletier/go-toml v1.9.4 // indirect
        github.com/pmezard/go-difflib v1.0.0 // indirect
        github.com/rogpeppe/go-internal v1.8.1 // indirect
        github.com/sergi/go-diff v1.2.0 // indirect
        github.com/shopspring/decimal v1.3.1 // indirect
        github.com/sirupsen/logrus v1.8.1 // indirect
        github.com/sourcegraph/annotate v0.0.0-20160123013949-f4cad6c6324d // indirect
        github.com/sourcegraph/syntaxhighlight v0.0.0-20170531221838-bd320f5d308e // indirect
        github.com/spf13/cobra v1.3.0 // indirect
        github.com/spf13/pflag v1.0.5 // indirect
        github.com/stretchr/testify v1.7.0 // indirect
        golang.org/x/net v0.0.0-20220127200216-cd36cc0744dd // indirect
        golang.org/x/sync v0.0.0-20210220032951-036812b2e83c // indirect
        golang.org/x/sys v0.0.0-20220209214540-3681064d5158 // indirect
        golang.org/x/term v0.0.0-20210927222741-03fcf44c2211 // indirect
        golang.org/x/text v0.3.7 // indirect
        gopkg.in/yaml.v2 v2.4.0 // indirect
        gopkg.in/yaml.v3 v3.0.0-20210107192922-496545a6307b // indirect
)
```

</details>
