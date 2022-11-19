#!/usr/bin/env lua
require 'ext'
local function getoutput(cmd)
	local out = io.readproc(cmd):trim()
	print(out)
	return out
end
assert(getoutput('./run.lua func') == '2')
assert(getoutput('./run.lua func_2') == '2')
assert(getoutput('./run.lua func_3') == '1\t-1')
assert(getoutput('./run.lua hello_world') == 'hello world')
assert(getoutput('./run.lua hello_world_2') == 'hello world')
assert(getoutput('./run.lua hello_world_3') == 'hello\tworld')
assert(getoutput('./run.lua math') == 'two plus two is 4')
assert(getoutput('./run.lua math_2') == '12.182493960703')
