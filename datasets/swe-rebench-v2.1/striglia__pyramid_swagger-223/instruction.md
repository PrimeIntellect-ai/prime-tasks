Add raw_bytes attribute to PyramidSwaggerResponse
Once Yelp/bravado-core#214 is completed, all classes using the OutgoingResponse will be required to have a new attribute, `raw_bytes` defined. Responses in `PyramidSwaggerResponse` will need to but updated for this change
