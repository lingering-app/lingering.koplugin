--[[--
Tegel voor een map uit de catalogus, gelijk op het homescreen en in Mijn boeken: stapel van
tot drie omslagen (Widgets.coverStack; zonder omslagen een mapicoon), daaronder de naam en
grijs het aantal boeken. Tekst links, gelijk met de linkerrand van de stapel; de stapel staat
gecentreerd in de tegel. Omslagen en aantal komen uit de cache van de map (library:cached);
staat de map er nog niet in, dan geen aantal. Een tik roept callback() aan.

FolderTile:new{ library, url, title, width, stack_w, stack_h, callback }
FolderTile.height(stack_h) → hoogte van de inhoud (voor rijen van gelijke hoogte)
Maat van de stapel: Widgets.folderStackSize.
]]
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("lingering.l10n.gettext")
local T = require("ffi/util").template

local Widgets = require("lingering.ui.widgets")
local Style = require("lingering.ui.style")

local COUNT_FACE = Font:getFace("cfont", 13)

local FolderTile = InputContainer:extend{
    library = nil,
    url = nil,
    title = nil,
    width = nil,
    stack_w = nil,
    stack_h = nil,
    callback = nil,
}

-- Hoogte van één regel tekst in dit lettertype.
local function lineHeight(face, bold)
    return TextWidget:new{ text = "Ag", face = face, bold = bold }:getSize().h
end

function FolderTile.height(stack_h)
    return stack_h + Size.padding.small + lineHeight(Widgets.FOLDER_TITLE_FACE, true) + lineHeight(COUNT_FACE)
end

-- Tot drie omslagen en het aantal boeken uit de cache; aantal nil als de map er niet in staat.
function FolderTile:loadFolder()
    local feed = self.library:cached(self.url)
    local single_w, single_h = Widgets.stackCoverSize(self.stack_w, self.stack_h)
    local covers, count = {}, 0
    for _, item in ipairs(feed and feed.items or {}) do
        if item.kind == "book" then
            count = count + 1
            if #covers < 3 and item.thumbnail then
                local bb = Widgets.loadCover(self.library, item.thumbnail, single_w, single_h)
                if bb then table.insert(covers, bb) end
            end
        end
    end
    return covers, feed and count or nil
end

function FolderTile:init()
    local covers, count = self:loadFolder()
    local stack = Widgets.coverStack(covers, self.stack_w, self.stack_h)
        or CenterContainer:new{
            dimen = Geom:new{ w = self.stack_w, h = self.stack_h },
            Widgets.icon({ icon_file = "folder.svg" }, math.floor(math.min(self.stack_w, self.stack_h) * 0.4)),
        }
    local left = math.floor((self.width - self.stack_w) / 2)
    local text_w = self.width - left - Size.padding.default
    local group = VerticalGroup:new{
        align = "left",
        stack,
        VerticalSpan:new{ width = Size.padding.small },
        TextWidget:new{
            text = self.title,
            face = Widgets.FOLDER_TITLE_FACE,
            bold = true,
            max_width = text_w,
        },
    }
    if count then
        table.insert(group, TextWidget:new{
            text = count == 1 and _("1 boek") or T(_("%1 boeken"), count),
            face = COUNT_FACE,
            fgcolor = Style.text_secondary,
            max_width = text_w,
        })
    end
    group.overlap_offset = { left, 0 }
    self[1] = OverlapGroup:new{
        dimen = Geom:new{ w = self.width, h = FolderTile.height(self.stack_h) },
        group,
    }
    self.ges_events = {
        TapTile = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
end

function FolderTile:onTapTile()
    if self.callback then Widgets.safeCall("map " .. tostring(self.title), self.callback) end
    return true
end

return FolderTile
