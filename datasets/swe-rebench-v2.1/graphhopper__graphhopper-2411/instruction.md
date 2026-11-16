If heading is provided change EdgeFilter for LocationIndexTree
The issue can be reproduced with oneway streets like [this](https://graphhopper.com/maps/?point=51.211414%2C14.566305&point=51.211521%2C14.561906&ch.disable=true&heading=270), ie. the heading does not work. Expected is the snapping to the other side of the motorway but it is unclear if the heading should already be applied at the snapping step. (The ordinary case works like [here](https://graphhopper.com/maps/?point=51.192725%2C14.56094&point=51.192819%2C14.567678&ch.disable=true&heading=270))

### Additional contract requirements

A request with one heading may contain multiple points. The heading constrains the first point; later points without corresponding headings are routed without a heading constraint.
