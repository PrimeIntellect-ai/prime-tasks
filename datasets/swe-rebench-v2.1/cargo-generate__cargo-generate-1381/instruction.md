Feature request: Add feature to see if file exists in destination directory
I'd like to be able to use cargo generate's `--init` feature to configure a pre-existing project to use my crate. My crate requires a build script and config.toml to operate.

I want to be able to write these files to the destination if they don't yet exist, but if the user already has one or both of these files I don't want to overwrite them as this would destroy the user's configuration for their project.

At present I have to either use system commands or ask the user whether the files exist, otherwise cargo generate simply errors when trying to copy the file. We already have a way to check whether a file exists in the template folder, so it seems reasonable to also be able to check the destination folder too.
