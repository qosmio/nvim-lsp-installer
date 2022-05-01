local log = require "nvim-lsp-installer.log"
local platform = require "nvim-lsp-installer.platform"
local Result = require "nvim-lsp-installer.core.result"
local spawn = require "nvim-lsp-installer.core.spawn"
local powershell = require "nvim-lsp-installer.core.managers.powershell"

local _HEADERS = {
    ["User-Agent"] = "nvim-lsp-installer (+https://github.com/williamboman/nvim-lsp-installer)",
}

---@param t1 table
---@param t2 table
local function merge_in_place(t1, t2)
    for k, v in pairs(t2) do
        if type(v) == "table" then
            if type(t1[k]) == "table" and not vim.tbl_islist(t1[k]) then
                merge_in_place(t1[k], v)
            else
                t1[k] = v
            end
        else
            t1[k] = v
        end
    end
    return t1
end

---@param t1 table
---@param prog string ('curl','wget','iwr')
local function format_headers(t1, prog)
    local prog_flags = { wget = "--header", curl = "-H", iwr = "" }
    if prog_flags[prog] then
        local res = {}
        for k, v in pairs(t1) do
            if prog == "iwr" then
                res[#res + 1] = ("'%s' = '%s'"):format(k, v)
            else
                res[#res + 1] = prog_flags[prog]
                res[#res + 1] = ("%s: %s"):format(k, v)
            end
        end
        return res
    end
end

---@alias FetchOpts {out_file:string}

---@async
---@param url string @The url to fetch.
---@param opts FetchOpts
local function fetch(url, opts)
    opts = opts or {}
    log.fmt_debug("Fetching URL %s", url)

    local platform_specific = Result.failure()

    if opts.headers then
        merge_in_place(_HEADERS, opts.headers)
    end

    local HEADERS = {
        wget = { format_headers(_HEADERS, "wget") },
        curl = { format_headers(_HEADERS, "curl") },
        iwr = { format_headers(_HEADERS, "iwr") },
    }

    if platform.is_win then
        if opts.out_file then
            platform_specific = powershell.command(
                ([[iwr -Headers @{%s} -UseBasicParsing -Uri %q -OutFile %q;]]):format(table.concat(HEADERS.iwr[1],";"), url, opts.out_file)
            )
        else
            platform_specific = powershell.command(
                ([[Write-Output (iwr -Headers @{%s} -UseBasicParsing -Uri %q).Content;]]):format(table.concat(HEADERS.iwr[1],";"), url)
            )
        end
    end

    return platform_specific
        :recover_catching(function()
            return spawn.wget({ HEADERS.wget[1], "-nv", "-O", opts.out_file or "-", url }):get_or_throw()
        end)
        :recover_catching(function()
            return spawn.curl({ HEADERS.curl[1], "-fsSL", opts.out_file and { "-o", opts.out_file } or vim.NIL, url }):get_or_throw()
        end)
        :map(function(result)
            if opts.out_file then
                return result
            else
                return result.stdout
            end
        end)
end

return fetch
