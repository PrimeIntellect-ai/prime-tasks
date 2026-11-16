Support Alpine Linux family
Currently there's a mapping for Linux distributions to families; E.G. Ubuntu and Rasbian are in the Debian family, CentOs and Fedora are in the Red Hat family https://github.com/elastic/go-sysinfo/blob/6d844a021a259bdc8ef539d7689934febbcca538/providers/linux/os.go#L50-L58

Alpine Linux is supported as a distribution and is included in tests, however it returns an empty string for the OS Family. While Alpine doesn't have many derivatives at this time, it is used enough in use cases like containers that for consistency and ease Family should return `alpine` just like you get `debian` for the family if you run it on `debian`
