local cmd = require("cmd")
local file = require("file")
local json = require("json")
local strings = require("strings")

local M = {}

local MANIFEST_NAMES = { "pixi.toml", "mojoproject.toml", "pyproject.toml" }

function M.get_env_vars(ctx)
    local pixi_bin = ctx.options.pixi_bin or "pixi"
    local environment = ctx.options.environment
    local manifest_path = ctx.options.manifest_path

    local command = pixi_bin .. " shell-hook --json"
    if manifest_path then
        command = command .. " --manifest-path " .. manifest_path
    end
    if environment then
        command = command .. " --environment " .. environment
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

    return env_vars, watch_files
end

return M
