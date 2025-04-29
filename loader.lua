if shared.Faker then
    return
end

local BASE_URL = "https://raw.githubusercontent.com/yj5v/fake-rivals-first-person-models/main/"
local INDEX_URL = BASE_URL .. "index.lua"

local HttpService = game:GetService("HttpService")

local Faker = {
    Modules = {}
}

shared.Faker = Faker

local function isValidModuleName(name: string): boolean
    return name:match("^[%w_]+$") ~= nil
end

function Faker.__loadModule(moduleName: string)
    assert(isValidModuleName(moduleName), `Invalid module name: {moduleName}`)

    if Faker.Modules[moduleName] then
        return Faker.Modules[moduleName]
    end

    local success, result = pcall(function()
        local source = game:HttpGet(BASE_URL .. "modules/" .. moduleName .. ".lua", true)
        return loadstring(source)()
    end)

    if success then
        Faker.Modules[moduleName] = result
        return result
    else
        warn(`Failed to load module '{moduleName}': {result}`)
        return nil
    end
end

local success, response = pcall(function()
    return game:HttpGet(INDEX_URL, true)
end)

if success then
    for _, moduleName in ipairs( loadstring(response)() ) do
        Faker.__loadModule(moduleName)
    end
else
    warn("Failed to load index.json:", response)
end
