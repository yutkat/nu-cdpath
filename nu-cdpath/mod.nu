# nu-cdpath: bash/zsh-style CDPATH for `cd` in Nushell.
#
# `use nu-cdpath` only defines `nu-cdpath cd` and `nu-cdpath resolve`;
# `use nu-cdpath cd` replaces `cd` in the importing scope.

use lib.nu *

# The builtin; this module's own `cd` does not shadow it here.
alias builtin-cd = cd

def bases []: nothing -> list<string> {
    $env.CDPATH? | parse-cdpath | expand-entries
}

# Local directories first; CDPATH ones only when nothing here matches, so
# normal path completion stays as it is.
def complete-dir [token: record]: nothing -> any {
    let prefix = $token.text
    if ($prefix | is-explicit) or (matching-dirs $prefix . | is-not-empty) {
        return null
    }
    cdpath-candidates $prefix (bases)
}

# Resolve a `cd` target: itself when it exists here (or names its location
# explicitly), otherwise the first match under a $env.CDPATH entry, otherwise
# unchanged so `cd` reports the error.
export def resolve [target: string]: nothing -> string {
    if ($target | is-explicit) or ($target | is-dir) {
        return $target
    }
    find-in-bases $target (bases) | default $target
}

# Change directory, looking up targets missing here in $env.CDPATH.
#
# $env.CDPATH is a list of directories (or a string separated by the path
# separator); entries with `*` or `?` are glob patterns such as `~/*`.
export def --env cd [
    path?: string@complete-dir # Directory to change to (default: home)
    --physical (-P) # Resolve symbolic links, as the builtin does
]: nothing -> nothing {
    let target = if $path == null { $nu.home-dir } else { resolve $path }
    if $physical {
        builtin-cd --physical $target
    } else {
        builtin-cd $target
    }
}
