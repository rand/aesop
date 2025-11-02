# Configuration System

Aesop supports comprehensive runtime configuration through a simple key=value configuration file. Settings can be persisted to disk and take effect immediately when the editor starts.

## Configuration File

### Location

Aesop searches for configuration files in the following order:

1. `$XDG_CONFIG_HOME/aesop/config.conf` (if `XDG_CONFIG_HOME` is set)
2. `~/.config/aesop/config.conf` (default on Linux/macOS)
3. `./aesop.conf` (current directory fallback)

The first file found is used. If no configuration file exists, built-in defaults are used.

### Format

Configuration uses a simple key=value format with support for comments:

```conf
# Aesop Editor Configuration
# Lines starting with # are comments

# Editor behavior
tab_width=4
expand_tabs=true
line_numbers=true
relative_line_numbers=false

# Visual settings
syntax_highlighting=true
highlight_current_line=true
```

Boolean values accept: `true`/`false`, `yes`/`no`, `1`/`0`

## Configuration Settings

### Editor Behavior

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `tab_width` | number (1-16) | `4` | Width of tab character in spaces |
| `expand_tabs` | boolean | `true` | Insert spaces instead of tab character when Tab is pressed |
| `line_numbers` | boolean | `true` | Show line numbers in gutter |
| `relative_line_numbers` | boolean | `false` | Show relative line numbers (distance from cursor) |
| `auto_indent` | boolean | `true` | Automatically indent new lines |
| `wrap_lines` | boolean | `false` | Wrap long lines (not yet implemented) |

### Visual Settings

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `show_whitespace` | boolean | `false` | Display whitespace characters (not yet implemented) |
| `highlight_current_line` | boolean | `true` | Highlight the line containing the cursor |
| `show_indent_guides` | boolean | `false` | Show visual indentation guides (not yet implemented) |
| `syntax_highlighting` | boolean | `true` | Enable syntax highlighting for supported languages |

### Search Settings

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `search_case_sensitive` | boolean | `false` | Search is case-sensitive by default |
| `search_wrap_around` | boolean | `true` | Search wraps to beginning when reaching end of file |

### Multi-Cursor Settings

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `multi_cursor_enabled` | boolean | `true` | Enable multiple cursor support |
| `max_cursors` | number (1-1000) | `100` | Maximum number of cursors allowed |

### Auto-Pairing Settings

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `auto_pair_brackets` | boolean | `true` | Automatically insert closing brackets/quotes |

### Performance Settings

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `scroll_offset` | number | `3` | Minimum lines to keep above/below cursor when scrolling |
| `max_undo_history` | number | `1000` | Maximum number of undo steps to keep |

### File Handling

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `auto_save` | boolean | `false` | Automatically save files (not yet implemented) |
| `auto_save_delay_ms` | number | `1000` | Delay before auto-save triggers |
| `trim_trailing_whitespace` | boolean | `false` | Remove trailing whitespace on save |
| `ensure_newline_at_eof` | boolean | `true` | Ensure file ends with newline |

## Using Configuration

### Viewing Current Settings

To see the current configuration values, use the command palette (Space + P) and run:

```
config_show
```

This displays the most commonly used settings in the message area.

### Saving Configuration

To write the current configuration to disk:

1. Use the command palette (Space + P)
2. Run `config_write`
3. Configuration is saved to `~/.config/aesop/config.conf` (or `$XDG_CONFIG_HOME/aesop/config.conf`)

The command creates the directory if it doesn't exist.

### Runtime Configuration Changes

Currently, configuration changes require editing the config file manually and restarting the editor. Future versions will support runtime changes through `:set` commands.

## Examples

### Minimal Configuration

For a minimal setup with default behavior:

```conf
# Minimal config - just override a few settings
tab_width=2
expand_tabs=true
relative_line_numbers=true
```

### Programming-Focused Configuration

For software development:

```conf
# Programming-focused configuration
tab_width=4
expand_tabs=true
line_numbers=true
relative_line_numbers=false
auto_indent=true
syntax_highlighting=true
auto_pair_brackets=true
search_case_sensitive=true
trim_trailing_whitespace=true
ensure_newline_at_eof=true
max_undo_history=2000
```

### Writer-Friendly Configuration

For prose and documentation:

```conf
# Writer-friendly configuration
tab_width=2
expand_tabs=true
line_numbers=false
wrap_lines=true
syntax_highlighting=false
auto_pair_brackets=false
search_case_sensitive=false
```

### Performance-Tuned Configuration

For working with large files:

```conf
# Performance-tuned configuration
syntax_highlighting=false
max_undo_history=100
max_cursors=10
highlight_current_line=false
```

## Configuration Validation

Invalid configuration values are rejected with error messages:

- `tab_width` must be between 1 and 16
- `max_cursors` must be between 1 and 1000
- `max_undo_history` must be greater than 0

If validation fails, the editor falls back to default values for invalid settings.

## Troubleshooting

### Configuration Not Loading

1. Check file exists: `ls ~/.config/aesop/config.conf`
2. Check file permissions are readable
3. Verify file format (key=value, no spaces around `=`)
4. Run `config_show` to see what settings were loaded

### Settings Not Taking Effect

Some settings require specific conditions:

- **line_numbers/relative_line_numbers**: Takes effect immediately on startup
- **tab_width/expand_tabs**: Applies to new Tab key presses in insert mode
- **syntax_highlighting**: Only applies to supported file types (Zig, C, Rust, Go, Python)
- **search_case_sensitive/search_wrap_around**: Applies to new searches started with `/`

### Resetting to Defaults

To reset configuration to defaults:

1. Remove or rename the config file: `mv ~/.config/aesop/config.conf ~/.config/aesop/config.conf.bak`
2. Restart the editor
3. Optionally run `config_write` to create a new config file with defaults

## Advanced Usage

### Per-Project Configuration

You can use a local `aesop.conf` file in your project directory to override global settings. The local file takes precedence when found.

Example project-specific config:

```conf
# Project-specific settings for Python codebase
tab_width=4
expand_tabs=true
search_case_sensitive=true
```

### Environment-Specific Configuration

Use `$XDG_CONFIG_HOME` to maintain different configurations for different environments:

```bash
# Development environment
export XDG_CONFIG_HOME="$HOME/.config/dev"
aesop

# Production review environment
export XDG_CONFIG_HOME="$HOME/.config/prod"
aesop
```

## Future Enhancements

Planned configuration features:

- **Runtime updates**: `:set tab_width=2` to change settings without restart
- **Configuration profiles**: Switch between predefined configuration sets
- **Buffer-local settings**: Override settings per file or file type
- **Color scheme configuration**: Customize syntax highlighting colors
- **Key binding customization**: Remap keys through configuration file

## See Also

- [Interactive Commands](interactive-commands.md) - Command system and prompts
- [Prompt System Architecture](../architecture/prompt-system.md) - How commands work internally
