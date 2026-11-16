Error: Error: getTranslatorId: "csljson" is not a GUID
Hi there,

I don't even know if this project is still active so let me know if you want me to make a pull request for this.

Currently the default translator for a ".json" file is specified as csljson. This probably didn't work for a while, since it isn't in the list of translators used by better bibtex:
https://github.com/retorquere/zotero-better-bibtex/blob/609aa6fb0a392257bf2f8438902d46e27b6ad4e5/content/translators.ts#L109
(it probably "still worked" since the default must've been json)

However a commit from lastweek started making errors about this: https://github.com/retorquere/zotero-better-bibtex/commit/795b243619bf16aeb1e5f9bf768cc221d83cc2eb .

A workaround for the issue is just to use "filename.lksajfd", but I don't really know why this works.

Have a nice day !
