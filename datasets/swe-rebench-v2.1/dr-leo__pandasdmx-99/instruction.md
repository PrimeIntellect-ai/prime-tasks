Check tab-completion of Request convenience methods
As raised by @dr-leo via e-mail:
> In [9]: flows=ecb.dataflow()
> In [10]: flows
> Out[10]: <StructureMessage header=<Header error=None id='IDREF291392' prepared='
2019-07-21T16:00:17' receiver='no… footer=None response=<Response [200]> categor
y_scheme=DictLike() codelist=DictLike() concept_scheme=DictLike() constraint=Dic
tLike() dataflow=DictLike([('AME', <DataflowDefinition: 'AME'='AMECO'>), ('BKN',
 <DataflowDefini… structure=DictLike() organisation_scheme=DictLike() provisiona
greement=DictLike
>
> ---
> tab completion does not work on my box when I issue: 'ecb.datafl...'. Might be unrelated to your code. Should doublecheck with v0.9.

In 0.9, additional methods were added to Request using a helper class and method:
https://github.com/dr-leo/pandaSDMX/blob/16950d60fd7be933543cff2c26e8a11e1fd7433e/pandasdmx/api.py#L87-L93

In 1.0, these are handed by `__getattr__` and the `Resource` enum, which has the full list of members.
https://github.com/dr-leo/pandaSDMX/blob/28f6be45733e5cb7549c4c6dae215a28b6a0e676/pandasdmx/api.py#L67-L69

[HIDDEN]
