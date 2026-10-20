# Helpers for nu-cdpath: CDPATH parsing, directory lookup and completion
# candidates. Nothing here reads `$env`, so it can be tested directly.

# Normalize a CDPATH value: a list of entries, or a string separated by the
# platform path separator (as inherited from bash). Empty entries are dropped,
# because the current directory is always searched first anyway.
export def parse-cdpath []: any -> list<string> {
    let value = $in
    let entries = match ($value | describe --detailed).type {
        "nothing" => []
        "string" => ($value | split row (char esep))
        "list" => $value
        _ => (error make {msg: $"CDPATH must be a list or a string, got ($value | describe)"})
    }
    $entries | each { into string | str trim } | where { is-not-empty }
}

# Whether a path is a directory, following symbolic links.
export def is-dir []: string -> bool {
    ($in | path expand | path type) == dir
}

# Targets that name their location themselves and are never looked up in
# CDPATH: `-`, absolute paths, `~` paths and paths starting with `.` or `..`.
export def is-explicit []: string -> bool {
    $in == "-" or $in =~ '^(/|~|\.\.?(/|$))'
}

# Expand CDPATH entries into base directories. Entries containing `*` or `?`
# are glob patterns (e.g. `~/*`), expanded on every call so new directories
# show up; hidden directories match only when the pattern asks for them.
export def expand-entries []: list<string> -> list<string> {
    each {|entry|
        if ($entry =~ '[*?]') {
            try { ls ($entry | path expand --no-symlink | into glob) | get name } catch { [] }
        } else {
            [$entry]
        }
    }
    | flatten
    | where { is-dir }
}

# The first `base/target` that is a directory, or null.
export def find-in-bases [target: string, bases: list<string>]: nothing -> any {
    $bases | each {|b| $b | path join $target } | where { is-dir } | get --optional 0
}

# Split a typed prefix into its parent part and the name being typed. A
# trailing `/` means the whole prefix is the parent (`path dirname` drops it).
def split-prefix []: string -> record<parent: string, name: string> {
    let prefix = $in
    if ($prefix | str ends-with "/") {
        {parent: ($prefix | str trim --right --char "/"), name: ""}
    } else {
        {parent: ($prefix | path dirname), name: ($prefix | path basename)}
    }
}

# Directories matching `prefix*` under `base`, as full paths. The prefix is
# matched literally, so glob characters such as `[` in it are not wildcards.
export def matching-dirs [prefix: string, base: string]: nothing -> list<string> {
    let p = $prefix | split-prefix
    let dir = if ($p.parent | is-empty) { $base } else { $base | path join $p.parent }
    try {
        # A string variable is neither glob- nor tilde-expanded by `ls`, so
        # expand `~` here; `--no-symlink` keeps symlinked bases as they are.
        ls --all ($dir | path expand --no-symlink)
        | get name
        | where {|n| ($n | path basename | str starts-with $p.name) and ($n | is-dir) }
    } catch { [] }
}

# Completion candidates for `prefix` taken from the bases, keeping the
# prefix's parent part (`dotfiles/.con` -> `dotfiles/.config/`).
export def cdpath-candidates [prefix: string, bases: list<string>]: nothing -> list<string> {
    let parent = ($prefix | split-prefix).parent
    $bases
    | each {|b| matching-dirs $prefix $b }
    | flatten
    | each {|d| ($parent | path join ($d | path basename)) + "/" }
    | uniq
}
