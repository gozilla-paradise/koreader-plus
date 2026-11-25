--[[--
Thai user words.

Thai is written without spaces between words, and crengine uses a word list
to find where lines can be wrapped. It never breaks inside text it does not
know, but names and foreign words made of syllables that happen to be Thai
words may get broken in the middle (ยูโด|ร่า). The user can fix that by
selecting the word and adding it to their own Thai words, which are kept in
settings/user-thai-words.txt (one word per line).
]]

local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local ReaderThaiWords = WidgetContainer:extend{}

-- Thai letters, vowels and tone marks (U+0E01-U+0E3A and U+0E40-U+0E4E,
-- not digits and punctuation), the chars crengine segments, as UTF-8.
local THAI_CHAR_PATTERNS = { "\224\184[\129-\186]", "\224\185[\128-\142]" }

local function removeThaiChars(text)
    for _, pattern in ipairs(THAI_CHAR_PATTERNS) do
        text = text:gsub(pattern, "")
    end
    return text
end

local function hasThai(text)
    return removeThaiChars(text) ~= text
end

local function isThaiWord(text)
    return text ~= "" and removeThaiChars(text) == ""
end

-- Remove any non-Thai chars (spaces, punctuation...) at start and end of text
local function trimToThai(text)
    local chars = util.splitToChars(text)
    local first, last = 1, #chars
    while first <= last and not isThaiWord(chars[first]) do first = first + 1 end
    while last >= first and not isThaiWord(chars[last]) do last = last - 1 end
    return table.concat(chars, "", first, last)
end

function ReaderThaiWords:getUserWordsPath()
    return self.ui.document:getThaiUserWordsPath()
end

-- Returns the comment lines and the words of the user words file
function ReaderThaiWords:readUserWords()
    local comments, words = {}, {}
    local file = io.open(self:getUserWordsPath(), "r")
    if file then
        for raw_line in file:lines() do
            local line = raw_line:gsub("\r$", "")
            if line:match("^%s*#") then
                table.insert(comments, line)
            else
                local word = util.trim(line)
                if word ~= "" then
                    words[word] = true
                end
            end
        end
        file:close()
    end
    return comments, words
end

function ReaderThaiWords:hasUserWord(word)
    local words = select(2, self:readUserWords())
    return words[word] == true
end

-- Add (add=true) or remove (add=false) a word, and re-render the book
function ReaderThaiWords:updateUserWords(word, add)
    local comments, words = self:readUserWords()
    words[word] = add or nil
    local sorted = {}
    for w in pairs(words) do
        table.insert(sorted, w)
    end
    table.sort(sorted)

    local path = self:getUserWordsPath()
    local new_path = path .. ".new"
    local file = io.open(new_path, "w")
    if not file then
        logger.err("ReaderThaiWords: could not open", new_path)
        UIManager:show(InfoMessage:new{
            text = T(_("Could not write to %1"), path),
        })
        return
    end
    for _, line in ipairs(comments) do
        file:write(line, "\n")
    end
    for _, w in ipairs(sorted) do
        file:write(w, "\n")
    end
    file:close()
    os.remove(path)
    os.rename(new_path, path)

    self.ui.document:loadThaiUserWords()
    -- The Thai user words are part of crengine's rendering hash: this will re-render
    self.ui:handleEvent(Event:new("UpdatePos"))
    if add then
        Notification:notify(T(_("Thai word added: %1"), word), Notification.SOURCE_ALWAYS_SHOW)
    else
        Notification:notify(T(_("Thai word removed: %1"), word), Notification.SOURCE_ALWAYS_SHOW)
    end
end

-- Whether to show the button in the highlight dialog for this selected text
function ReaderThaiWords:isAvailable(text)
    if not text or text:find("[%s\n]") then
        return false
    end
    local cre = require("document/credocument"):engineInit()
    return cre.getThaiWordBreaks ~= nil and hasThai(text)
end

function ReaderThaiWords:getBreaksPreview(word)
    local cre = require("document/credocument"):engineInit()
    return cre.getThaiWordBreaks(word, " | ")
end

function ReaderThaiWords:showWordDialog(text)
    local word = trimToThai(text)
    if word == "" then return end
    local preview = self:getBreaksPreview(word)
    local description
    if preview ~= word then
        description = T(_("Lines can currently break at:\n%1\n\nAdd this word to your Thai words so lines never break inside it. You can first edit it to add or remove letters."), preview)
    else
        description = _("Lines currently never break inside this text.\n\nYou can still add it to your Thai words, which may help the text around it break correctly. You can first edit it to add or remove letters.")
    end
    local dialog
    dialog = InputDialog:new{
        title = _("Thai word"),
        description = description,
        input = word,
        input_type = "string",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Remove"),
                    enabled = self:hasUserWord(word),
                    callback = function()
                        local w = util.trim(dialog:getInputText())
                        UIManager:close(dialog)
                        if self:hasUserWord(w) then
                            self:updateUserWords(w, false)
                        end
                    end,
                },
                {
                    text = _("Add"),
                    is_enter_default = true,
                    callback = function()
                        local w = util.trim(dialog:getInputText())
                        if not isThaiWord(w) then
                            UIManager:show(InfoMessage:new{
                                text = _("A Thai word can only contain Thai letters, vowels and tone marks."),
                            })
                            return
                        end
                        UIManager:close(dialog)
                        if not self:hasUserWord(w) then
                            self:updateUserWords(w, true)
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

return ReaderThaiWords
