.cookiecutterrc and cookiecutters_dir not working as I expected
Hi,
Here's the setup:
+ I have a ~/.cookiecutterrc as talked about here: http://cookiecutter.readthedocs.org/en/latest/advanced_usage.html
+ I also have a cookiecutters_dir at ~/.cookiecutters/ with the subdirectory cookiecutter-pypackage/.

When I try to run "cookiecutter cookiecutter-pypackage/" in ~/Projects/, I get the following error

    Traceback (most recent call last):
      File "/opt/anaconda/bin/cookiecutter", line 9, in <module>
        load_entry_point('cookiecutter==0.9.0', 'console_scripts', 'cookiecutter')()
      File "/opt/anaconda/lib/python2.7/site-packages/click-3.3-py2.7.egg/click/core.py", line 610, in __call__
        return self.main(*args, **kwargs)
      File "/opt/anaconda/lib/python2.7/site-packages/click-3.3-py2.7.egg/click/core.py", line 590, in main
        rv = self.invoke(ctx)
      File "/opt/anaconda/lib/python2.7/site-packages/click-3.3-py2.7.egg/click/core.py", line 782, in invoke
        return ctx.invoke(self.callback, **ctx.params)
      File "/opt/anaconda/lib/python2.7/site-packages/click-3.3-py2.7.egg/click/core.py", line 416, in invoke
        return callback(*args, **kwargs)
      File "/Users/alexp/Projects/cookiecutter/cookiecutter/cli.py", line 70, in main
        cookiecutter(template, checkout, no_input)
      File "/Users/alexp/Projects/cookiecutter/cookiecutter/main.py", line 95, in cookiecutter
        extra_context=extra_context,
      File "/Users/alexp/Projects/cookiecutter/cookiecutter/generate.py", line 43, in generate_context
        file_handle = open(context_file)
    IOError: [Errno 2] No such file or directory: u'cookiecutter-pypackage/cookiecutter.json'

This error shows up if I either do pip install or with the git repo locally.  Naturally, it makes a bit of sense.  There is no directory ~/Projects/cookiecutter-pypackage/.

However, and perhaps I'm making a poor assumption about usage, it seems to me if I clone or otherwise create a cookiecutter and it's sitting in cookiecutters_dir, it'd be nice to just refer to it as I did above.  For my usage, if I create a cookiecutter, I don't particularly want it sitting around a Projects directory, especially if I have multiple project directories for personal and organizational purposes.

In order to do this, I added three lines to main.py in my fork (see below) and it seems to work.  I did it as an `elif` to try to preserve the possibility of a lack of a cookiecutters_dir.  I have not written a test for this and admittedly I don't really know how.  I will likely just use my fork with this modificationgoing forward but I wanted to let the developer crew know about this.

Cheers.

    # cookiecutter.main
    ...
    # TODO: find a better way to tell if it's a repo URL
    if 'git@' in template or 'https://' in template:
        repo_dir = clone(
            repo_url=template,
            checkout=checkout,
            clone_to_dir=config_dict['cookiecutters_dir'],
            no_input=no_input
        )
    #### Added these three lines
    [HIDDEN]
    else:
        # If it's a local repo, no need to clone or copy to your
        # cookiecutters_dir
        repo_dir = template

### Additional contract requirements

- The public function `determine_repo_dir(template, abbreviations, clone_to_dir, checkout, no_input)` in the module `cookiecutter.repository` returns the filesystem path of the repository directory that contains a `cookiecutter.json` file.
- `clone_to_dir` is the directory into which remote templates are cloned and in which already-cloned templates are looked up by name.
- When `template` is a remote repository URL, it is cloned into `clone_to_dir` and the cloned location is used as the candidate repository directory.
- When `template` is not a remote repository URL, the candidate repository directories are the literal `template` path and the path formed by joining `clone_to_dir` and `template`; the first candidate that contains a `cookiecutter.json` file is returned.
- When no candidate contains a `cookiecutter.json` file, `cookiecutter.exceptions.RepositoryNotFound` is raised with the message `A valid repository for "<template>" could not be found in the following locations:\n<path1>\n<path2>`, where the candidate locations are joined by newlines.
