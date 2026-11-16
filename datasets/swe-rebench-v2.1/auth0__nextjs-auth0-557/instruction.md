When somewhere in the returnTo Url a absolute url found -> Exeption
### Description

On our Project we have the following issue.

Our returnTo Url looks for example like this -> .../login?returnTo=/relative/return/page/with/params?someUrl=https://foo.bar

Because of the way how relative URL tested (Check of // somewhere in string) the lib says that no relative url is given

Can u get a look on this? ... I would make a PR to fix this

Thanks
