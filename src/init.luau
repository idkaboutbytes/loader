--[=[
	@class loader
]=]

const ReplicatedStorage = game:GetService("ReplicatedStorage")
const RunService = game:GetService("RunService")
const ServerScriptService = game:GetService("ServerScriptService")
const ServerStorage = game:GetService("ServerStorage")
const StarterPlayer = game:GetService("StarterPlayer")

const IsServer = RunService:IsServer()

const DependencyNameCache = {} -- [string] = ModuleScript
const DependencySourceCache = {} -- [string | Instance] = any

const Loader = {}
Loader.ClassName = "Loader"

type PackageInfo = {
	Author: string,
	Name: string,
	Version: string,
}

--[=[
	Checks if a package name follows Wally package format.
	@private
]=]
@checked const function isWallyPackage(packageInfo: PackageInfo): boolean
	return (packageInfo.Author ~= nil and packageInfo.Name ~= nil and packageInfo.Version ~= nil)
end

--[=[
	Parses Wally package information from a package name.
	@private
]=]
@checked const function wallyPackageInfo(name: string): PackageInfo?
	const versionSplit = name:split("@")
	const packageDetails = versionSplit[1]:split("_")

	const author = packageDetails[1]
	const packageName = packageDetails[2]
	const ver = versionSplit[2]

	const packageInfo: PackageInfo = {
		Author = author,
		Name = packageName,
		Version = ver,
	}

	if not isWallyPackage(packageInfo) then
		return nil
	end

	return packageInfo
end

--[=[
	Recursively searches a directory for a module by name.
	@private
]=]
@checked const function recurseDirectory(folder: Instance, looking: string)
	return coroutine.wrap(function()
		for _, child in folder:GetChildren() do
			if child.Name == looking then
				coroutine.yield(child)
			end

			for directory in recurseDirectory(child, looking) do
				coroutine.yield(directory)
			end
		end
	end)
end

--[=[
	Iterates through a Wally package folder to find a specific package.
	@private
]=]
@checked const function iterateWallyFolder(folder: Instance, lookingFor: string)
	local packageName = lookingFor

	return coroutine.wrap(function()
		for _, package in folder:GetChildren() do
			const packageInfo = wallyPackageInfo(package.Name)

			if packageInfo and packageInfo.Name == lookingFor:lower() then
				packageName = packageInfo.Name
			end

			if package.Name == lookingFor then
				coroutine.yield(package)
			end

			for child in recurseDirectory(package, packageName) do
				coroutine.yield(child)
			end
		end
	end)
end

--[=[
	Searches package folders for a specific module.
	@private
]=]
@checked const function searchPackagesForDependency(packageFolder: Instance, lookingFor: string): ModuleScript?
	local dependency = nil :: ModuleScript?

	for package in iterateWallyFolder(packageFolder, lookingFor) do
		if package.Name:lower() ~= lookingFor:lower() then
			continue
		end

		if not package:IsA("ModuleScript") then
			continue
		end

		dependency = package
	end

	return dependency
end

@checked const function normalizePackageRoots(first: Instance, ...: Instance): { Instance }
	assert(typeof(first) == "Instance", "Bad packages")

	const roots = { first, ... }
	for index, item in ipairs(roots) do
		assert(typeof(item) == "Instance", string.format("Bad packages at index %d", index))
	end

	return roots
end

--[=[
	Requires a module (with caching)
	@private
]=]
@checked const function instanceDependencySearch(dependency: ModuleScript): any
	if DependencySourceCache[dependency] ~= nil then
		return DependencySourceCache[dependency]
	end

	const ok, package = pcall(require, dependency)
	if not ok then
		error(string.format("[Loader] Failed to require module: %s", dependency:GetFullName()))
	end

	const name = dependency.Name
	if name:match("Service$") and package.ServerOnly and package.ServerOnly == true then
		const oldParent = dependency.Parent :: Instance
		local servicesFolder = ServerScriptService:FindFirstChild("Services")

		if not servicesFolder then
			servicesFolder = Instance.new("Folder")
			servicesFolder.Name = "Services"
			servicesFolder.Parent = ServerScriptService
		end

		if oldParent ~= servicesFolder then
			dependency.Parent = servicesFolder

			if #oldParent:GetChildren() == 0 then
				oldParent:Destroy()
			end
		end

		if dependency.Parent ~= servicesFolder then
			dependency.Parent = servicesFolder
		end
	end

	DependencySourceCache[dependency] = package
	return package
end

--[=[
	Finds a ModuleScript from a root
	@private
]=]
@checked const function pathDependencySearch(packageSource: Instance, dependencyName: string)
	const cached = DependencyNameCache[dependencyName]
	if cached and cached.Parent then
		return cached
	end

	const child = packageSource:FindFirstChild(dependencyName)
	if child and child:IsA("ModuleScript") then
		DependencyNameCache[dependencyName] = child
		return child
	end

	const found = searchPackagesForDependency(packageSource, dependencyName)
	if found then
		DependencyNameCache[dependencyName] = found
		return found
	end

	return nil
end

--[=[
	Resolves and requires a dependency
	@private
]=]
@checked const function fullDependencySearch(packageRoots: { Instance }, dependencyNameOrPackage: any): any
	if typeof(dependencyNameOrPackage) == "Instance" then
		return instanceDependencySearch(dependencyNameOrPackage :: ModuleScript)
	end

	const dependencyName = dependencyNameOrPackage
	if DependencySourceCache[dependencyName] ~= nil then
		return DependencySourceCache[dependencyName]
	end

	const cachedModule = DependencyNameCache[dependencyName]
	if cachedModule and cachedModule.Parent then
		return instanceDependencySearch(cachedModule)
	end

	for _, root in packageRoots do
		const moduleScript = pathDependencySearch(root, dependencyName)

		if moduleScript then
			const result = instanceDependencySearch(moduleScript)
			DependencySourceCache[dependencyName] = result
			return result
		end
	end

	error(string.format("[Loader] Failed to resolve dependency: %s", tostring(dependencyName)))
end

--[=[
	Loads a module resolver

	@within Loader
	@param ... Instance
	@return (string | Instance) -> any
]=]
@checked
function Loader.load(...: Instance?): (any) -> any
	local packageRoots: { Instance }

	if (...) == nil then
		packageRoots = {
			ReplicatedStorage,
			StarterPlayer,
		}

		if IsServer then
			table.insert(packageRoots, ServerScriptService)
			table.insert(packageRoots, ServerStorage)
		end
	else
		packageRoots = normalizePackageRoots(ReplicatedStorage, ... :: Instance)
	end

	return function(dependencyNameOrPackage: any)
		return fullDependencySearch(packageRoots, dependencyNameOrPackage)
	end
end

return Loader
