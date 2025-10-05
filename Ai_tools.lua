local dt = require "darktable"
local du = require "lib/dtutils"
du.check_min_api_version("7.0.0", "moduleExample")
local gettext = dt.gettext.gettext
local function _(msgid) return gettext(msgid) end
local script_data = {}
script_data.metadata = {
    name = "AI Toolbox",
    purpose = _("Use AI to tag and rate pictures"),
    author = "Ayéda Okambawa",
}
local mE = {}
mE.widgets = {}
mE.event_registered = false
mE.module_installed = false

-----------------------------------------------------------------------
-- UI Widgets
-----------------------------------------------------------------------

-------------------------------------------
-- Existing Tags
-------------------------------------------
local cbb_existing_tags = dt.new_widget("combobox") {
    label = _("Nb of tags"),
    value = 4,
    "3","4","5","7","10"
}

-------------------------------------------
-- Popular Tags
-------------------------------------------
local cbb_popular_tags = dt.new_widget("combobox") {
    label = _("Nb of tags"),
    value = 4,
    "3","4","5","7","10"
}

-------------------------------------------
-- Ollama Model
-------------------------------------------
local cbb_model = dt.new_widget("combobox") {
    label = _("Model"),
    value = 3,
    "gemma3:27b","gemma3:12b","gemma3:4b","minicpm-v:8b","llava:7b"
}

-------------------------------------------
-- Strictness
-------------------------------------------
local cbb_lvl = dt.new_widget("combobox") {
    label = _("Strictness"),
    value = 3,
    "Clement","Moderate","Rigorous"
}

-------------------------------------------
-- Criteria
-------------------------------------------
local cbb_crt = dt.new_widget("combobox") {
    label = _("Criteria"),
    value = 3,
    "Esthetics","Composition","Light","Emotion"
}

-------------------------------------------
-- Temp image quality
-------------------------------------------
local sld_quality = dt.new_widget("slider") {
    label = _("Temporary JPG quality "),
    soft_min = 0, soft_max = 100, hard_min = 0, hard_max = 100,
    step = 1, digits = 0, value = 95
}

-------------------------------------------
-- Image size
-------------------------------------------
local sld_size = dt.new_widget("slider") {
    label = _("Temporary JPG size"),
    soft_min = 0, soft_max = 4096, hard_min = 0, hard_max = 4096,
    step = 1, digits = 0, value = 0
}

local cbt_clear = dt.new_widget("check_button"){label = _("Clear tags first"), value = false}
local separator1 = dt.new_widget("separator"){}

-----------------------------------------------------------------------
-- Export helper
-----------------------------------------------------------------------
local function export_to_temp_jpeg(img)
    local temp_file = os.tmpname() .. ".jpg"
    local jpeg_exporter = dt.new_format("jpeg")
    jpeg_exporter.quality = sld_quality.value
    jpeg_exporter.max_width = sld_size.value
    jpeg_exporter.max_height = sld_size.value
    jpeg_exporter:write_image(img, temp_file, true)
    dt.print_log(string.format("Exported %s to temp file %s", img.filename, temp_file))
    return temp_file
end

