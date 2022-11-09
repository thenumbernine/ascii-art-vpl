#!/usr/bin/env lua
local file = require 'ext.file'
local class = require 'ext.class'
local table = require 'ext.table'
local string = require 'ext.string'
local tolua = require 'ext.tolua'
local fn = ...
if not fn then error("expected: run.lua <filename>") end
local d = assert(file(fn)):read()
local ls = string.split(d, '\n')

local connchars = string.split('|/-\\*+'):mapi(function(s,i) return i,s end):setmetatable(nil)

local env = _G

local Object = class()

function Object:init(args)
	for k,v in pairs(args) do
		self[k] = v
	end
end

function Object:__tostring()
	local o = table(self)
	local conns = table(o.conns)
	o.conns = nil
	local s = table()
	for _,side in ipairs(table.keys(conns)) do
		conns[side] = table(conns[side])
		for i=1,#conns[side] do
			conns[side][i] = conns[side][i].value
		end
		s:insert(side..'='..conns[side]:concat',')
	end
	o.conns = s:concat'; '
	return tolua(o)
end

function Object:__concat(o)
	return tostring(self)..tostring(o)
end

function Object:eval()
	if self.type == 'string' then
		return self.value
	end

	-- if its :something: then idk .. return?

	local args = table()
	local n
	if self.conns and self.conns.up then
		n = #self.conns.up
		for i=1,n do
			args[i] = self.conns.up[i]:eval()
		end
	end
	
	if self.value:match'^:(.*):$' then
		return args:unpack(1,n)
	end

	local f = assert(env[self.value], "failed to find "..self.value)
	return f(args:unpack(1,n))
end

local objs = table()
for y=1,#ls do
	local l = ls[y]
	local n = #l
	local x = 1
	while x <= n do
		local c = l:sub(x,x)
		if c == ' ' then
		elseif connchars[c] then
			objs:insert(Object{
				type = 'conn',
				value = c,
				x = x,
				y = y,
				w = 1,
				h = 1,
			})
		elseif c == '"' then
			-- read a string
			local k = x+1
			while k <= n do
				local kc = l:sub(k,k)
				if kc == '\\' then 
					k = k + 1
				elseif kc == '"' then
					break
				end
				k = k + 1
			end
			objs:insert(Object{
				type = 'string',
				value = l:sub(x+1,k-1),
				x = x,
				y = y,
				w = k-x+1,
				h = 1,
			})
			x = k
		else
			-- read until non-name token
			local k = x+1
			while true do
				local kc = l:sub(k,k)
				if kc == ' ' or connchars[kc] then
					k = k - 1
					break
				end
				k = k + 1
				if k > n then 
					k = k - 1
					break 
				end
			end
			objs:insert(Object{
				type = 'name',
				value = l:sub(x,k),
				x = x,
				y = y,
				w = k-x+1,
				h = 1,
			})
			x = k
		end
		x = x + 1
	end
end

-- btw what about spaces in strings?

local function findat(x, y)
	for _,obj in ipairs(objs) do
		if obj.x <= x 
		and obj.y <= y 
		and x <= obj.x + obj.w - 1
		and y <= obj.y + obj.h - 1
		then
			return obj
		end
	end
end

local function connect(self, from, to, dx, dy)
	-- left / above
	local nbfrom = findat(self.x - dx, self.y - dy)
	if nbfrom then
		nbfrom.conns = nbfrom.conns or {}
		nbfrom.conns[to] = nbfrom.conns[to] or table()
		nbfrom.conns[to]:insert(self)
		self.conns = self.conns or {}
		self.conns[from] = self.conns[from] or table()
		self.conns[from]:insert(nbfrom)
	end
	local nbto = findat(self.x + dx, self.y + dy)
	if nbto then
		self.conns = self.conns or {}
		self.conns[to] = self.conns[to] or table()
		self.conns[to]:insert(nbto)
		nbto.conns = nbto.conns or {}
		nbto.conns[from] = nbto.conns[from] or table()
		nbto.conns[from]:insert(self)
	end
end

-- now merge connections
for _,obj in ipairs(objs) do
	if obj.type == 'conn' then
		-- connect it
		if obj.value == '|' then
			connect(obj, 'up', 'down', 0, 1)
		elseif obj.value == '-' then
			connect(obj, 'left', 'right', 1, 0)
		--elseif obj.value == '/' then	-- hmm
		--elseif obj.value == '\\' then
		elseif obj.value == '+' then
			-- TODO
		elseif obj.value == '*' then
			-- TODO
		else
			error("unknown connection")
		end
	end
end

-- now collapse edges
local merged
repeat
	merged = false
	for i,obj in ipairs(objs) do
		if obj.type ~= 'conn' then
			for side, conns in pairs(obj.conns) do
				local redo
				repeat
					print(i, #conns, conns[1].type)
					redo = false
					for j=#conns,1,-1 do
						local other = conns[j]
						if other.type == 'conn' then
							conns:remove(j)
							if other.conns then
								if other.conns[side] then
									conns:append(other.conns[side])
									other.conns[side] = nil
								end
							end
							merged = true
							redo = true
							break
						end
					end
				until not redo
			end
		end
	end
until not merged

for i=#objs,1,-1 do
	local o = objs[i]
	if o.type == 'conn' then
		objs:remove(i)
	else
		-- sort conns.up .down by x
		-- sort conns.left .right by y
		for _,side in pairs(table.keys(o.conns)) do
			local sortfield
			if side == 'up' or side == 'down' then
				sortfield = 'x'
			elseif side == 'left' or side == 'right' then
				sortfield = 'y'
			else
				error("unknown connection direction")
			end
			table.sort(o.conns[side], function(a,b)
				return a[sortfield] < b[sortfield]
			end)
		end
	end
end

-- [[
print'objs:'
for i,obj in ipairs(objs) do
	print(objs[i])
end
--]]

--now starting with 'done', or a function def ... or 'main' or something ...
-- ... trace left-most and run all those nodes

local done = select(2, objs:find(nil, function(o) 
	return o.type == 'name' and o.value == ':done:' 
end))
print('done', done)
local trace
if done then
	-- executing ":done:" function ...

	--print'found done'
	local leftmost = table()
	local ns = table{done}
	while #ns > 0 do
		local o = ns:remove(1)
		if o.conns and o.conns.left then
			ns:append(o.conns.left)
		else
			leftmost:insert(o)
		end
	end
	print'leftmost:'
	for _,l in ipairs(leftmost) do
		print(l)
	end

	local exec = table(leftmost)
	while #exec > 0 do
		local o = exec:remove(1)
		if o.conns and o.conns.right then
			exec:append(o.conns.right)
		end
		-- now execute 'o'
		if trace then
			print('executing '..o)
		end
		o:eval()
	end
end
