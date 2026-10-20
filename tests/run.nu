# Test entry point: `nu tests/run.nu`. Exits non-zero when a test fails.
#
# These tests exercise CDPATH parsing, lookup and `cd` in-process. Completion
# only runs inside the line editor, so it is checked through
# `nu --ide-complete`, which calls the same completer.

use std/assert

const ROOT = path self ..
use ($ROOT | path join nu-cdpath)
use ($ROOT | path join nu-cdpath lib.nu) *

# A fresh directory tree:
#   here/{local,shared}  one/{foo,shared,.hidden,deep/inner}  two/{bar,shared}
#   one/file (a regular file)
def scratch []: nothing -> string {
    let root = $env.__TEST_ROOT | path join (random uuid)
    for d in [here/local here/shared one/foo one/shared one/.hidden one/deep/inner two/bar two/shared] {
        mkdir ($root | path join $d)
    }
    touch ($root | path join one file)
    $root
}

# Completions `nu --ide-complete` offers for `line` typed after `use nu-cdpath cd`.
# `--home` sets HOME for the child process, where `~` expands to it.
def ide-complete [line: string, cdpath: string, cwd: string, --home: string]: nothing -> list<string> {
    let file = $env.__TEST_ROOT | path join $"(random uuid).nu"
    let source = $"use ($ROOT | path join nu-cdpath) cd\n($line)"
    $source | save $file
    cd $cwd
    let home = if $home == null { {} } else { {HOME: $home} }
    with-env ({CDPATH: $cdpath} | merge $home) {
        ^$nu.current-exe -n --ide-complete ($source | str length --utf-8-bytes) $file
    } | from json | get completions
}

# --- parsing ----------------------------------------------------------------

def "test CDPATH lists and strings are parsed" [] {
    assert equal ([/a "" " /b "] | parse-cdpath) [/a /b]
    assert equal ($"/a(char esep)(char esep)/b" | parse-cdpath) [/a /b]
    assert equal (null | parse-cdpath) []
    assert error { 42 | parse-cdpath }
}

def "test explicit targets are recognized" [] {
    for t in ["-" / /usr ~ ~/x . .. ./x ../x] {
        assert ($t | is-explicit) $"($t) should be explicit"
    }
    for t in [x x/y .config ...x] {
        assert (not ($t | is-explicit)) $"($t) should not be explicit"
    }
}

# --- expansion and lookup ---------------------------------------------------

def "test glob entries expand to visible directories" [] {
    let root = scratch
    let found = [($root | path join one "*")] | expand-entries | path basename | sort
    assert equal $found [deep foo shared]
}

def "test missing entries and files are dropped" [] {
    let root = scratch
    let entries = [($root | path join nope) ($root | path join one file) ($root | path join two) ($root | path join nope "*")]
    assert equal ($entries | expand-entries) [($root | path join two)]
}

def "test lookup takes the first base with the target" [] {
    let root = scratch
    let bases = [($root | path join one) ($root | path join two)]
    assert equal (find-in-bases shared $bases) ($root | path join one shared)
    assert equal (find-in-bases bar $bases) ($root | path join two bar)
    assert equal (find-in-bases deep/inner $bases) ($root | path join one deep inner)
    assert equal (find-in-bases file $bases) null
    assert equal (find-in-bases nope $bases) null
}

def "test candidates keep the parent part and are unique" [] {
    let root = scratch
    let bases = [($root | path join one) ($root | path join two)]
    assert equal (cdpath-candidates sh $bases) [shared/]
    assert equal (cdpath-candidates "" $bases | sort) [.hidden/ bar/ deep/ foo/ shared/]
    assert equal (cdpath-candidates deep/in $bases) [deep/inner/]
    assert equal (cdpath-candidates fi $bases) []
}

def "test candidates match glob characters literally" [] {
    let root = scratch
    for d in ["a[b]/in" ab "a*c"] {
        mkdir ($root | path join one $d)
    }
    let bases = [($root | path join one)]
    assert equal (cdpath-candidates "a[" $bases) ["a[b]/"]
    assert equal (cdpath-candidates "a*" $bases) ["a*c/"]
    assert equal (cdpath-candidates "a?" $bases) []
    assert equal (cdpath-candidates a $bases | sort) ["a*c/" "a[b]/" ab/]
    assert equal (cdpath-candidates "a[b]/" $bases) ["a[b]/in/"]
    assert equal (cdpath-candidates deep/ $bases) [deep/inner/]
}

