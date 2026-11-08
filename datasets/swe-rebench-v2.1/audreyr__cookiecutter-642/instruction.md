Expand Environment Variables in Cookiecutter Configuration File
I set my cookiecutterrc file via an environment variable, like this:

    export COOKIECUTTER_CONFIG="$XDG_CONFIG_HOME/cookiecutter/cookiecutterrc"

In my cookiecutterrc, I'd like to use those same environment variables to set paths, however they don't currently expand:

    default_context:
        full_name: "Nathan Farrar"
        email: "nathan.farrar@gmail.com"
        github_username: "nfarrar"
    cookiecutters_dir: "$XDG_CACHE_HOME/cookiecutter/template"
    replay_dir: "$XDG_CACHE_HOME/cookiecutter/replay"
    abbreviations:
        pp: https://github.com/audreyr/cookiecutter-pypackage.git
        gh: https://github.com/{0}.git
        bb: https://bitbucket.org/{0}

For example:

    $ cookiecutter pp
    $ ls ~/
    ...
    drwxr-xr-x   3 nfarrar staff  102 Feb 28 07:37 '$XDG_CACHE_HOME'
    ...
