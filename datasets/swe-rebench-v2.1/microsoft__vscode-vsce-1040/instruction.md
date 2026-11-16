Publisher required when only packaging an extension
https://github.com/microsoft/vscode-vsce/pull/1011 introduced a requirement that we should set a publisher even if we are just calling `vsce package` and have no intention to publish the artifact.
I wonder if it would be possible to reverse this behavior and allow packaging an extension without defining a publisher.
