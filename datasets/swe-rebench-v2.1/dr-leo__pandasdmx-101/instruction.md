Prune empty StructureMessage collections in to_pandas()
As raised by @dr-leo via e-mail:

> flows = ecb.dataflow()
>
> When I do 'to_pandas(flows)', the resulting DictLike has all the empty resources from the StructureMessage. I buy your Argument that at IM Level all supported resource types should be represented by an Attribute. However, I see no merit in representing absent resources by a key and empty dict.

Related to #79.
