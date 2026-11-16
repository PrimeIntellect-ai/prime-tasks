Annotation: Param/ResultTags with In/Out
Currently, fx.ParamTags and fx.ResultTags error out when they're used with fx.In and fx.Out.

It makes sense that fx.ParamTags shouldn't be used with fx.In, and fx.ResultTags with fx.Out, but there's no reason for fx.ParamTags to not be able to be used with fx.Out.

We should allow the usage of fx.ParamTags annotation with fx.Out, and similarly, fx.ResultTags with fx.In.
