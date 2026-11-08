[Feature request] classnames order, group by responsive variant
Right now the ordering in applied in this order:

1. Affected property (e.g. `flex`, `padding`...)
2. Responsive variant (e.g. `sm:`, `md:`, `lg:`...)
3. Theme variant (e.g. `dark:`...)
4. State variant (e.g. `hover:`, `disabled:`...)

e.g. `<div class="p-4 sm:p-6 lg:p-8 rounded sm:rounded-lg lg:rounded-2xl">...</div>`

While I like this approach, some user might prefer grouping by responsive variant first like so:

1. Responsive variant (e.g. `sm:`, `md:`, `lg:`...)
2. Affected property (e.g. `flex`, `padding`...)
3. Theme variant (e.g. `dark:`...)
4. State variant (e.g. `hover:`, `disabled:`...)

e.g. `<div class="p-4 rounded sm:p-6 sm:rounded-lg lg:p-8 lg:rounded-2xl">...</div>`

Both looks fine to me, I would add an optional parameter `groupByResponsive` set to `false` in order to keep using current order rules by default.

What do you think about this feature ?
