local M = {}

local sort = require("dired.sort")
local util = require("dired.utils")

local CONFIG_SPEC = {
    show_colors = {
        default = true,
        check = function(val)
            if type(val) ~= "boolean" then
                return "Must be boolean, instead received " .. type(val)
            end
        end,
    },
    show_dot_dirs = {
        default = true,
        check = function(val)
            if type(val) ~= "boolean" then
                return "Must be boolean, instead received " .. type(val)
            end
        end,
    },
    show_hidden = {
        default = true,
        check = function(val)
            if type(val) ~= "boolean" then
                return "Must be boolean, instead received " .. type(val)
            end
        end,
    },
    show_icons = {
        default = false,
        check = function(val)
            if type(val) ~= "boolean" then
                return "Must be boolean, instead received " .. type(val)
            end
        end,
    },
    hide_details = {
        default = false,
        check = function(val)
            if type(val) ~= "boolean" then
                return "Must be boolean, instead received " .. type(val)
            end
        end,
    },
    -- control mouse/preview UX
    enable_click_preview = {
        -- highlights the current line on single left-click
        default = true,
        check = function(val)
            if type(val) ~= "boolean" then
                return "Must be boolean, instead received " .. type(val)
            end
        end,
    },
    enable_double_click_open = {
        -- opens file/dir on double left-click
        default = true,
        check = function(val)
            if type(val) ~= "boolean" then
                return "Must be boolean, instead received " .. type(val)
            end
        end,
    },
    path_separator = {
        default = "/",
        check = function(val)
            if type(val) ~= "string" then
                return "Must be string of length 1, instead received " .. type(val)
            end
            if #val ~= 1 then
                return "Must be string of length 1, instead received string of length " .. tostring(#val)
            end
        end,
    },
    show_banner = {
        default = false,
        check = function(val)
            if type(val) ~= "boolean" then
                return "Must be boolean, instead received " .. type(val)
            end
        end,
    },
    sort_order = {
        default = "name",
        check = function(val)
            if val == "name" then
                return sort.sort_by_name
            elseif val == "dirs" then
                return sort.sort_by_dirs
            elseif val == "date" then
                return sort.sort_by_date
            elseif type(val) == "function" then
                return val
            else
                return 'Must be one of {"name", "dirs", "date", or function}'
            end
        end,
    },
    keybinds = {
        default = {
            dired_enter = "<CR>",
            dired_back = "_",
            dired_up = "-",
            dired_rename = "R",
            dired_create = "d",
            dired_delete = "D",
            dired_delete_range = "D",
            dired_duplicate = "Y",
            dired_copy = "C",
            dired_copy_range = "C",
            dired_copy_marked = "MC",
            dired_move = "X",
            dired_move_range = "X",
            dired_move_marked = "MX",
            dired_paste = "P",
            dired_mark = "M",
            dired_mark_range = "M",
            dired_delete_marked = "MD",
            dired_shell_cmd = "!",
            dired_shell_cmd_marked = "&",
            dired_toggle_hidden = ".",
            dired_toggle_sort_order = ",",
            dired_toggle_colors = "c",
            dired_toggle_icons = "*",
            dired_toggle_hide_details = "(",
            dired_quit = "q",
            dired_wdired_enter = "E",
            dired_wdired_finish = "<C-c><C-c>",
            dired_wdired_abort = "<C-c><C-k>",
        },
        check = function()
            return {}
        end,
    },
    colors = {
        default = {
            -- Use current theme groups via links; fg/bg/gui are optional and omitted
            DiredDimText = { link = { "Comment" } },
            DiredDirectoryName = { link = { "Directory", "Title" } },
            DiredDotfile = { link = { "Comment", "NonText" } },
            DiredFadeText1 = { link = { "Comment" } },
            DiredFadeText2 = { link = { "NonText", "Comment" } },
            DiredSize = { link = { "Number", "Normal" } },
            DiredUsername = { link = { "Identifier", "Title" } },
            DiredMonth = { link = { "Normal", "Title" } },
            DiredDay = { link = { "Normal", "Title" } },
            DiredFileName = { link = { "Normal" } },
            DiredFileSuid = { link = { "Error", "ErrorMsg", "WarningMsg" } },
            DiredNormal = { link = { "Normal" } },
            DiredNormalBold = { link = { "Normal" } },
            DiredSymbolicLink = { link = { "Special", "Type", "Identifier" } },
            DiredBrokenLink = { link = { "Error", "ErrorMsg" } },
            DiredSymbolicLinkTarget = { link = { "String", "Special" } },
            DiredBrokenLinkTarget = { link = { "WarningMsg", "ErrorMsg" } },
            DiredFileExecutable = { link = { "Function", "Statement", "Type" } },
            DiredMarkedFile = { link = { "Visual", "Search" } },
            -- Distinct color for single-click preview; avoid marked file color
            DiredPreview = { link = { "CursorLine", "PmenuSel", "IncSearch" } },
            DiredCopyFile = { link = { "DiffChange", "Type" } },
            DiredMoveFile = { link = { "DiffDelete", "WarningMsg" } },
        },
        check = function(cfg)
            for k, v in pairs(cfg) do
                if v["link"] == nil then
                    return "Must contain a link element for each highlight group"
                end
                if type(v["link"]) ~= "table" then
                    return "link must be a table of highlight groups for " .. tostring(k)
                end
                -- bg/fg/gui are optional; if provided, must be strings
                for _, key in ipairs({ "bg", "fg", "gui" }) do
                    if v[key] ~= nil and type(v[key]) ~= "string" then
                        return key .. " must be a string when provided for " .. tostring(k)
                    end
                end
            end
        end,
    },
}

local user_config = {}

function M.update(opts)
    local errs = {}
    for opt_name, spec in pairs(CONFIG_SPEC) do
        local usr_val = opts[opt_name]
        if usr_val == nil then
            user_config[opt_name] = nil
        else
            -- create keybind config of user + defaults
            if opt_name == "keybinds" then
                user_config.keybinds = util.shallowcopy(CONFIG_SPEC.keybinds.default)
                local ret = spec.check(usr_val)
                if type(ret) == "string" then
                    table.insert(errs, string.format("`%s` %s", opt_name, ret))
                else
                    for key, val in pairs(usr_val) do
                        user_config.keybinds[key] = val
                    end
                end

            -- create colors config of user + defaults
            elseif opt_name == "colors" then
                user_config.colors = util.shallowcopy(CONFIG_SPEC.colors.default)
                local ret = spec.check(usr_val)
                if type(ret) == "string" then
                    table.insert(errs, string.format("`%s` %s", opt_name, ret))
                else
                    for key, val in pairs(usr_val) do
                        user_config.colors[key] = val
                    end
                end
            elseif opt_name == "sort_order" then
                local ret = spec.check(usr_val)
                if type(ret) == "string" then
                    table.insert(errs, string.format("`%s` %s", opt_name, ret))
                else
                    user_config[opt_name] = ret
                end

            -- handle rest of the config that are not tables
            else
                local ret = spec.check(usr_val)
                if type(ret) == "string" then
                    table.insert(errs, string.format("`%s` %s", opt_name, ret))
                else
                    user_config[opt_name] = usr_val
                end
            end
        end
    end

    local unrecognised_opts = {}
    for key, _ in pairs(opts) do
        if CONFIG_SPEC[key] == nil then
            table.insert(unrecognised_opts, string.format("`%s`", key))
        end
    end

    if #unrecognised_opts > 0 then
        table.insert(errs, table.concat(unrecognised_opts, ", ") .. "not recognised")
    end

    return errs
end

function M.get(opt)
    if CONFIG_SPEC[opt] == nil then
        error("Unrecognised Option: " .. opt)
    end
    if user_config[opt] == nil then
        return CONFIG_SPEC[opt].default
    else
        return user_config[opt]
    end
end

function M.get_sort_order(val)
    if val == "name" then
        return sort.sort_by_name
    elseif val == "dirs" then
        return sort.sort_by_dirs
    elseif val == "date" then
        return sort.sort_by_date
    elseif type(val) == "function" then
        return val
    else
        return nil
    end
end

function M.get_next_sort_order()
    local current = vim.g.dired_sort_order
    local sorting_functions = { "name", "date", "dirs" }
    local current_idx = 1

    for i, str in ipairs(sorting_functions) do
        if str == current then
            current_idx = i
            break
        end
    end

    local next_idx = current_idx + 1
    if next_idx > #sorting_functions then
        next_idx = 1
    end

    return sorting_functions[next_idx]
end

return M