# --- cd ---------------------------------------------------------------------

def --env "test use alone keeps the builtin cd" [] {
    let root = scratch
    cd ($root | path join here)
    $env.CDPATH = [($root | path join one)]
    assert error { cd foo }
}

def --env "test cd falls back to CDPATH" [] {
    let root = scratch
    cd ($root | path join here)
    $env.CDPATH = [($root | path join one) ($root | path join two)]
    nu-cdpath cd foo
    assert equal $env.PWD ($root | path join one foo)
    nu-cdpath cd bar
    assert equal $env.PWD ($root | path join two bar)
    nu-cdpath cd deep/inner
    assert equal $env.PWD ($root | path join one deep inner)
}

def --env "test cd prefers the current directory" [] {
    let root = scratch
    cd ($root | path join here)
    $env.CDPATH = [($root | path join one)]
    nu-cdpath cd shared
    assert equal $env.PWD ($root | path join here shared)
}

def --env "test cd follows the CDPATH order" [] {
    let root = scratch
    cd ($root | path join here local)
    $env.CDPATH = [($root | path join two) ($root | path join one)]
    nu-cdpath cd shared
    assert equal $env.PWD ($root | path join two shared)
}

def --env "test cd accepts a CDPATH string and glob entries" [] {
    let root = scratch
    cd ($root | path join here)
    $env.CDPATH = $"($root | path join two)(char esep)($root | path join "*")"
    nu-cdpath cd foo
    assert equal $env.PWD ($root | path join one foo)
    nu-cdpath cd local
    assert equal $env.PWD ($root | path join here local)
}

def --env "test relative CDPATH entries follow the current directory" [] {
    let root = scratch
    cd ($root | path join here local)
    $env.CDPATH = [..]
    nu-cdpath cd shared
    assert equal $env.PWD ($root | path join here shared)
}

def --env "test explicit targets are not looked up" [] {
    let root = scratch
    cd ($root | path join here)
    $env.CDPATH = [($root | path join one)]
    assert error { nu-cdpath cd ./foo }
    assert equal $env.PWD ($root | path join here)
}

def --env "test cd without a match or CDPATH reports an error" [] {
    let root = scratch
    cd ($root | path join here)
    $env.CDPATH = [($root | path join one)]
    assert error { nu-cdpath cd nope }
    assert error { nu-cdpath cd file }
    hide-env CDPATH
    assert error { nu-cdpath cd foo }
    assert equal (nu-cdpath resolve foo) foo
}

def --env "test cd without arguments, dash and physical work like the builtin" [] {
    let root = scratch
    cd ($root | path join here)
    nu-cdpath cd
    assert equal $env.PWD $nu.home-dir
    nu-cdpath cd -
    assert equal $env.PWD ($root | path join here)
    ^ln -s ($root | path join one) ($root | path join link)
    $env.CDPATH = [$root]
    nu-cdpath cd link
    assert equal $env.PWD ($root | path join link)
    nu-cdpath cd -P ($root | path join link)
    assert equal $env.PWD ($root | path join one)
}

def --env "test use with the command name replaces cd" [] {
    use ($ROOT | path join nu-cdpath) cd
    let root = scratch
    cd ($root | path join here)
    $env.CDPATH = [($root | path join one)]
    cd foo
    assert equal $env.PWD ($root | path join one foo)
}

# --- completion -------------------------------------------------------------

def "test completion offers CDPATH directories when nothing matches here" [] {
    let root = scratch
    let cdpath = $"($root | path join one)(char esep)($root | path join two)"
    let here = $root | path join here
    assert equal (ide-complete "cd fo" $cdpath $here) [foo/]
    assert equal (ide-complete "cd deep/in" $cdpath $here) [deep/inner/]
    assert equal (ide-complete "cd nope" $cdpath $here) []
}

# Changing HOME does not affect `~` in the running shell, only in a child
# process, so `~` bases are checked through completion.
def "test completion expands a tilde in CDPATH entries" [] {
    let root = scratch
    let here = $root | path join here
    assert equal (ide-complete "cd fo" "~/one" $here --home $root) [foo/]
    assert equal (ide-complete "cd deep/" "~/one" $here --home $root) [deep/inner/]
}

