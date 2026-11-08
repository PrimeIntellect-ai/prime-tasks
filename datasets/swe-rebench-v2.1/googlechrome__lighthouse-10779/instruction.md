Remove unused extendedInfo field from audits
A handful of audits are still setting the extendedInfo in their return value. Since extendedInfo has been wholly replaced by 'details' and 'debugData', it's no point in keeping it since it doesn't even make it into the LHR json.
