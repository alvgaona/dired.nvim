-- writable dired mode - allows editing filenames directly in the buffer
local fs = require("dired.fs")
local ls = require("dired.ls")
local display = require("dired.display")
local marker = require("dired.marker")

local M = {}

-- store the original state when entering wdired mode
M.original_filenames = {}
M.is_active = false

-- enter wdired mode - make the dired buffer editable
function M.enter()
    if vim.bo.filetype ~= "dired" then
        vim.notify("Wdired: Can only be used in dired buffers", vim.log.levels.ERROR)
        return
    end

    if M.is_active then
        vim.notify("Wdired: Already in wdired mode", vim.log.levels.WARN)
        return
    end

    local dir = vim.g.current_dired_path
    if not dir then
        vim.notify("Wdired: No current directory", vim.log.levels.ERROR)
        return
    end

    -- get all files in current directory
    local dir_files = ls.fs_entry.get_directory(dir)

    -- store original filenames with their line numbers
    M.original_filenames = {}

    -- the buffer starts with 2 header lines (directory path and "total used" line)
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

    -- make buffer modifiable
    vim.bo.modifiable = true
    vim.bo.readonly = false
    M.is_active = true

    -- show help message
    vim.notify("Wdired mode: <C-c><C-c> to finish, <C-c><C-k> to cancel", vim.log.levels.INFO)
end

-- extract filename from a buffer line in wdired mode
local function extract_filename_from_line(line)
    return display.get_filename_from_listing(line)
end

-- validate that only the filename portion of a line was changed
-- returns: is_valid, new_filename
local function validate_line_change(original_line, current_line, original_filename)
    -- if lines are identical, no change
    if original_line == current_line then
        return true, original_filename
    end

    -- get the new filename from the modified line
    local new_filename = extract_filename_from_line(current_line)

    -- reconstruct what the line should look like with the new filename
    -- by replacing only the filename portion in the original line
    local expected_line =
        original_line:gsub(vim.pesc(original_filename) .. "$", vim.pesc(new_filename))

    -- check if the current line matches what we expect
    -- (only filename changed, nothing else)
    if current_line == expected_line then
        return true, new_filename
    else
        -- something other than the filename was modified
        return false, nil
    end
end

