error when template contains Iteration of list
Error existe in lastest version moto 4.0.8

Having this template :
`{{#each items}} <a href="{{itemName}}">{{itemDesc}}</a> {{/each}}`

And our input :

`{"items": [{"itemName": "item1", "itemDesc": "description 1"}]}`

Moto will not find out "items" from input because moto search for "#each items".

[HIDDEN]

[HIDDEN]

In addition, moto can not find itemName and itemDesc from a lower level dict inside a list.
