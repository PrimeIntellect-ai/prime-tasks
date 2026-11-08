relative_path option includes all folders using full path
Using 7.5.2 of spatie/laravel-backup, with a vanilla Laravel 8 install.

Only thing I've changed in the backup.php config:
```
'relative_path' => base_path()
```
It does backup all the files using a [relative path](https://github.com/spatie/laravel-backup/pull/1158).
But: it also creates all the folders (without the files) with full path: /Users/path_to_source_code

E.g. when I `unzip 2021-04-26-14-45-37.zip`:
```
# files have been extracted, but also shows "Users" folder
ls -1
2021-04-26-14-45-37.zip	artisan			config			phpunit.xml		server.php
README.md		bootstrap		database		public			storage
Users			composer.json		db-dumps		resources		tests
app			composer.lock		package.json		routes			webpack.mix.js

# the "config" folder shows the expected files
$ ls config
app.php			broadcasting.php	database.php		logging.php		services.php
auth.php		cache.php		filesystems.php		mail.php		session.php
backup.php		cors.php		hashing.php		queue.php		view.php

# but under "Users" folder there also is a config folder
$ ls Users/path_to_source_code/
app		config		public		routes		tests
bootstrap	database	resources	storage

# but this folder is empty
$ ls Users/path_to_source_code/config
```

I extract using default unzip on MacOs (also tried p7zip).

### Additional contract requirements

- When `relative_path` is set to a source directory, ZIP member names must be relative to that directory and must not include its absolute path or ancestor directories. Included files and directories retain their paths beneath that directory, and excluded paths do not appear in the archive.
