-- Entry point: lua5.4 tests/lua/run.lua   (run from the resource folder or anywhere)
local here = debug.getinfo(1, 'S').source:sub(2):match('(.*)/lua/run%.lua$') or 'tests'
TEST_ROOT = here
RESOURCE_ROOT = here .. '/..'
dofile(TEST_ROOT .. '/lua/mock_fivem.lua')
HARNESS = dofile(TEST_ROOT .. '/lua/harness.lua')

local suites = { 'test_server.lua', 'test_client.lua' }
local only = arg and arg[1]
for _, file in ipairs(suites) do
    if not only or file:find(only, 1, true) then
        local path = TEST_ROOT .. '/lua/' .. file
        local f = io.open(path, 'r')
        if f then f:close() dofile(path) end
    end
end

local r = HARNESS.results
MOCK.realPrint(('\n%d passed, %d failed'):format(r.passed, r.failed))
os.exit(r.failed == 0 and 0 or 1)
