flag-parameter rule wrongly detects var definition and points to the function signature
**Describe the bug**
A clear and concise description of what the bug is.

My fucntion isn't receiving any "err" nor "value" parameters.
![Image](https://github.com/user-attachments/assets/7b9f2c2a-4819-4b90-907e-029744f6f3df)

**To Reproduce**

```
❯ go version
go version go1.23.5 windows/amd64
❯ revive -version
version 1.6.0
```

**Code:**

Notice how ConnectPG2 does show the error, but ConnectPG3 doesn't.

```go
package pgdb

import (
	"context"
	"fmt"
	"log"
	"log/slog"
	"time"

	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

func ConnectPG2(ctx context.Context, logLogger *log.Logger, dsn string, coloredLogs bool, logLevel logger.LogLevel) (*gorm.DB, error) {
	lg := logger.New(
		logLogger,
		logger.Config{
			SlowThreshold:             time.Second,
			LogLevel:                  logLevel,
			IgnoreRecordNotFoundError: true,
			ParameterizedQueries:      false,
			Colorful:                  coloredLogs,
		},
	)
	var db *gorm.DB
	var err error
	i := 2
	for { // infinite attempts with timeout for intermediate logs
		ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
		db, err = connectPgWithContext(ctx, dsn, &gorm.Config{Logger: lg})
		cancel()
		if err == nil {
			break
		}
		slog.Error(err.Error())
		slog.Debug("trying again", "attempt", i)
		i++
		time.Sleep(2 * time.Second)
	}

	// test db connection
	value := false
	err = db.WithContext(ctx).Raw("SELECT 1 = 1").First(&value).Error
	if err != nil {
		err = fmt.Errorf("ConnectPG: connection test failed: %w", err)
		return nil, err
	}
	if !value {
		err = fmt.Errorf("ConnectPG: logic issue with postgres found")
		return nil, err
	}

	return db, nil
}

func ConnectPG3(ctx context.Context, dsn string) (*gorm.DB, error) {
	var db *gorm.DB
	var err error
	i := 2
	for { // infinite attempts with timeout for intermediate logs
		ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
		db, err = connectPgWithContext(ctx, dsn, &gorm.Config{})
		cancel()
		if err == nil {
			break
		}
		slog.Error(err.Error())
		slog.Debug("trying again", "attempt", i)
		i++
		time.Sleep(2 * time.Second)
	}

	// test db connection
	value := false
	err = db.WithContext(ctx).Raw("SELECT 1 = 1").First(&value).Error
	if err != nil {
		err = fmt.Errorf("ConnectPG: connection test failed: %w", err)
		return nil, err
	}
	if !value {
		err = fmt.Errorf("ConnectPG: logic issue with postgres found")
		return nil, err
	}

	return db, nil
}
```



```shell
# flags

revive -config revive.toml -formatter friendly ./...
```

```toml
# When set to false, ignores files with "GENERATED" header, similar to golint
ignoreGeneratedHeader = true
# severity = "warning"
confidence = 0.8
errorCode = 2
warningCode = 1

# exclude = [
#     "assets",
#     "build",
#     "config",
#     "dist",
#     "docs",
#     "excelmaker",
#     "public",
#     "sql",
#     "templates",
#     "tmp",
# ]

[rule.blank-imports]
[rule.comment-spacings]
severity = "error"
[rule.constant-logical-expr]
[rule.context-as-argument]
# [rule.context-keys-type] # disabled due to bad performance
[rule.datarace]
[rule.defer]
severity = "error"
[rule.dot-imports]
severity = "error"
[rule.duplicated-imports]
[rule.empty-block]
[rule.error-naming]
severity = "error"
[rule.error-return]
severity = "error"
[rule.error-strings]
# [rule.errorf] # disabled due to bad performance
# [rule.exported]
# Disabled = true
[rule.flag-parameter]
# severity = "error"
[rule.import-shadowing]
severity = "error"
[rule.increment-decrement]
[rule.indent-error-flow]
# # [rule.package-comments]
# # Disabled = true
[rule.modifies-parameter]
severity = "error"
[rule.nested-structs]
[rule.range]
severity = "error"
[rule.receiver-naming]
severity = "error"
[rule.redefines-builtin-id]
severity = "error"
[rule.redundant-import-alias]
# [rule.string-of-int] # disabled due to bad performance
[rule.struct-tag]
[rule.superfluous-else]
# [rule.time-equal] # disabled due to bad performance
# [rule.time-naming] # disabled due to bad performance
[rule.unexported-naming]
# [rule.unexported-return] # disabled due to bad performance
[rule.unreachable-code]
[rule.unused-parameter]
[rule.use-any]
severity = "error"
[rule.useless-break]
# [rule.var-declaration] # disabled due to bad performance
[rule.var-naming]
severity = "error"
```

**Expected behavior**

This warning doesn't shows.

**Logs**

```
❯ revive -config revive.toml -formatter friendly ./...
  ⚠  https://github.com/mgechev/revive/blob/master/RULES_DESCRIPTIONS.md#flag-parameter  parameter 'err' seems to be a control flag, avoid control coupling
  src\services\pgdb\test.go:14:16

  ⚠  https://github.com/mgechev/revive/blob/master/RULES_DESCRIPTIONS.md#flag-parameter  parameter 'err' seems to be a control flag, avoid control coupling
  src\services\pgdb\test.go:14:16

  ⚠  https://github.com/mgechev/revive/blob/master/RULES_DESCRIPTIONS.md#flag-parameter  parameter 'value' seems to be a control flag, avoid control coupling
  src\services\pgdb\test.go:14:16

⚠ 3 problems (0 errors, 3 warnings)

Warnings:
  3  flag-parameter

```




**Desktop (please complete the following information):**
 - OS: windows 11 pro, 24H2
 - Version of Go: 1.23.5

**Additional context**
idk.