-----------------------------------------------------------------------
-- Existing Tagging
-----------------------------------------------------------------------
local function Existing_tag_button()
    local images = dt.gui.selection()
    if #images == 0 then
        dt.print("No image selected")
        return
    end

    -- retrieving all tags in DB
    local all_tags = dt.tags
    local tag_names = {}
    local no_dt_tags = 0
    for _, tag in ipairs(all_tags) do
        -- Filter out darktable system tags
        if not tag.name:match("^darktable|") then
            table.insert(tag_names, tag.name)
            no_dt_tags = no_dt_tags + 1
        end
    end

    local tag_list = table.concat(tag_names, ", ")
    -- Fallback if no user tags exist
    if tag_list == "" then
        tag_list = "Vietnam, Motorbike"
    end

    local selected_model = cbb_model.value
    local nb_tag = cbb_existing_tags.value

    for _, img in ipairs(images) do
        local full_path = img.path .. "/" .. img.filename

        -- Optionally detach existing tags
        if cbt_clear.value == true then
            local current_tags = dt.tags.get_tags(img)
            for _, tag in ipairs(current_tags) do
                dt.tags.detach(tag, img)
            end
        end

        dt.print("Processing: " .. full_path)
        local jpeg_path = export_to_temp_jpeg(img)

        -- Build new existing_tags prompt
        local prompt = "You are an expert in photo recognizing and darktable tag generation. " ..
                "I will give you a description of an image. Based on the description, " ..
                "Check against existing tags: " .. tag_list .. ". " ..
                "provide a list of maximum " .. nb_tag .. " out of the existing tag list." ..
                " darktable tags. Consider similar tags where the difference is only capital letters as the same and choose only the one with capital letters" ..
                "Only put the most pertinent tags. If you are not 90 percent certain the tag matches please dismiss this tag from the list. " ..
                "Do not include any introductory phrases. Only the tags separated with commas."

        -- Command for Native Ollama
        local command = string.format(
                'ollama run "%s" "%s" "%s"',
                selected_model, prompt, jpeg_path
        )

        print("Running Ollama: " .. command)
        local handle = io.popen(command)
        local output = handle:read("*a")
        handle:close()

        dt.print("Ollama output for " .. img.filename .. ": " .. output)

        -- Parse comma-separated tags
        for tag in string.gmatch(output, '([^,]+)') do
            local cleaned_tag = tag:match("^%s*(.-)%s*$")
            if cleaned_tag ~= "" then
                local tag_obj = dt.tags.create(cleaned_tag)
                dt.tags.attach(tag_obj, img)
                print("Added tag: " .. cleaned_tag .. " to " .. img.filename)
            end
        end

        os.remove(jpeg_path) -- clean up
    end

    dt.print("Tagging complete for " .. #images .. " image(s).")
end

-----------------------------------------------------------------------
-- Popular Tagging
-----------------------------------------------------------------------
local function Popular_tag_button()
    local images = dt.gui.selection()
    if #images == 0 then
        dt.print("No image selected")
        return
    end

    local selected_model = cbb_model.value
    local nb_tag = cbb_popular_tags.value

    for _, img in ipairs(images) do
        local full_path = img.path .. "/" .. img.filename

        -- Optionally detach existing tags
        if cbt_clear.value == true then
            local current_tags = dt.tags.get_tags(img)
            for _, tag in ipairs(current_tags) do
                dt.tags.detach(tag, img)
            end
        end

        dt.print("Processing: " .. full_path)
        local jpeg_path = export_to_temp_jpeg(img)

        -- Build new popular tags prompt
        local prompt = "You are a stock photographer focusing on traveling, lifestyle, portraits and landscape. " ..
                "Please find ~50 trending tags optimized for Shutterstock/Adobe Stock. " ..
                "Provide a list of exactly " .. nb_tag .. " darktable tags out of them which best match the image. " ..
                "Only put the most pertinent tags. Do not include any introductory phrases. Only the tags separated with commas."

        -- Command for Native Ollama
        local command = string.format(
                'ollama run "%s" "%s" "%s"',
                selected_model, prompt, jpeg_path
        )

        print("Running Ollama: " .. command)
        local handle = io.popen(command)
        local output = handle:read("*a")
        handle:close()

        dt.print("Ollama output for " .. img.filename .. ": " .. output)

        -- Parse comma-separated tags
        for tag in string.gmatch(output, '([^,]+)') do
            local cleaned_tag = tag:match("^%s*(.-)%s*$")
            if cleaned_tag ~= "" then
                local tag_obj = dt.tags.create(cleaned_tag)
                dt.tags.attach(tag_obj, img)
                print("Added tag: " .. cleaned_tag .. " to " .. img.filename)
            end
        end

        os.remove(jpeg_path) -- clean up
    end

    dt.print("Tagging complete for " .. #images .. " image(s).")
end

-----------------------------------------------------------------------
-- Rating
-----------------------------------------------------------------------
local function btt_rating()
    local images = dt.gui.selection()
    if #images == 0 then
        dt.print("No image selected")
        return
    end
    local selected_model = cbb_model.value
    local strictness = cbb_lvl.value

    for _, img in ipairs(images) do
        local full_path = img.path .. "/" .. img.filename
        dt.print("Processing: " .. full_path)

        local jpeg_path = export_to_temp_jpeg(img)

        --------------
        --- Rating prompt --
        --------------
        local prompt = "You are a " .. strictness .. " professional photography evaluator. " ..
                "I will provide an image. Assess its potential after editing. " ..
                "consider creativity, esthetics and emotional impact. " ..
                "Disregard resolution and file size. " ..
                "Respond only with a single number, using this scale: -1 Unusable, 0 Very Bad, 1 Bad, 2 Okay, 3 Good, 4 Very Good, 5 Excellent"

        -- Command for Native Ollama
        local command = string.format(
                'ollama run "%s" "%s" "%s"',
                selected_model, prompt, jpeg_path
        )

        print("Running Ollama: " .. command)
        local handle = io.popen(command)
        local output = handle:read("*a")
        handle:close()

        local rating = tonumber(output:match("(-?%d+)"))
        if rating then
            if rating < -1 then rating = -1 end
            if rating > 5 then rating = 5 end
            img.rating = rating
            print("Set rating for " .. img.filename .. " to " .. rating)
        else
            print("No valid rating found for " .. img.filename)
        end
        os.remove(jpeg_path)
    end
    dt.print("Rating complete for " .. #images .. " image(s).")
end

-----------------------------------------------------------------------
-- Select Best Image
-----------------------------------------------------------------------
local function btt_select_best()
    local images = dt.gui.selection()
    if #images < 2 then
        dt.print("Select at least two images")
        return
    end
    local selected_model = cbb_model.value
    local criteria = cbb_crt.value
    local prompt = "I am giving you multiple images. Select ONLY the best one (the one with the highest potential for photography). " ..
            "Focus on " .. criteria .. ". Respond ONLY with the index number."

    local image_paths = {}
    local tempfile_paths = {}

    for idx, img in ipairs(images) do
        local jpeg_path = export_to_temp_jpeg(img)
        if not jpeg_path then
            dt.print("Export failed for " .. img.filename)
            return
        end
        table.insert(image_paths, '"' .. jpeg_path .. '"')
        table.insert(tempfile_paths, { img = img, path = jpeg_path })
    end

    -- Command for Native Ollama
    local command = string.format(
            'ollama run "%s" "%s" %s',
            selected_model, prompt, table.concat(image_paths, " ")
    )

    print("Running Ollama: " .. command)
    local handle = io.popen(command)
    local output = handle:read("*a")
    handle:close()

    dt.print("Ollama output: " .. output)
    local chosen_index = tonumber(output:match("(%d+)"))
    if not chosen_index or chosen_index < 1 or chosen_index > #images then
        dt.print("Could not determine best image index")
        for _, t in ipairs(tempfile_paths) do os.remove(t.path) end
        return
    end

    for idx, t in ipairs(tempfile_paths) do
        if idx ~= chosen_index then
            t.img.rating = -1
            print("Rejected: " .. t.img.filename)
        else
            t.img.rating = 0
            print("Best image kept: " .. t.img.filename)
        end
        os.remove(t.path)
    end
    dt.print("Best image kept. Others rejected.")
end

-----------------------------------------------------------------------
-- GUI / Module lifecycle
-----------------------------------------------------------------------
local function install_module()
    if not mE.module_installed then
        dt.register_lib(
                "AIToolbox",
                _("AI Toolbox"),
                true,
                false,
                {[dt.gui.views.lighttable] = {"DT_UI_CONTAINER_PANEL_RIGHT_CENTER", 100}},
                dt.new_widget("box") { orientation = "vertical", table.unpack(mE.widgets) },
                nil,nil
        )
        mE.module_installed = true
    end
end

local function destroy()
    dt.gui.libs["AIToolbox"].visible = false
end

local function restart()
    dt.gui.libs["AIToolbox"].visible = true
end

-- Labels
local lbl_existing_tag = dt.new_widget("section_label")
lbl_existing_tag.label = _(" -Existing Tags-")

local lbl_popular_tag = dt.new_widget("section_label")
lbl_popular_tag.label = _(" ---- Popular Tags")

local lbl_rating = dt.new_widget("section_label")
lbl_rating.label = _("--  Rating  --")

local lbl_setting = dt.new_widget("section_label")
lbl_setting.label = _("Settings")

local lbl_reject = dt.new_widget("section_label")
lbl_reject.label = _(" Top Pick ---")

-- Buttons
local attach_button = dt.new_widget("button") {
    label=_("- Attach Tags - "),
    clicked_callback=function(_) Existing_tag_button() end
}

local import_button = dt.new_widget("button") {
    label=_("--   Import Tags"),
    clicked_callback=function(_) Popular_tag_button() end
}

local rating_button = dt.new_widget("button") {
    label=_("Set Rating"),
    clicked_callback=function(_) btt_rating() end
}

local reject_button = dt.new_widget("button") {
    label=_("Select Best ---"),
    clicked_callback=function(_) btt_select_best() end
}

mE.widgets = {
    lbl_existing_tag, cbt_clear, cbb_existing_tags, separator1, attach_button,
    lbl_popular_tag, cbb_popular_tags, import_button,
    lbl_rating, cbb_lvl, rating_button,
    lbl_reject, cbb_crt, reject_button,
    lbl_setting, cbb_model, sld_quality, sld_size
}

if dt.gui.current_view().id == "lighttable" then
    install_module()
else
    if not mE.event_registered then
        dt.register_event("AIToolbox", "view-changed", function(event, old_view, new_view)
            if new_view.id == "lighttable" then install_module() end
        end)
        mE.event_registered = true
    end
end

script_data.destroy = destroy
script_data.restart = restart
script_data.destroy_method = "hide"
script_data.show = restart
return script_data
