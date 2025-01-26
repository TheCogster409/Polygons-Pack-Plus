ShapeTool = class()

local primaryBind = sm.gui.getKeyBinding("Create", true)
local secondaryBind = sm.gui.getKeyBinding("Attack", true)
local rotateBind = sm.gui.getKeyBinding("NextCreateRotation", true)

function TextureTool.client_onEquippedUpdate(self, primary, secondary, forceBuild)
    local character = sm.localPlayer
    print("hi")
    sm.gui.setInteractionText("Press", rotateBind, " to select a shape")
    return true, false
end