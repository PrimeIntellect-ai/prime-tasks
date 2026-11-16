ids should be available from envisage.api
id constants that are needed externally to Envisage (for example, ids for extension points like the `SERVICE_OFFERS` id, or ids for actual services) are currently available in `envisage.ids`. I think they should be made available in `envisage.api`, too, so that downstream users only ever have to import from `envisage.api`.
