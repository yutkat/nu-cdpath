# nu-cdpath

bash/zsh-style `CDPATH` for `cd` in Nushell.

With nu-cdpath, `cd dotfiles` works from any directory: when the target is not
found in the current directory, `cd` looks it up under the directories listed
in `$env.CDPATH`, as bash and zsh do. Tab completion offers those directories
too.

- The current directory is always searched first, so ordinary `cd` keeps
  working as before.
- Entries can be glob patterns such as `~/*`, so every directory one level
  below your home becomes reachable by name.
- Without `$env.CDPATH`, `cd` behaves exactly like the builtin.

## Requirements

- The latest Nushell release (0.116.0 or newer)
- Linux; tested in WezTerm

## Install

Clone the repository:

```sh
git clone https://github.com/yutkat/nu-cdpath.git /path/to/nu-cdpath
```

then add to your `config.nu`:

```nu
use /path/to/nu-cdpath/nu-cdpath cd
$env.CDPATH = [~ ~/projects]
```

Or install it with [nupm](https://github.com/nushell/nupm) from the clone
(`$env.NUPM_HOME/modules` must be in `$env.NU_LIB_DIRS`):

```nu
nupm install /path/to/nu-cdpath --path
```

and add to your `config.nu`:

```nu
use nu-cdpath cd
$env.CDPATH = [~ ~/projects]
```

`use nu-cdpath cd` replaces `cd` in your configuration; `use nu-cdpath` alone
only adds `nu-cdpath cd` and `nu-cdpath resolve` and leaves `cd` as it is. To
try it without your own configuration:

```sh
XDG_CONFIG_HOME=$(mktemp -d) nu --config examples/minimal-config.nu
```

## Usage

```nu
$env.CDPATH = [~ .. ~/* ~/.config]   # what zsh's cdpath=(~ .. ~/*(N-/) ~/.config) does
cd dotfiles                          # ~/dotfiles, from anywhere
cd nushell                           # ~/.config/nushell
cd dotfiles/.config                  # nested targets work too
nu-cdpath resolve dotfiles           # where `cd dotfiles` would go
```

`cd` without arguments, `cd -` and `cd -P` work as with the builtin.

### `$env.CDPATH`

- A list of directories, searched in order. A string separated by the path
  separator (`:` on Linux), as inherited from bash, works too.
- `~` is expanded; relative entries such as `..` are relative to the current
  directory.
- Entries containing `*` or `?` are glob patterns, expanded every time they are
  used, so new directories are found without restarting Nushell. Hidden
  directories match only when the pattern itself starts with `.`.
- Entries that do not exist are ignored.

### Which targets are looked up

A target is looked up in `$env.CDPATH` only when it is not a directory in the
current directory. Targets that name their location themselves are never
looked up: `-`, absolute paths, `~` paths, and paths starting with `./` or
`../`. Use those to make sure you stay where you are.

### Completion

Completion is unchanged while something in the current directory matches what
you typed. When nothing does, it offers matching directories from
`$env.CDPATH` instead, like zsh's
`zstyle ':completion:*:cd:*' tag-order local-directories path-directories`.

## How it works

- `nu-cdpath cd` is a custom command that resolves its argument with
  `nu-cdpath resolve` and passes the result to the builtin `cd`. Importing it
  as `cd` shadows the builtin in your configuration and the REPL only; scripts
  and other modules keep using the builtin.
- The completer returns no candidates of its own (`null`) when the current
  directory has matches, which makes Nushell fall back to its normal path
  completion.

## Known issues

- Only the `cd` command is affected; `ls`, `open` and other commands do not
  look up `$env.CDPATH`.
- Another module or config that also replaces `cd` wins or loses depending on
  which `use`/`def` comes last; only one replacement is active.

## Development

```sh
nu tests/run.nu
```
