#!/usr/bin/env lua
local file = require 'ext.file'
local class = require 'ext.class'
local table = require 'ext.table'
local string = require 'ext.string'
local tolua = require 'ext.tolua'

local fn, trace = ...
if not fn then error("expected: run.lua <filename>") end
local d = assert(file(fn)):read()
local ls = string.split(d, '\n')

local connchars = string.split('|/-\\*+'):mapi(function(s,i) return i,s end):setmetatable(nil)

local env = _G


local Node = class()

function Node:init(args)
	self.conns = {}
	for k,v in pairs(args) do
		self[k] = v
	end
end

function Node:__tostring()
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

function Node:__concat(o)
	return tostring(self)..tostring(o)
end

function Node:getLuaFunc()
	--[[ using names
	local f = env[self.value]
	--]]
	-- [[ using expressions
	local f = assert(load('return '..self.value, nil, nil, env))()
	--]]
	return assert(f, "failed to find "..self.value)
end

function Node:getFuncArgValues()
	-- if its :something: then idk .. return?
	local args = table()
	if self.conns.up then
		args.n = #self.conns.up
		for i=1,args.n do
			args[i] = self.conns.up[i]:eval()
		end
	end
	return args
end

function Node:eval()
	local args = self:getFuncArgValues()
	if trace then
		print('calling '..self.value)
	end
	local f = self:getLuaFunc()
	return f(args:unpack())
end

local Conn = class(Node)

local Name = class(Node)

-- function arg
local Arg = class(Node)

-- function definition
local Func = class(Node)

-- output of function definition is just returning what gets fed into it
function Func:eval()
	return self:getFuncArgValues():unpack()
end

local Value = class(Node)

function Value:eval()
	return self.value
end

local String = class(Value)

local Number = class(Value)


local op = require 'ext.op'
local opforsym = {
	['+'] = op.add,
	['-'] = op.sub,	-- TODO unm for single-arg
	['*'] = op.mul,
	['/'] = op.div,
	['%'] = op.mod,
	['..'] = op.concat,
	['#'] = op.len,
	['?'] = function(a,b,c) if a then return b else return c end end,
	['&'] = op.band,
	['|'] = op.bor,
	['~'] = op.bnot,
	['^'] = op.bxor,
	['&&'] = op.land,
	['||'] = op.lor,
	['=='] = op.eq,
	['!='] = op.ne,
	['<'] = op.lt,
	['<='] = op.le,
	['>'] = op.gt,
	['>='] = op.ge,
	['<<'] = op.lshift,
	['>>'] = op.rshift,
}
-- TODO arshift, rotate left , rotate right, int-div


local Op = class(Node)

function Op:getLuaFunc()
	return assert(opforsym[self.value], "failed to find op for "..self.value)
end


local nodes = table()
for y=1,#ls do
	local l = ls[y]
	local n = #l
	local x = 1
	
	local function readUntil(close)
		-- read until )
		local k = x+1
		while k <= n do
			local kc = l:sub(k,k)
			if kc == close then
				break
			end
			k = k + 1
		end
		return k, l:sub(x+1,k-1), k-x+1
	end
	
	while x <= n do
		local c = l:sub(x,x)
		if c == ' ' then
		elseif connchars[c] then
			nodes:insert(Conn{
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
			nodes:insert(String{
				value = l:sub(x+1,k-1),
				x = x,
				y = y,
				w = k-x+1,
				h = 1,
			})
			x = k
		elseif c == '(' then
			local k, value, w = readUntil')'
			nodes:insert(Op{
				value = value,
				x = x,
				y = y,
				w = w,
				h = 1,
			})
			x = k
		elseif c == '<' then
			local k, value, w = readUntil'>'
			nodes:insert(Arg{
				value = value,
				x = x,
				y = y,
				w = w,
				h = 1,
			})
			x = k
		elseif c == ':' then
			local k, value, w = readUntil':'
			nodes:insert(Func{
				value = value,
				x = x,
				y = y,
				w = w,
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
			local value = l:sub(x,k)
			local num = tonumber(value)
			local cl = Name
			if num then
				cl = Number
				value = num
			end
			nodes:insert(cl{
				value = value,
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

if trace then
	print'initially found nodes:'
	for i,obj in ipairs(nodes) do
		print(nodes[i])
	end
end



-- btw what about spaces in strings?

local function findat(x, y)
	for _,obj in ipairs(nodes) do
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
		nbfrom.conns[to] = nbfrom.conns[to] or table()
		nbfrom.conns[to]:insert(self)
		self.conns[from] = self.conns[from] or table()
		self.conns[from]:insert(nbfrom)
	end
	local nbto = findat(self.x + dx, self.y + dy)
	if nbto then
		self.conns[to] = self.conns[to] or table()
		self.conns[to]:insert(nbto)
		nbto.conns[from] = nbto.conns[from] or table()
		nbto.conns[from]:insert(self)
	end
end

-- now merge connections
for _,obj in ipairs(nodes) do
	if Conn:isa(obj) then
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
	for i,obj in ipairs(nodes) do
		if not Conn:isa(obj) then
			for side, conns in pairs(obj.conns) do
				local redo
				repeat
--print(i, #conns, conns[1] and conns[1].type)
					redo = false
					for j=#conns,1,-1 do
						local other = conns[j]
						if Conn:isa(other) then
							conns:remove(j)
							if other.conns[side] then
								conns:append(other.conns[side])
								other.conns[side] = nil
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

for i=#nodes,1,-1 do
	local o = nodes[i]
	if Conn:isa(o) then
		nodes:remove(i)
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

if trace then
	print'after merging conns, nodes:'
	for i,obj in ipairs(nodes) do
		print(nodes[i])
	end
end

--now starting with 'done', or a function def ... or 'main' or something ...
-- ... trace left-most and run all those nodes

local function call(node)
	--print'found node'
	local leftmost = table()
	local ns = table{node}
	while #ns > 0 do
		local o = ns:remove(1)
		if o.conns.left then
			ns:append(o.conns.left)
		else
			leftmost:insert(o)
		end
	end
	if trace then
		print'leftmost:'
		for _,l in ipairs(leftmost) do
			print(l)
		end
	end

	local noderesults
	local exec = table(leftmost)
	while #exec > 0 do
		local o = exec:remove(1)
		if o.conns.right then
			exec:append(o.conns.right)
		end
		-- now execute 'o'
		if trace then
			print('executing '..o)
		end
		local results = table.pack(o:eval())
		if o == node then
			noderesults = results
		end
	end
	-- TODO return anything?
	if noderesults then
		return noderesults:unpack()
	end
end

for _,obj in ipairs(nodes) do
	-- TODO for these names, change the type to 'func' or something
	if Func:isa(obj) then
		env[obj.value] = function()
			return call(obj)
		end
	end
end

if env.done then
	env.done()
end
