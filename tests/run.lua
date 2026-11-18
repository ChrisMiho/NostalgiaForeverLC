-- Minimal test runner for the pure-Lua parts of NostalgiaForeverLC.
-- Usage (from repo root):  luajit tests/run.lua   (or lua5.1 tests/run.lua)

package.path = "./?.lua;" .. package.path

local passed, failed = 0, 0
local current = ""

function describe(name, fn)
    current = name
    fn()
end

function it(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print(("FAIL  %s :: %s\n      %s"):format(current, name, tostring(err)))
    end
end

function eq(actual, expected, msg)
    if actual ~= expected then
        error((msg or "") .. " expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

function truthy(v, msg)
    if not v then error((msg or "expected truthy") .. ", got " .. tostring(v), 2) end
end

function falsy(v, msg)
    if v then error((msg or "expected falsy") .. ", got " .. tostring(v), 2) end
end

local specs = { "tests/engine_spec.lua", "tests/data_spec.lua" }
for _, spec in ipairs(specs) do
    local f = io.open(spec, "r")
    if f then
        f:close()
        dofile(spec)
    end
end

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
