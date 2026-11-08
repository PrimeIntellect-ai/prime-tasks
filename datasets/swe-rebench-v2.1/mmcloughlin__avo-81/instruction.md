pass: remove redundant jump to immediately following label
Simple cleanup pass to remove `JMP label \n label:\n`.

Discussed in #performance on Gophers Slack

https://gophers.slack.com/archives/C0VP8EF3R/p1554774092011200
https://gophers.slack.com/archives/C0VP8EF3R/p1554785110023800

Example:

https://github.com/dgryski/go-chaskey/commit/ba454392bc5ab6daae103e15147185f8f4a27dcc#diff-5c275d0467fb567c78cf8a144f8b301bL89
