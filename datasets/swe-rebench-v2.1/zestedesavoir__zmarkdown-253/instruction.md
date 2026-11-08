abbr ending with a period are not parsed
WIth this markdown ;

```
LLPANMP

L.L.P.A.N.M.P.


*[L.L.P.A.N.M.P.]: Les légendes pour les sigles ne marchent plus
*[LLPANMP]: Les légendes pour les sigles ne marchent plus
```
we get :

```html
<p><abbr title="Les légendes pour les sigles ne marchent plus">LLPANMP</abbr></p>
<p>L.L.P.A.N.M.P.</p>
```

but we expected:

```html
<p><abbr title="Les légendes pour les sigles ne marchent plus">LLPANMP</abbr></p>
<p><abbr title="Les légendes pour les sigles ne marchent plus">L.L.P.A.N.M.P.</abbr></p>
```
