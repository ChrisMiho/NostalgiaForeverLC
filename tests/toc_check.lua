-- Fails when Core/Data/UI .lua files on disk and IDontWannaLC.toc disagree.
-- Run from the repo root: luajit tests/toc_check.lua
local listed, onDisk, bad = {}, {}, false

for line in io.lines("IDontWannaLC.toc") do
    line = line:gsub("\r", "")
    if line ~= "" and line:sub(1, 1) ~= "#" then
        listed[(line:gsub("\\", "/"))] = true
    end
end

local p = assert(io.popen("ls Core/*.lua Data/*.lua UI/*.lua"))
for path in p:lines() do onDisk[path] = true end
p:close()

local function sorted(set)
    local t = {}
    for k in pairs(set) do t[#t + 1] = k end
    table.sort(t)
    return t
end

for _, path in ipairs(sorted(onDisk)) do
    if not listed[path] then
        print("toc_check: " .. path .. " not in IDontWannaLC.toc")
        bad = true
    end
end
for _, path in ipairs(sorted(listed)) do
    if path:match("^[^/]+/.*%.lua$") and not onDisk[path] then
        local f = io.open(path, "r")
        if f then f:close() else
            print("toc_check: " .. path .. " listed in IDontWannaLC.toc but missing")
            bad = true
        end
    end
end
os.exit(bad and 1 or 0)
