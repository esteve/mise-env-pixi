# mise-env-pixi

A [mise](https://mise.jdx.dev) env plugin that activates [pixi](https://pixi.sh) environments in your shell.

## Installation

Add the plugin to your project's `mise.toml`:

```toml
[plugins]
pixi-env = "https://github.com/esteve/mise-env-pixi"

[env]
_.pixi-env = { tools = true }
```

## Configuration Options

| Option               | Description                                                                  | Default       |
| -------------------- | ---------------------------------------------------------------------------- | ------------- |
| `tools`              | Use mise-managed tools (required if pixi is installed via mise)              | `false`       |
| `environment`        | Pixi environment name to activate                                            | pixi default  |
| `pixi_bin`           | Path to the pixi binary                                                      | `pixi`        |
| `manifest_path`      | Path to the pixi manifest file                                               | auto-detected |
| `activation_scripts` | Source pixi activation scripts and merge their environment changes (see [Activation Scripts](#activation-scripts)) | `true` |

### Examples

```toml
[plugins]
pixi-env = "https://github.com/esteve/mise-env-pixi"

[env]
# Activate the default pixi environment (activation_scripts defaults to true)
_.pixi-env = { tools = true }
```

```toml
[plugins]
pixi-env = "https://github.com/esteve/mise-env-pixi"

[env]
# Activate a named environment
_.pixi-env = { tools = true, environment = "cuda" }
```

```toml
[plugins]
pixi-env = "https://github.com/esteve/mise-env-pixi"

[env]
# Use a custom pixi binary and manifest path
_.pixi-env = { pixi_bin = "/opt/pixi/bin/pixi", manifest_path = "/path/to/pixi.toml" }
```

```toml
[plugins]
pixi-env = "https://github.com/esteve/mise-env-pixi"

[env]
# Disable activation scripts (scripts are sourced by default)
_.pixi-env = { tools = true, activation_scripts = false }
```

## Environment-Specific Configuration

Combine with mise's environment system for different pixi environments:

```toml
[plugins]
pixi-env = "https://github.com/esteve/mise-env-pixi"

[env]
_.pixi-env = { tools = true, environment = "dev" }

[env.production]
_.pixi-env = { tools = true, environment = "production" }
```

Then activate different environments:

```bash
# Development (default)
mise env

# Production
MISE_ENV=production mise env
```

## Manifest Detection

When `manifest_path` is not set, the plugin searches for pixi config files in the current directory. The following files are recognized:

- `pixi.toml`
- `mojoproject.toml`
- `pyproject.toml` — only when it contains a `[tool.pixi]` section

Plain `pyproject.toml` files without `[tool.pixi]` are ignored.

## Cache Invalidation

The plugin watches for changes to invalidate its cache:

- **Auto-detect mode**: all recognized manifest files that are present (`pixi.toml`, `mojoproject.toml`, and `pyproject.toml` with `[tool.pixi]`)
- **`manifest_path` set**: only the specified file is watched
- `pixi.lock` in the same directory, if it exists
- Activation scripts listed in `pixi.toml`, if they exist

Any change to a watched file clears the cached environment.

## Activation Scripts

Pixi supports custom activation scripts defined in `pixi.toml` under the `[activation]` section:

```toml
[activation]
scripts = ["activate.sh"]
```

By default, activation scripts are sourced automatically — the plugin sources each script and
captures any new or changed environment variables they produce. Set `activation_scripts = false`
to disable this behavior:

```toml
[env]
_.pixi-env.activation_scripts = false
```

**Note:** Requires pixi >= 0.67, which introduced the `activation_scripts` field in
`pixi shell-hook --json` output.

When enabled, the plugin selects the appropriate shell based on the script's file extension,
sources each script, captures the resulting environment diff, and merges it into the returned
environment. Cleanup is handled automatically by mise when leaving the directory.

**Unix:**

| Extension              | Shell  |
| ---------------------- | ------ |
| `.sh` (or no extension)| `sh`   |
| `.bash`                | `bash` |
| `.zsh`                 | `zsh`  |
| `.fish`                | `fish` |
| `.ps1`                 | `pwsh` |

**Windows:**

| Extension              | Shell        |
| ---------------------- | ------------ |
| `.ps1` (or no extension)| `powershell` |
| `.bat` / `.cmd`        | `cmd.exe`    |

> `.nu` (Nushell) and `.elv` (Elvish) scripts are not yet supported and will be skipped with a warning.

Scripts with unsupported extensions for the current platform are also skipped with a warning.

If a script fails to source, the error is logged as a warning and the script is skipped — the plugin
continues normally. The option defaults to `true`.

## Known Limitations

- Mise can only clean up environment variables that were set by activation scripts.
  Other side effects (shell functions, aliases, hooks) cannot be deactivated when
  leaving the directory, similar to upstream `pixi shell-hook`.

## Acknowledgments

Thanks to [Jeff Dickey](https://github.com/jdx) for [mise-env-fnox](https://github.com/jdx/mise-env-fnox), which this project is based on.

## License

Apache-2.0
