--[[
	@Dev_Bas
	Token v2.0.2:
	A typed roblox module for generate token to represent an uniqueness.
]]

--!native
--!optimize 2

local HttpService = game:GetService("HttpService")
local GenerateGUID = HttpService.GenerateGUID
local GlobalRandomizer = Random.new()
local NextInteger = GlobalRandomizer.NextInteger

--[=[
	class Token
]=]
local Token = {}
Token.__index = Token

--[=[
	Returns a new token generator using an optional seed.
	Seed number must be in range [-9007199254740991, 9007199254740991]. (53 bit integer)
<strong>
	@return Token
</strong><p><em>--Style: Moonwave Documentation</em>
]=]
function Token.new(seed: number?)
	return setmetatable({
		Randomizer = Random.new(seed)	
	}, Token)
end

type TokenBase = ("Base256ASCII" | "Base94JSONSAFE" | "Base64URL" | "Hex" | "GUID")

function Token.isbase(token: string, tokenBase: TokenBase): boolean
	if tokenBase == "Hex" then
		return string.find(token, "^[0-9A-Fa-f]+$") ~= nil
	elseif tokenBase == "GUID" then
		return string.find(token, "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
	elseif tokenBase == "Base64URL" then
		return string.find(token, "^[A-Za-z0-9%-_]+$") ~= nil
	elseif tokenBase == "Base94JSONSAFE" then
		return string.find(token, "^[0-9a-zA-Z!#$%%&'()*+,-./:;<=>?@%[%]^_`{|}~"..string.char(127).."]+$") ~= nil
	elseif tokenBase == "Base256ASCII" then 
		return true -- since every text character, emoji based from ascii fundamental level.
	end
	
	return false
end

--[=[
	Returns a GUID string. (HttpService optimized)
	Uniqueness is 2^128 possibility. (128 bit)
<strong>
	@return string --token GUID
</strong><p><em>--Style: Moonwave Documentation</em>
]=]
function Token.guid()
	return GenerateGUID(HttpService, false)
end

type Token = typeof(Token.new())

local STRING_CACHES = table.create(16)

--- Takes an array of bytes and builds a string out of it.
--- Uses `7997` byte chunks to make the string, which ends up being very fast.
local function stringBuilder(input: {number}, length: number?): string
	local inputLength = if length then math.min(#input, length) else #input
	
	for i = 1, inputLength, 7997 do
		local j = math.min(i + 7996, inputLength)
		table.insert(STRING_CACHES, string.char(table.unpack(input, i, j)))
	end

	local blockOfString = table.concat(STRING_CACHES)
	table.clear(STRING_CACHES)

	return blockOfString
end

local blockBase256ASCII = table.create(32, 0)

--[=[
	Returns a random Base256ASCII string.
	If the method were call with no token generator, it'll using global token generator by default.
	-- Useful for case, attribute use.
	-- Avoid for case, json codec, datastore serdes use.
<strong>
	@param length: number --Uniqueness is (256 ^ length) possibility.

	@return string --token Base256ASCII
</strong><p><em>--Style: Moonwave Documentation</em>
]=]
function Token:NextBase256ASCII(length: number)
	local self = self :: Token

	local Randomizer = self.Randomizer or GlobalRandomizer
	
	for i = 1, length do
		blockBase256ASCII[i] = NextInteger(Randomizer, 0, 255)
	end
	
	return stringBuilder(blockBase256ASCII, length)
end

local blockBase94JSONSAFE = table.create(16)
local BASE_94_JSONSAFE_CHARACTERS = {
	"0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
	"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p",
	"q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
	"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P",
	"Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
	"!", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/", ":",
	";", "<", "=", ">", "?", "@", "[", "]", "^", "_", "`", "{", "|", "}", "~",
	string.char(127)
}

--[=[
	Returns a random Base94JSONSAFE string.
	If the method were call with no token generator, it'll using global token generator by default.
	-- Useful for case, json codec, datastore serdes use.
	-- Not recommend for case, redeem code use hard to writing for human.
<strong>
	@param length: number --Uniqueness is (94 ^ length) possibility.

	@return string --token Base94JSONSAFE
</strong><p><em>--Style: Moonwave Documentation</em>
]=]
function Token:NextBase94JSONSAFE(length: number)
	local self = self :: Token

	local Randomizer = self.Randomizer or GlobalRandomizer
	
	for i = 1, length do
		local pointer = NextInteger(Randomizer, 1, 93)
		blockBase94JSONSAFE[i] = BASE_94_JSONSAFE_CHARACTERS[pointer]
	end
	
	local blockOfString = table.concat(blockBase94JSONSAFE)
	table.clear(blockBase94JSONSAFE)

	return blockOfString
end

local blockBase64URL = table.create(16)
local BASE_64_URL_CHARACTERS = {
	"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P",
	"Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "a", "b", "c", "d", "e", "f",
	"g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v",
	"w", "x", "y", "z", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "-", "_"
}

--[=[
	Returns a random Base64URL string.
	If the method were call with no token generator, it'll using global token generator by default.
	-- Useful for case, general use good balance between easy to write and uniqueness.
<strong>
	@param length: number --Uniqueness is (64 ^ length) possibility.

	@return string --token Base64URL
</strong><p><em>--Style: Moonwave Documentation</em>
]=]
function Token:NextBase64URL(length: number)
	local self = self :: Token
	local Randomizer = self.Randomizer or GlobalRandomizer
	
	for i = 1, length do
		local pointer = NextInteger(Randomizer, 1, 64)
		blockBase64URL[i] = BASE_64_URL_CHARACTERS[pointer]
	end
	
	local blockOfString = table.concat(blockBase64URL)
	table.clear(blockBase64URL)
	
	return blockOfString
end

local blockOf16C15 = table.create(16)
local min16C15, max16C15 = 16 ^ (15 - 1) - 1, 16 ^ 15 - 1 
--- update table reuse, extend to be C15.
--- since NextInteger can still random correctly and not pass the breaking point which is >9223372036854775000.
local function process16C15(Randomizer: Random, length: number): {number}
	local iteration = length // 15
	
	table.clear(blockOf16C15)
	
	for i = 1, iteration do
		blockOf16C15[i] = NextInteger(Randomizer, min16C15, max16C15) -- 13
	end
	
	local remainder = length % 15
	
	if remainder > 0 then
		blockOf16C15[iteration + 1] = NextInteger(Randomizer, 16 ^ (remainder - 1) - 1, 16 ^ remainder - 1)
	end
	
	return blockOf16C15
end

--- Takes an array of bytes and builds a string out of it.
--- Uses `7997` byte chunks to make the string, which ends up being very fast.
local function stringBuilderHexBlock16C15(input: {number}): string
	local inputLength = #input
	
	for i = 1, inputLength, 7997 do
		local j = math.min(i + 7996, inputLength)
		local alloc = (j - i) + 1
		
		table.insert(STRING_CACHES, string.format(string.rep([[%x]], alloc), table.unpack(input, i, j)))
	end
	
	local blockOfString = table.concat(STRING_CACHES)
	table.clear(STRING_CACHES)
	
	return blockOfString
end

--[=[
	Returns a random Hex string.
	If the method were call with no token generator, it'll using global token generator by default.
<strong>
	@param length: number --Uniqueness is (16 ^ length) possibility.

	@return string --token Hex
</strong><p><em>--Style: Moonwave Documentation</em>
]=]
function Token:NextHex(length: number)	
	local self = self :: Token
	local Randomizer = self.Randomizer or GlobalRandomizer
	local blockOf16C13 = process16C15(Randomizer, length)
	
	return stringBuilderHexBlock16C15(blockOf16C13)
end

--[=[
	Returns a new token object with the same state as the original.
<strong>
	@return Token
</strong><p><em>--Style: Moonwave Documentation</em>
]=]
function Token:Clone()
	local self = self :: Token
	local newTokenObject = table.clone(self)
	
	newTokenObject.Randomizer = typeof(self.Randomizer) == "Random" and self.Randomizer:Clone() or nil
	
	return setmetatable(newTokenObject, Token)
end

return Token