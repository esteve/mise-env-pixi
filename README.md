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

| Option          | Description                                                     | Default       |
| --------------- | --------------------------------------------------------------- | ------------- |
| `tools`         | Use mise-managed tools (required if pixi is installed via mise) | `false`       |
| `environment`   | Pixi environment name to activate                               | pixi default  |
| `pixi_bin`      | Path to the pixi binary                                        | `pixi`        |
| `manifest_path` | Path to the pixi manifest file                                 | auto-detected |

### Examples

```toml
[plugins]
pixi-env = "https://github.com/esteve/mise-env-pixi"

[env]
# Activate the default pixi environment
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

When `manifest_path` is not set, pixi automatically detects the manifest. The plugin watches for:

- `pixi.toml`
- `mojoproject.toml`
- `pyproject.toml` — only when it contains a `[tool.pixi]` section

Plain `pyproject.toml` files without `[tool.pixi]` are ignored.

## Cache Invalidation

The plugin watches two files for changes:

- The detected (or configured) manifest file
- `pixi.lock` in the same directory, if it exists

Any change to either file clears the cached environment.

## Known Limitations

- `pixi shell-hook --json` reports environment variables and PATH entries but does not run activation scripts. Conda-style hooks (e.g. `conda activate` side effects) will not execute.

## Acknowledgments

Thanks to [Jeff Dickey](https://github.com/jdx) for [mise-env-fnox](https://github.com/jdx/mise-env-fnox), which this project is based on.

## License

Apache-2.0
