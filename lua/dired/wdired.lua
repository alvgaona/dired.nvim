-- Writable Dired mode - allows editing filenames directly in the buffer
local fs = require("dired.fs")
local ls = require("dired.ls")
local display = require("dired.display")

local M = {}

-- Store the original state when entering wdired mode
M.original_filenames = {}
M.is_active = false

-- Enter wdired mode - make the dired buffer editable
function M.enter()
    if vim.bo.filetype ~= "dired" then
        vim.notify("Wdired: Can only be used in dired buffers", "error")
        return
    end

    if M.is_active then
        vim.notify("Wdired: Already in wdired mode", "warn")
        return
    end

    local dir = vim.g.current_dired_path
    if not dir then
        vim.notify("Wdired: No current directory", "error")
        return
    end

    -- Get all files in current directory
    local dir_files = ls.fs_entry.get_directory(dir)

    -- Store original filenames with their line numbers
    M.original_filenames = {}

    -- The buffer starts with 2 header lines (directory path and "total used" line)
    local header_lines = 2
    local buf_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

    for line_nr = header_lines + 1, #buf_lines do
        local line = buf_lines[line_nr]
        local filename = display.get_filename_from_listing(line)

        if filename and filename ~= "" and filename ~= "." and filename ~= ".." then
            local file = ls.get_file_by_filename(dir_files, filename)
            if file then
                table.insert(M.original_filenames, {
                    line_nr = line_nr,
                    original_name = filename,
                    original_line = line,
                    file = file,
                })
            end
        end
    end

    -- Make buffer modifiable
    vim.bo.modifiable = true
    vim.bo.readonly = false
    M.is_active = true

    -- Show help message
    vim.notify(
        "Wdired mode enabled. Edit filenames, then use :DiredWdiredFinish to apply or :DiredWdiredAbort to cancel",
        "info"
    )
end

-- Extract filename from a buffer line in wdired mode
-- We reuse the existing display.get_filename_from_listing function
-- which already handles all the edge cases properly
local function extract_filename_from_line(line)
    return display.get_filename_from_listing(line)
end

-- Apply changes - rename files according to buffer edits
function M.finish()
    if not M.is_active then
        vim.notify("Wdired: Not in wdired mode", "warn")
        return
    end

    local buf_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local renames = {}
    local errors = {}

    -- Compare current buffer with original filenames
    for _, entry in ipairs(M.original_filenames) do
        local line_nr = entry.line_nr
        local original_name = entry.original_name
        local current_line = buf_lines[line_nr]

        if not current_line then
            table.insert(errors, string.format("Line %d was deleted", line_nr))
        else
            local new_name = extract_filename_from_line(current_line)

            if new_name ~= original_name then
                -- Validate new filename
                if new_name == "" then
                    table.insert(errors, string.format("Empty filename on line %d", line_nr))
                elseif new_name == "." or new_name == ".." then
                    table.insert(errors, string.format("Invalid filename '%s' on line %d", new_name, line_nr))
                elseif new_name:match("/") then
                    table.insert(errors, string.format("Filename cannot contain '/' on line %d", line_nr))
                else
                    table.insert(renames, {
                        line_nr = line_nr,
                        old_name = original_name,
                        new_name = new_name,
                        old_path = entry.file.filepath,
                        new_path = fs.join_paths(entry.file.parent_dir, new_name),
                    })
                end
            end
        end
    end

    -- Report errors if any
    if #errors > 0 then
        vim.notify("Wdired: Errors found:\n  " .. table.concat(errors, "\n  "), "error")
        return
    end

    -- Check for conflicts
    local new_names = {}
    for _, rename in ipairs(renames) do
        if new_names[rename.new_name] then
            vim.notify(
                string.format(
                    "Wdired: Duplicate filename '%s' (lines %d and %d)",
                    rename.new_name,
                    new_names[rename.new_name],
                    rename.line_nr
                ),
                "error"
            )
            return
        end
        new_names[rename.new_name] = rename.line_nr

        -- Check if target already exists (and is not being renamed away)
        if fs.file_exists(rename.new_path) then
            local is_rename_target = false
            for _, other_rename in ipairs(renames) do
                if other_rename.old_path == rename.new_path then
                    is_rename_target = true
                    break
                end
            end

            if not is_rename_target then
                vim.notify(
                    string.format("Wdired: File '%s' already exists", rename.new_name),
                    "error"
                )
                return
            end
        end
    end

    -- Perform renames
    if #renames == 0 then
        vim.notify("Wdired: No changes to apply", "info")
        M.abort()
        return
    end

    -- Show summary
    vim.notify(string.format("Wdired: Renaming %d file(s)...", #renames), "info")

    local rename_count = 0
    for _, rename in ipairs(renames) do
        local success = vim.loop.fs_rename(rename.old_path, rename.new_path)
        if success then
            rename_count = rename_count + 1
        else
            vim.notify(
                string.format(
                    "Wdired: Failed to rename '%s' to '%s'",
                    rename.old_name,
                    rename.new_name
                ),
                "error"
            )
        end
    end

    -- Exit wdired mode and refresh
    M.is_active = false
    M.original_filenames = {}
    vim.bo.modifiable = false

    -- Refresh the dired buffer
    display.render(vim.g.current_dired_path)

    vim.notify(string.format("Wdired: Successfully renamed %d file(s)", rename_count), "info")
end

-- Abort wdired mode without applying changes
function M.abort()
    if not M.is_active then
        vim.notify("Wdired: Not in wdired mode", "warn")
        return
    end

    M.is_active = false
    M.original_filenames = {}
    vim.bo.modifiable = false

    -- Refresh the dired buffer to restore original state
    display.render(vim.g.current_dired_path)

    vim.notify("Wdired: Aborted, no changes applied", "info")
end

return M
