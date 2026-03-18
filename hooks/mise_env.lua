local pixi = require("hooks.pixi")

function PLUGIN:MiseEnv(ctx)
    local env_vars_raw, watch_files = pixi.get_env_vars(ctx)

    if not env_vars_raw then
        return { cacheable = true, watch_files = watch_files, env = {} }
    end

    local env_vars = {}
    for k, v in pairs(env_vars_raw) do
        if k ~= "PATH" then
            table.insert(env_vars, { key = k, value = v })
        end
    end

    return { cacheable = true, watch_files = watch_files, env = env_vars }
end
