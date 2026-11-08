Hex::line_to always returns the origin when start==end
Specialcasing this in my code fixed the bug I was seeing, so it's just a simple bad computation :)