# An unclosed `[` is a parse error, which stops `--ide-complete` from running
# the completer, so only lines that parse are checked here.
def "test completion matches glob characters literally" [] {
    let root = scratch
    for d in ["a[b]x" abx "a*c" ab] {
        mkdir ($root | path join one $d)
    }
    let cdpath = $root | path join one
    let here = $root | path join here
    assert equal (ide-complete "cd a[b]" $cdpath $here) ["a[b]x/"]
    assert equal (ide-complete "cd a*" $cdpath $here) ["a*c/"]
    assert equal (ide-complete "cd a?" $cdpath $here) []
}

def "test completion keeps local paths as they are" [] {
    let root = scratch
    let cdpath = $root | path join one
    let here = $root | path join here
    assert equal (ide-complete "cd sh" $cdpath $here) [shared/]
    assert equal (ide-complete "cd lo" $cdpath $here) [local/]
    assert equal (ide-complete "cd ./fo" $cdpath $here) []
}

# --- runner -----------------------------------------------------------------

# Each test runs in its own closure, so `$env` changes (including PWD) do not
# leak between tests.
const TESTS = [
    "test CDPATH lists and strings are parsed"
    "test explicit targets are recognized"
    "test glob entries expand to visible directories"
    "test missing entries and files are dropped"
    "test lookup takes the first base with the target"
    "test candidates keep the parent part and are unique"
    "test candidates match glob characters literally"
    "test use alone keeps the builtin cd"
    "test cd falls back to CDPATH"
    "test cd prefers the current directory"
    "test cd follows the CDPATH order"
    "test cd accepts a CDPATH string and glob entries"
    "test relative CDPATH entries follow the current directory"
    "test explicit targets are not looked up"
    "test cd without a match or CDPATH reports an error"
    "test cd without arguments, dash and physical work like the builtin"
    "test use with the command name replaces cd"
    "test completion offers CDPATH directories when nothing matches here"
    "test completion expands a tilde in CDPATH entries"
    "test completion matches glob characters literally"
    "test completion keeps local paths as they are"
]

def --env run-test [name: string]: nothing -> any {
    try {
        match $name {
            "test CDPATH lists and strings are parsed" => { test CDPATH lists and strings are parsed }
            "test explicit targets are recognized" => { test explicit targets are recognized }
            "test glob entries expand to visible directories" => { test glob entries expand to visible directories }
            "test missing entries and files are dropped" => { test missing entries and files are dropped }
            "test lookup takes the first base with the target" => { test lookup takes the first base with the target }
            "test candidates keep the parent part and are unique" => { test candidates keep the parent part and are unique }
            "test candidates match glob characters literally" => { test candidates match glob characters literally }
            "test use alone keeps the builtin cd" => { test use alone keeps the builtin cd }
            "test cd falls back to CDPATH" => { test cd falls back to CDPATH }
            "test cd prefers the current directory" => { test cd prefers the current directory }
            "test cd follows the CDPATH order" => { test cd follows the CDPATH order }
            "test cd accepts a CDPATH string and glob entries" => { test cd accepts a CDPATH string and glob entries }
            "test relative CDPATH entries follow the current directory" => { test relative CDPATH entries follow the current directory }
            "test explicit targets are not looked up" => { test explicit targets are not looked up }
            "test cd without a match or CDPATH reports an error" => { test cd without a match or CDPATH reports an error }
            "test cd without arguments, dash and physical work like the builtin" => { test cd without arguments, dash and physical work like the builtin }
            "test use with the command name replaces cd" => { test use with the command name replaces cd }
            "test completion offers CDPATH directories when nothing matches here" => { test completion offers CDPATH directories when nothing matches here }
            "test completion expands a tilde in CDPATH entries" => { test completion expands a tilde in CDPATH entries }
            "test completion matches glob characters literally" => { test completion matches glob characters literally }
            "test completion keeps local paths as they are" => { test completion keeps local paths as they are }
            _ => (error make {msg: $"no such test: ($name)"})
        }
        null
    } catch {|err| $err.msg }
}

def main [] {
    let root = mktemp --directory --tmpdir nu-cdpath-test.XXXXXX
    let results = $TESTS | each {|name|
        {name: $name, error: (do { $env.__TEST_ROOT = $root; run-test $name })}
    }
    rm --recursive $root
    for r in $results {
        if $r.error == null {
            print $"ok    ($r.name)"
        } else {
            print $"FAIL  ($r.name): ($r.error)"
        }
    }
    let failed = $results | where error != null | length
    print $"\n($results | length) tests, ($failed) failed"
    if $failed > 0 { exit 1 }
}
