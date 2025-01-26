-- This code is ran by LuaJIT + Luarocks, not SM lua. It is used to generate all the meshes for the shapes.

--local lfs = require("luafilesystem")
local json = require("dkjson")

for x = 1, 8, 1 do
    for y = 1, 8, 1 do
        for z = 1, 8, 1 do
            print(x, y, z)
        end
    end
end