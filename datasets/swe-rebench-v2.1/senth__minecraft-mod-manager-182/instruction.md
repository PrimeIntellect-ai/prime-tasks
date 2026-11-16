Skip downloading already up to date files on update
Maybe I'm looking at this wrong, but it seems like when the "update" command is used, the latest version of installed mods are downloaded and replace the current installed versions regardless if the currently installed version is up to date already.

On my end this makes for the 'update' command to take a long time (about an extra 1.5 seconds per mod). This seems unnecessary. Is there a faster way this could be implemented to avoid downloading the whole mod every time (maybe comparing metadata from curse/modrinth is faster?)

### Additional contract requirements

When updating an installed mod, if the latest available version has the same upload time as the installed version, the update must leave the installed file in place and must not download or replace it. A genuinely newer available version must still be downloaded and installed.
