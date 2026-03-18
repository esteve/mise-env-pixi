local strings = require("strings")
local pixi = require("hooks.pixi")

local function split_path(path_str)
    if not path_str or path_str == "" then
        return {}
    end
    return strings.split(path_str, ":")
end

local function to_set(arr)
    local s = {}
    for _, v in ipairs(arr) do
        s[v] = true
    end
    return s
end

function PLUGIN:MisePath(ctx)
    local env_vars, _ = pixi.get_env_vars(ctx)

    if not env_vars then
        return {}
    end

    local pixi_path_str = env_vars["PATH"]
    if not pixi_path_str or pixi_path_str == "" then
        return {}
    end

    local current_path_str = os.getenv("PATH") or ""
    local current_entries = to_set(split_path(current_path_str))

    local result = {}
    for _, entry in ipairs(split_path(pixi_path_str)) do
        if entry ~= "" and not current_entries[entry] then
            table.insert(result, entry)
        end
    end

    return result
end
