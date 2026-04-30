local cmd = require("cmd")
local file = require("file")
local json = require("json")
local strings = require("strings")

local M = {}

local MANIFEST_NAMES = { "pixi.toml", "mojoproject.toml", "pyproject.toml" }

-- Parse null-delimited env output (from `env -0`) into a table.
-- Each entry is "KEY=VALUE" separated by NUL bytes.
local function parse_null_env(raw)
  local result = {}
  -- Split on NUL byte
  local i = 1
  while i <= #raw do
    local nul = raw:find("\0", i, true)
    local entry
    if nul then
      entry = raw:sub(i, nul - 1)
      i = nul + 1
    else
      entry = raw:sub(i)
      i = #raw + 1
    end
    if entry ~= "" then
      local eq = entry:find("=", 1, true)
      if eq then
        local k = entry:sub(1, eq - 1)
        local v = entry:sub(eq + 1)
        result[k] = v
      end
    end
  end
  return result
end

-- Parse line-delimited env output (from cmd.exe `set` command) into a table.
-- Each line is "KEY=VALUE". Handles \r\n line endings.
local function parse_line_env(raw)
  local result = {}
  -- Normalize \r\n to \n
  local normalized = raw:gsub("\r\n", "\n"):gsub("\r", "\n")
  local i = 1
  while i <= #normalized do
    local nl = normalized:find("\n", i, true)
    local line
    if nl then
      line = normalized:sub(i, nl - 1)
      i = nl + 1
    else
      line = normalized:sub(i)
      i = #normalized + 1
    end
    if line ~= "" then
      local eq = line:find("=", 1, true)
      if eq then
        local k = line:sub(1, eq - 1)
        local v = line:sub(eq + 1)
        if k:match("^[A-Za-z_][A-Za-z0-9_]*$") then
          result[k] = v
        end
      end
    end
  end
  return result
end

-- Returns true if running on Windows.
local function is_windows()
  return package.config:sub(1, 1) == "\\"
end

-- Extract file extension from a path. Returns lowercase extension including
-- the dot (e.g. ".sh", ".ps1", ".bat") or "" if there is no extension.
local function get_extension(path)
  local ext = path:match("(%.[^./\\]+)$")
  if ext then
    return ext:lower()
  end
  return ""
end

-- PowerShell env dump command: outputs NUL-delimited KEY=VALUE pairs.
local PS_ENV_DUMP = 'Get-ChildItem Env: | ForEach-Object { $_.Name + "=" + $_.Value + "`0" }'

-- Returns a table with shell execution info based on file extension + platform,
-- or nil if the combination is unsupported on the current platform.
local function shell_for_script(script_path)
  local ext = get_extension(script_path)

  if is_windows() then
    if ext == ".ps1" or ext == "" then
      return {
        cmd = "powershell",
        args = { "-NoProfile", "-Command" },
        source_cmd = ".",
        env_dump = PS_ENV_DUMP,
        parser = "null",
      }
    elseif ext == ".bat" or ext == ".cmd" then
      return {
        cmd = "cmd.exe",
        args = { "/c" },
        source_cmd = "call",
        env_dump = "set",
        parser = "line",
      }
    elseif ext == ".nu" or ext == ".elv" then
      print('[mise-env-pixi] warning: ' .. ext
        .. ' scripts (Nushell/Elvish) are not yet supported for activation, skipping: '
        .. script_path)
      return nil
    else
      -- .sh, .bash, .zsh, .fish and other Unix scripts are unsupported on Windows
      print('[mise-env-pixi] warning: unsupported script type "' .. ext
        .. '" on this platform, skipping: ' .. script_path)
      return nil
    end
  else
    -- Unix
    if ext == ".sh" or ext == "" then
      return {
        cmd = "sh",
        args = { "-c" },
        source_cmd = ".",
        env_dump = "env -0",
        parser = "null",
      }
    elseif ext == ".bash" then
      return {
        cmd = "bash",
        args = { "-c" },
        source_cmd = "source",
        env_dump = "env -0",
        parser = "null",
      }
    elseif ext == ".zsh" then
      return {
        cmd = "zsh",
        args = { "-c" },
        source_cmd = "source",
        env_dump = "env -0",
        parser = "null",
      }
    elseif ext == ".fish" then
      return {
        cmd = "fish",
        args = { "-c" },
        source_cmd = "source",
        env_dump = "env -0",
        parser = "null",
      }
    elseif ext == ".ps1" then
      return {
        cmd = "pwsh",
        args = { "-NoProfile", "-Command" },
        source_cmd = ".",
        env_dump = PS_ENV_DUMP,
        parser = "null",
      }
    elseif ext == ".nu" or ext == ".elv" then
      print('[mise-env-pixi] warning: ' .. ext
        .. ' scripts (Nushell/Elvish) are not yet supported for activation, skipping: '
        .. script_path)
      return nil
    else
      -- .bat, .cmd and other Windows scripts are unsupported on Unix
      print('[mise-env-pixi] warning: unsupported script type "' .. ext
        .. '" on this platform, skipping: ' .. script_path)
      return nil
    end
  end
end

-- Escape single quotes in a string for use inside a single-quoted shell argument.
-- Replaces each ' with '\'' (end quote, escaped quote, start quote).
local function shell_escape(s)
  return s:gsub("'", "'\\''")
end