-- apply changes - rename files according to buffer edits
function M.finish()
    if not M.is_active then
        vim.notify("Wdired: Not in wdired mode", vim.log.levels.WARN)
        return
    end

    local buf_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local renames = {}
    local errors = {}

    -- validate header lines weren't modified (lines 1-2)
    local header_lines = 2
    if #buf_lines < header_lines then
        vim.notify("Wdired: Header lines were deleted", vim.log.levels.ERROR)
        return
    end

    -- detect line reordering by checking if any original filename appears at wrong line
    local original_filenames_map = {} -- map filename to original line_nr
    for _, entry in ipairs(M.original_filenames) do
        original_filenames_map[entry.original_name] = entry.line_nr
    end

    for _, entry in ipairs(M.original_filenames) do
        local current_line = buf_lines[entry.line_nr]
        if current_line then
            local current_filename = extract_filename_from_line(current_line)
            -- if current filename is from our original list but at wrong line, it was reordered
            if current_filename and original_filenames_map[current_filename] then
                if original_filenames_map[current_filename] ~= entry.line_nr then
                    vim.notify(
                        string.format(
                            "Wdired: Line reordering detected. '%s' moved from line %d to %d. Only rename files, do not reorder lines.",
                            current_filename,
                            original_filenames_map[current_filename],
                            entry.line_nr
                        ),
                        vim.log.levels.ERROR
                    )
                    return
                end
            end
        end
    end

    -- compare current buffer with original filenames
    for _, entry in ipairs(M.original_filenames) do
        local line_nr = entry.line_nr
        local original_name = entry.original_name
        local original_line = entry.original_line
        local current_line = buf_lines[line_nr]

        if not current_line then
            table.insert(errors, string.format("Line %d was deleted", line_nr))
        else
            -- validate that only the filename was changed
            local is_valid, new_name =
                validate_line_change(original_line, current_line, original_name)

            if not is_valid then
                table.insert(
                    errors,
                    string.format(
                        "Line %d: Modified non-filename content. Only filenames can be edited in wdired mode.",
                        line_nr
                    )
                )
            elseif new_name ~= original_name then
                -- validate new filename
                if new_name == "" then
                    table.insert(errors, string.format("Empty filename on line %d", line_nr))
                elseif new_name == "." or new_name == ".." then
                    table.insert(
                        errors,
                        string.format("Invalid filename '%s' on line %d", new_name, line_nr)
                    )
                elseif new_name:match("/") then
                    table.insert(
                        errors,
                        string.format("Filename cannot contain '/' on line %d", line_nr)
                    )
                elseif new_name:match("\n") or new_name:match("\r") then
                    table.insert(
                        errors,
                        string.format("Filename cannot contain newlines on line %d", line_nr)
                    )
                elseif new_name:match("\0") then
                    table.insert(
                        errors,
                        string.format("Filename cannot contain null bytes on line %d", line_nr)
                    )
                elseif new_name ~= vim.trim(new_name) then
                    table.insert(
                        errors,
                        string.format(
                            "Filename has leading/trailing whitespace on line %d (did you mean '%s'?)",
                            line_nr,
                            vim.trim(new_name)
                        )
                    )
                elseif #new_name > 255 then
                    table.insert(
                        errors,
                        string.format("Filename too long on line %d (max 255 bytes)", line_nr)
                    )
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

    -- report errors if any
    if #errors > 0 then
        vim.notify(
            "Wdired: Errors found:\n  " .. table.concat(errors, "\n  "),
            vim.log.levels.ERROR
        )
        return
    end

    -- check for conflicts
    -- build lookup maps for O(1) access instead of O(n) nested loops
    local new_names = {}
    local old_path_to_rename = {} -- map old_path -> rename for quick lookup

    for _, rename in ipairs(renames) do
        old_path_to_rename[rename.old_path] = rename

        if new_names[rename.new_name] then
            vim.notify(
                string.format(
                    "Wdired: Duplicate filename '%s' (lines %d and %d)",
                    rename.new_name,
                    new_names[rename.new_name],
                    rename.line_nr
                ),
                vim.log.levels.ERROR
            )
            return
        end
        new_names[rename.new_name] = rename.line_nr
    end

    -- check if target already exists (and is not being renamed away)
    for _, rename in ipairs(renames) do
        if fs.file_exists(rename.new_path) then
            -- O(1) lookup instead of O(n) loop
            local is_rename_target = old_path_to_rename[rename.new_path] ~= nil

            if not is_rename_target then
                vim.notify(
                    string.format("Wdired: File '%s' already exists", rename.new_name),
                    vim.log.levels.ERROR
                )
                return
            end
        end
    end

    -- perform renames
    if #renames == 0 then
        vim.notify("Wdired: No changes to apply", vim.log.levels.INFO)
        M.abort()
        return
    end

    -- show summary
    vim.notify(string.format("Wdired: Renaming %d file(s)...", #renames), vim.log.levels.INFO)

    -- detect swap renames (A->B, B->A) and handle them specially
    -- by first renaming one to a temp name
    local processed = {}
    local rename_count = 0

    for _, rename in ipairs(renames) do
        if processed[rename.old_path] then
            -- already processed as part of a swap
            goto continue
        end

        -- check if this is part of a swap (target is being renamed to our source)
        -- O(1) lookup using the map we built earlier
        local swap_partner = old_path_to_rename[rename.new_path]
        if not (swap_partner and swap_partner.new_path == rename.old_path) then
            swap_partner = nil
        end

        if swap_partner then
            -- handle swap: A->B and B->A using temp file
            local temp_name = rename.new_name .. ".wdired_tmp_" .. os.time()
            local temp_path = fs.join_paths(fs.get_parent_path(rename.old_path), temp_name)

            -- rename A -> temp
            local success1 = vim.loop.fs_rename(rename.old_path, temp_path)
            if not success1 then
                vim.notify(
                    string.format("Wdired: Failed swap rename '%s' (temp)", rename.old_name),
                    vim.log.levels.ERROR
                )
                goto continue
            end

            -- rename B -> A
            local success2 = vim.loop.fs_rename(swap_partner.old_path, swap_partner.new_path)
            if not success2 then
                -- rollback: temp -> A
                vim.loop.fs_rename(temp_path, rename.old_path)
                vim.notify(
                    string.format("Wdired: Failed swap rename '%s'", swap_partner.old_name),
                    vim.log.levels.ERROR
                )
                goto continue
            end

            -- rename temp -> B
            local success3 = vim.loop.fs_rename(temp_path, rename.new_path)
            if not success3 then
                vim.notify(
                    string.format("Wdired: Failed swap rename '%s' (final)", rename.old_name),
                    vim.log.levels.ERROR
                )
                goto continue
            end

            rename_count = rename_count + 2
            processed[rename.old_path] = true
            processed[swap_partner.old_path] = true
        else
            -- normal rename
            local success = vim.loop.fs_rename(rename.old_path, rename.new_path)
            if success then
                rename_count = rename_count + 1
                processed[rename.old_path] = true
            else
                vim.notify(
                    string.format(
                        "Wdired: Failed to rename '%s' to '%s'",
                        rename.old_name,
                        rename.new_name
                    ),
                    vim.log.levels.ERROR
                )
            end
        end

        ::continue::
    end

    -- exit wdired mode and refresh
    M.is_active = false
    M.original_filenames = {}
    vim.bo.modifiable = false

    -- clear marked files since their file objects are now stale after renames
    if #marker.marked_files > 0 then
        marker.marked_files = {}
    end

    -- refresh the dired buffer
    display.render(vim.g.current_dired_path)

    vim.notify(
        string.format("Wdired: Successfully renamed %d file(s)", rename_count),
        vim.log.levels.INFO
    )
end

-- abort wdired mode without applying changes
function M.abort()
    if not M.is_active then
        vim.notify("Wdired: Not in wdired mode", vim.log.levels.WARN)
        return
    end

    M.is_active = false
    M.original_filenames = {}
    vim.bo.modifiable = false

    -- refresh the dired buffer to restore original state
    display.render(vim.g.current_dired_path)

    vim.notify("Wdired: Aborted, no changes applied", vim.log.levels.INFO)
end

return M
