# Minimal config to try nu-cdpath without any other customization:
#
#   XDG_CONFIG_HOME=$(mktemp -d) nu --config examples/minimal-config.nu
#
# In your own config.nu, replace the path below with where you cloned the repo,
# or put the clone's parent directory in $env.NU_LIB_DIRS and `use nu-cdpath cd`.

$env.config.show_banner = false

use ../nu-cdpath cd
# `cd <name>` also finds directories in your home and one level below it.
$env.CDPATH = [~ ~/*]