-- Source a single activation script and return a table of env vars that are
-- new or changed compared to `baseline` (a table from parse_null_env).
-- Returns diff table and nil on success, or nil and an error string on failure.
local function source_script_env_diff(shell_info, script_path, baseline)
  local after_raw
  local ok
  local full_cmd

  if shell_info.cmd == "powershell" or shell_info.cmd == "pwsh" then
    -- PowerShell: `. "script" | Out-Null; <env dump>`
    local escaped_path = script_path:gsub('"', '`"')  -- PowerShell backtick-escape for double quotes
    local ps_cmd = string.format('. "%s" | Out-Null; %s', escaped_path, shell_info.env_dump)
    full_cmd = string.format('%s -NoProfile -Command "%s"',
      shell_info.cmd, ps_cmd:gsub('"', '\\"'))
    ok, after_raw = pcall(function()
      return cmd.exec(full_cmd)
    end)
  elseif shell_info.cmd == "cmd.exe" then
    -- cmd.exe: `call "script" >nul 2>&1 & set`
    full_cmd = string.format('cmd.exe /c "call \\"%s\\" >nul 2>&1 & %s"',
      script_path, shell_info.env_dump)
    ok, after_raw = pcall(function()
      return cmd.exec(full_cmd)
    end)
  else
    -- Unix-style shells (sh, bash, zsh, fish)
    -- Use double quotes around the script path (handles spaces),
    -- single quotes around the outer -c argument.
    local shell_cmd = string.format(
      '%s "%s" >/dev/null 2>&1; %s',
      shell_info.source_cmd,
      script_path:gsub('"', '\\"'),
      shell_info.env_dump
    )
    full_cmd = string.format("%s -c '%s'",
      shell_info.cmd, shell_escape(shell_cmd))
    ok, after_raw = pcall(function()
      return cmd.exec(full_cmd)
    end)
  end

  if not ok then
    return nil, "exec failed: " .. tostring(after_raw)
  end

  if not after_raw or after_raw == "" then
    return nil, "empty env output after sourcing script"
  end

  local after
  if shell_info.parser == "line" then
    after = parse_line_env(after_raw)
  else
    after = parse_null_env(after_raw)
  end

  -- Compute diff: keys that are new or have changed value
  local diff = {}
  for k, v in pairs(after) do
    if baseline[k] ~= v then
      diff[k] = v
    end
  end

  return diff, nil
end

function M.get_env_vars(ctx)
  local pixi_bin = ctx.options.pixi_bin or "pixi"
  local environment = ctx.options.environment
  local manifest_path = ctx.options.manifest_path
  local activation_scripts = ctx.options.activation_scripts or true

  local command = pixi_bin .. " shell-hook --json"
  if manifest_path then
    command = command .. ' --manifest-path "' .. manifest_path:gsub('"', '\\"') .. '"'
  end
  if environment then
    command = command .. ' --environment "' .. environment:gsub('"', '\\"') .. '"'
  end

  local ok, output = pcall(function()
    return cmd.exec(command)
  end)

  if not ok then
    print("[mise-env-pixi] warning: `" .. command .. "` failed: " .. tostring(output))
    return nil, {}
  end

  if not output or output == "" then
    return nil, {}
  end

  local decode_ok, data = pcall(json.decode, output)
  if not decode_ok then
    print("[mise-env-pixi] warning: failed to parse JSON: " .. tostring(data))
    return nil, {}
  end

  local env_vars = data["environment_variables"]
  if type(env_vars) ~= "table" then
    return nil, {}
  end

  -- Optionally source activation scripts and merge resulting env vars
  if activation_scripts then
    local scripts = data["activation_scripts"]
    if type(scripts) == "table" and #scripts > 0 then
      -- Capture the current process env as a baseline so we can diff against
      -- it after each script is sourced. Use a platform-aware command so the
      -- baseline matches exactly what the shell subprocess will see.
      local baseline_cmd
      if is_windows() then
        baseline_cmd = 'powershell -NoProfile -Command "' .. PS_ENV_DUMP:gsub('"', '\\"') .. '"'
      else
        baseline_cmd = "sh -c 'env -0'"
      end

      local baseline_ok, baseline_raw = pcall(function()
        return cmd.exec(baseline_cmd)
      end)

      local baseline = {}
      if baseline_ok and baseline_raw and baseline_raw ~= "" then
        baseline = parse_null_env(baseline_raw)
      else
        print("[mise-env-pixi] warning: could not capture baseline env; activation script diffs may be inaccurate")
      end

      for _, script_path in ipairs(scripts) do
        local shell_info = shell_for_script(script_path)
        if shell_info then
          local diff, err = source_script_env_diff(shell_info, script_path, baseline)
          if err then
            print("[mise-env-pixi] warning: failed to source activation script `"
              .. script_path .. "`: " .. err)
          else
            for k, v in pairs(diff) do
              env_vars[k] = v
            end
            for k, v in pairs(diff) do
              baseline[k] = v
            end
          end
        end
      end
    end
  end

  local watch_files = {}
  if manifest_path then
    table.insert(watch_files, manifest_path)
  else
    for _, name in ipairs(MANIFEST_NAMES) do
      if file.exists(name) then
        if name ~= "pyproject.toml" or strings.contains(file.read(name) or "", "[tool.pixi]") then
          table.insert(watch_files, name)
        end
      end
    end
  end
  if file.exists("pixi.lock") then
    table.insert(watch_files, "pixi.lock")
  end

  -- Watch activation scripts for changes
  local scripts = data["activation_scripts"]
  if type(scripts) == "table" then
    for _, script_path in ipairs(scripts) do
      if file.exists(script_path) then
        table.insert(watch_files, script_path)
      end
    end
  end

  return env_vars, watch_files
end

return M
