if shared.Faker then
    return
end

local BASE_URL = "https://raw.githubusercontent.com/yj5v/fake-rivals-first-person-models/main/modules/"
local INDEX_URL = BASE_URL .. "index.json"

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
        local source = game:HttpGet(BASE_URL .. moduleName .. ".lua", true)
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
    local moduleList = HttpService:JSONDecode(response)
    for _, moduleName in ipairs(moduleList) do
        Faker.__loadModule(moduleName)
    end
else
    warn("Failed to load index.json:", response)
end
