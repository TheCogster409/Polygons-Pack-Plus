TextureTool = class()

local camera = sm.camera
local primaryBind = sm.gui.getKeyBinding("Create", true)
local secondaryBind = sm.gui.getKeyBinding("Attack", true)
local rotateBind = sm.gui.getKeyBinding("NextCreateRotation", true)

function TextureTool.client_onCreate(self)
  self.textureType = "Regular"

  self.gui = sm.gui.createGuiFromLayout( "$CONTENT_DATA/Gui/Layouts/TextureTool.layout", false, {
    isHud = false,
    isInteractive = true,
    needsCursor = true,
    hidesHotbar = false,
    isOverlapped = false,
    backgroundAlpha = 0.0,
  })
  --self.gui:setButtonCallback( "MyButton", "cl_onButtonPressed" )
end

function TextureTool.client_onUpdate(self, dt)
  self.deltaTime = dt
end

local uuidLists = sm.json.open("$CONTENT_DATA/Scripts/uuids.json")

local function checkType(shapeType)
  for i, list in pairs(uuidLists) do
      if list[shapeType] ~= nil then
        return true
      end
  end
  return false
end

function TextureTool.client_onEquippedUpdate(self, primary, secondary, forceBuild)
	local character = sm.localPlayer

  -- Selection Effect
  if not self.selectionEffect then
    self.selectionEffect = sm.effect.createEffect('ShapeRenderable')
    self.selectionEffect:setParameter("visualization", true)
  end

  local position = camera.getPosition()
  local direction = camera.getDirection()
  local filter = sm.physics.filter.dynamicBody + sm.physics.filter.staticBody
  local hit, result = sm.physics.raycast(position, position + direction * 7.5, character, filter)

  if hit then
    local isValid = result.type == "body"
    local selectedShape = isValid and result:getShape()

    if not selectedShape.isBlock and sm.item.getFeatureData(selectedShape.uuid).data ~= nil then
      local shapeType = sm.item.getFeatureData(selectedShape.uuid).data.shapeType

      if isValid and checkType(shapeType) then
        position = isValid and selectedShape:getInterpolatedWorldPosition()
        rotation = selectedShape:getWorldRotation()
        velocity = isValid and selectedShape.velocity or selectedShape.shapeA.velocity

        sm.gui.setInteractionText("", primaryBind, "Change to " .. self.textureType .. " texture")
        self.selectionEffect:stop()
        self.selectionEffect:setPosition(position + velocity * self.deltaTime)
        self.selectionEffect:setRotation(rotation)
        self.selectionEffect:setScale(sm.vec3.one() * 0.25)
        self.selectionEffect:setParameter("uuid", selectedShape.uuid)
        self.selectionEffect:start()

        if primary == sm.tool.interactState.start then
          sm.effect.playEffect("SpudgunBasic - DefaultImpact01", position, velocity, rotation)
          self.network:sendToServer("server_changeShape", {selectedShape, self.textureType})
        end
      else
        self.selectionEffect:stop()
      end
    else
      self.selectionEffect:stop()
    end
  else
    self.selectionEffect:stop()
  end

  sm.gui.setInteractionText("", rotateBind, "Rotate mode ", "<p textShadow='false' bg='gui_keybinds_bg' color='#ffffff' spacing='4'>" .. "Current: " .. self.textureType .. "</p>")
  return true, true
end

function TextureTool.client_onToggle(self)
  --self.gui:open()

  if self.textureType == "Glow" then
    self.textureType = "Regular"
  elseif self.textureType == "Regular" then
    self.textureType = "Glow"
  end
	return true --true or false, default false
end

function TextureTool.client_onUnequip(self)
  self.selectionEffect:stop()
end

function  TextureTool.server_changeShape(self, data)
  local shapeType = sm.item.getFeatureData(data[1].uuid).data.shapeType
  local uuid = uuidLists[data[2]][shapeType]

  data[1]:replaceShape(sm.uuid.new(uuid))
end