if shared.Faker then
	return
end

shared.Faker = {}

local Faker = shared.Faker
Faker.Modules = {}

function Faker.__loadModule(moduleName: string)
	Faker.Modules[moduleName] = loadstring(game:HttpGet(`https://raw.githubusercontent.com/yj5v/fake-rivals-first-person-models/main/modules/{moduleName}.lua`, true))()
end

Faker.__loadModule("TweenInfos")
Faker.__loadModule("AnimationPlayer")
Faker.__loadModule("AnimationLinker")
