editor = class()

local localPlayer = sm.localPlayer
local camera = sm.camera

local createStr = "<p textShadow='true' bg='gui_keybinds_bg' color='#ffffff' spacing='5'>"..create.."To edit selected</p>"
local attackStr = "<p textShadow='true' bg='gui_keybinds_bg' color='#ffffff' spacing='5'>"..attack.."To multiselect</p>"
local forceStrSelect = "<p textShadow='true' bg='gui_keybinds_bg' color='#ffffff' spacing='5'>"..force.."To select body</p>"
local forceStrDeselect = "<p textShadow='true' bg='gui_keybinds_bg' color='#ffffff' spacing='5'>"..force.."To deselect body</p>"
local reloadStr = "<p textShadow='true' bg='gui_keybinds_bg' color='#ffffff' spacing='5'>"..reload.."To select creation</p>"

local plasticUuid = sm.uuid.new("628b2d61-5ceb-43e9-8334-a4135566df7a")
local backupDir = "$CONTENT_DATA/creationBackups/"
local settingsDir = "$CONTENT_DATA/Settings/toolSettings.json"
local packetSize = 65000

local function getEffectData(shape)
	local isShape = type(shape) == "Shape"
	local scale = sm.vec3.one() / 4
	local uuid = shape.uuid

	if isShape then
		if shape.isBlock then
			uuid = plasticUuid
			scale = shape:getBoundingBox() + sm.vec3.one() / 1000
		end
	else
		if shape:getType() == "piston" then
			local pistonLength = shape:getLength()
			local lifted = shape.shapeA.body:isOnLift()

			if pistonLength > 1.05 and not lifted then
				uuid = plasticUuid
				scale.z = pistonLength / 4
			end
		end
	end

	return uuid, scale
end

local function getJointEffectPosiiton(joint)
	local position = joint.worldPosition
	local type_ = joint:getType()
	local rot = sm.quat.getAt(joint:getWorldRotation())

	if type_ == "unknown" then
		local bb = joint:getBoundingBox()
		local len = math.max(math.abs(bb.x),  math.abs(bb.y), math.abs(bb.z))
		local offset = len / 2 - 0.125

		position = position + rot * offset
	elseif type_ == "piston" then
		local pistonLength = joint:getLength()
		local lifted = joint.shapeA.body:isOnLift()

		if pistonLength > 1.05 and not lifted then
			local real = joint.worldPosition
			local fake = real + rot * pistonLength / 4
			local dir = fake - real

			position = position + dir / 2 - (rot * 0.125)
		end
	end

	return position
end

local function randCol()
	return sm.color.new(math.random(0, 100000) / 100000, 
						math.random(0, 100000) / 100000, 
						math.random(0, 100000) / 100000)
end

local function formatCol(color)
	return string.upper(string.sub(tostring(color), 1, 6))
end

local function deepCopy(orig)
	local orig_type = type(orig)
	local copy
	if orig_type == 'table' then
		copy = {}
		for orig_key, orig_value in next, orig, nil do
			copy[deepCopy(orig_key)] = deepCopy(orig_value)
		end
	else
		copy = orig
	end
	return copy
end

local function beautifyJson(obj, indent)
    indent = indent or 0

    local function encode(val, current_indent)
        local inner_indent = current_indent + 2
        local indent_str = string.rep("    ", inner_indent)
        local current_indent_str = string.rep("    ", current_indent)

        if type(val) == "table" then
            local entries = {}
            local is_array = true
            local max_index = 0

            for k, _ in pairs(val) do
                if type(k) == "number" and k > 0 and math.floor(k) == k then
                    max_index = math.max(max_index, k)
                else
                    is_array = false
                end
            end

            if is_array and max_index == #val then
                for i = 1, max_index do
                    table.insert(entries, indent_str .. encode(val[i], inner_indent))
                end

                return "#dbd700[#eeeeee\n" .. table.concat(entries, ",\n") .. "\n" .. current_indent_str .. "#dbd700]#eeeeee"
            else
                for k, v in pairs(val) do
                    table.insert(entries, indent_str .. '"' .. tostring(k) .. '": ' .. encode(v, inner_indent))
                end

                table.sort(entries)

                return "#dbd700{#eeeeee\n" .. table.concat(entries, ",\n") .. "\n" .. current_indent_str .. "#dbd700}#eeeeee"
            end
        elseif type(val) == "number" then
            return "#b5ce89" .. tostring(val) .. "#eeeeee"
        elseif type(val) == "boolean" then
            return "#022871" .. tostring(val) .. "#eeeeee"
        elseif type(val) == "string" then
            return '#f05c0f"' .. val .. '"#eeeeee'
        else
            error("Unsupported data type: " .. type(val))
        end
    end

    local encoded_str = encode(obj, indent)
    local lines = {}
    local line_number = 1

    for line in encoded_str:gmatch("[^\n]+") do
        local formatted_line = string.format("#7a7a7a%4d:	#eeeeee%s", line_number, line)
        table.insert(lines, formatted_line)
        line_number = line_number + 1
    end

    return table.concat(lines, "\n")
end


local function uglifyJson(str)
    local hex_pattern = "#%x%x%x%x%x%x"
    local clean = str:gsub(hex_pattern, "")

    local line_number_pattern = "^%s*%d+:%s*"
    local lines = {}
    
    for line in clean:gmatch("[^\n]+") do
        line = line:gsub(line_number_pattern, "")
        table.insert(lines, line)
    end
    
    return table.concat(lines, "\n")
end

local function splitString(inputString, chunkSize)
    local chunks = {}

    for i = 1, #inputString, chunkSize do
        local chunk = string.sub(inputString, i, i + chunkSize - 1)
        table.insert(chunks, chunk)
    end

    return chunks
end

local function replaceHexColor(inputStr, newHex)
    local oldHexPattern = "%f[%w]%x%x%x%x%x%x%f[%W]"
    local modifiedStr = string.gsub(inputStr, oldHexPattern, function(oldHex)

        local startIdx, endIdx = string.find(inputStr, oldHex)

        if startIdx > 1 and string.sub(inputStr, startIdx - 1, startIdx - 1) == "#" then
            return oldHex
        else
            return newHex
        end
    end)

    return modifiedStr
end

local function convertTimestamp(timestamp)
    local SECONDS_IN_MINUTE = 60
    local SECONDS_IN_HOUR = 3600
    local SECONDS_IN_DAY = 86400
    local SECONDS_IN_YEAR = 31556926

    local function isLeapYear(year)
        return (year % 4 == 0 and year % 100 ~= 0) or (year % 400 == 0)
    end

    local year = 1970
    local remainingSeconds = timestamp

    while remainingSeconds >= SECONDS_IN_YEAR do
        if isLeapYear(year) then
            if remainingSeconds < 366 * SECONDS_IN_DAY then break end
            remainingSeconds = remainingSeconds - 366 * SECONDS_IN_DAY
        else
            if remainingSeconds < 365 * SECONDS_IN_DAY then break end
            remainingSeconds = remainingSeconds - 365 * SECONDS_IN_DAY
        end
        year = year + 1
    end

    local daysInMonth = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
    if isLeapYear(year) then
        daysInMonth[2] = 29
    end

    local month = 1
    while remainingSeconds >= daysInMonth[month] * SECONDS_IN_DAY do
        remainingSeconds = remainingSeconds - daysInMonth[month] * SECONDS_IN_DAY
        month = month + 1
    end
    local day = math.floor(remainingSeconds / SECONDS_IN_DAY) + 1
    remainingSeconds = remainingSeconds % SECONDS_IN_DAY

    local hour = math.floor(remainingSeconds / SECONDS_IN_HOUR)
    remainingSeconds = remainingSeconds % SECONDS_IN_HOUR
    local minute = math.floor(remainingSeconds / SECONDS_IN_MINUTE)
    local second = remainingSeconds % SECONDS_IN_MINUTE

    local formattedDate = string.format("%02d/%02d/%04d", day, month, year)
    local formattedTime = string.format("%02d:%02d:%02d", hour, minute, second)

    return formattedDate, formattedTime
end

local function getLength(tbl)
	local count = 0

	for _, v in pairs(tbl) do
		count = count + 1
	end

	return count
end

local function returnFirst(tbl)
	for i, v in pairs(tbl) do
		return v
	end
end

local function destroyEffectTable(table)
	for _, v in pairs(table) do
		if sm.exists(v) then
			v:destroy()
		end
	end
end

local function absVec(vec)
	return sm.vec3.new(math.abs(vec.x), math.abs(vec.y), math.abs(vec.z))
end

local function drawLine(pos1, pos2, effect)
	local dir = pos1 - camera.getPosition()

	if dir:length() > 0 then
		local dirDot = camera.getDirection():dot(dir:normalize())

		local width, height = sm.gui.getScreenSize()
		local x1, y1 = sm.render.getScreenCoordinatesFromWorldPosition(pos1, width, height)
		local x2, y2 = sm.render.getScreenCoordinatesFromWorldPosition(pos2, width, height)

		if dirDot > 0.3 and x1 ~= math.huge and x2 ~= math.huge and y1 ~= math.huge and y2 ~= math.huge then
			local factor = width / 16

			x1 = x1 / factor
			x2 = x2 / factor

			y1 = (height / factor) - (y1 / factor)
			y2 = (height / factor) - (y2 / factor)

			local pos1 = sm.vec3.new(x1, 0, y1)
			local pos2 = sm.vec3.new(x2, 0, y2)
			local diff = pos1 - pos2

			local scale = sm.vec3.new(0.01, 0.01, diff:length())
			local position = pos1 - diff / 2
			local rotation = sm.vec3.getRotation(sm.vec3.new(0, 0, 1), diff)

			effect:setPosition(position)
			effect:setRotation(rotation)
			effect:setScale(scale)

			if not effect:isPlaying() then
				effect:start()
			end
		else
			if effect:isPlaying() then
				effect:stop()
			end
		end
	end
end

local function quatFromMatrix(m)
    local trace = m[1][1] + m[2][2] + m[3][3]
    local q

    if trace > 0 then
        local s = math.sqrt(trace + 1.0) * 2
        q = sm.quat.new(
            (m[3][2] - m[2][3]) / s,
            (m[1][3] - m[3][1]) / s,
            (m[2][1] - m[1][2]) / s,
            0.25 * s
        )
    elseif (m[1][1] > m[2][2] and m[1][1] > m[3][3]) then
        local s = math.sqrt(1.0 + m[1][1] - m[2][2] - m[3][3]) * 2
        q = sm.quat.new(
            0.25 * s,
            (m[1][2] + m[2][1]) / s,
            (m[1][3] + m[3][1]) / s,
            (m[3][2] - m[2][3]) / s
        )
    elseif (m[2][2] > m[3][3]) then
        local s = math.sqrt(1.0 + m[2][2] - m[1][1] - m[3][3]) * 2
        q = sm.quat.new(
            (m[1][2] + m[2][1]) / s,
            0.25 * s,
            (m[2][3] + m[3][2]) / s,
            (m[1][3] - m[3][1]) / s
        )
    else
        local s = math.sqrt(1.0 + m[3][3] - m[1][1] - m[2][2]) * 2
        q = sm.quat.new(
            (m[1][3] + m[3][1]) / s,
            (m[2][3] + m[3][2]) / s,
            0.25 * s,
            (m[2][1] - m[1][2]) / s
        )
    end

    return q
end

local function better_quat_rotation(forward, right, up)
    forward = forward:safeNormalize(sm.vec3.new(1, 0, 0))
    right   = right:safeNormalize(sm.vec3.new(0, 0, 1))
    up      = up:safeNormalize(sm.vec3.new(0, 1, 0))

    local m11 = right.x; local m12 = right.y; local m13 = right.z
    local m21 = forward.x; local m22 = forward.y; local m23 = forward.z
    local m31 = up.x; local m32 = up.y; local m33 = up.z

    local biggestIndex = 0
    local fourBiggestSquaredMinus1 = m11 + m22 + m33

    local fourXSquaredMinus1 = m11 - m22 - m33
    if fourXSquaredMinus1 > fourBiggestSquaredMinus1 then
        fourBiggestSquaredMinus1 = fourXSquaredMinus1
        biggestIndex = 1
    end

    local fourYSquaredMinus1 = m22 - m11 - m33
    if fourYSquaredMinus1 > fourBiggestSquaredMinus1 then
        fourBiggestSquaredMinus1 = fourYSquaredMinus1
        biggestIndex = 2
    end

    local fourZSquaredMinus1 = m33 - m11 - m22
    if fourZSquaredMinus1 > fourBiggestSquaredMinus1 then
        fourBiggestSquaredMinus1 = fourZSquaredMinus1
        biggestIndex = 3
    end

    local biggestVal = math.sqrt(fourBiggestSquaredMinus1 + 1.0) * 0.5
    local mult = 0.25 / biggestVal

    if biggestIndex == 1 then
        return sm.quat.new(biggestVal, (m12 + m21) * mult, (m31 + m13) * mult, (m23 - m32) * mult)
    elseif biggestIndex == 2 then
        return sm.quat.new((m12 + m21) * mult, biggestVal, (m23 + m32) * mult, (m31 - m13) * mult)
    elseif biggestIndex == 3 then
        return sm.quat.new((m31 + m13) * mult, (m23 + m32) * mult, biggestVal, (m12 - m21) * mult)
    end

    return sm.quat.new((m23 - m32) * mult, (m31 - m13) * mult, (m12 - m21) * mult, biggestVal)
end

local function rotateVectors(at, right, up, angular_velocity, dt)
    local angle_x, angle_y, angle_z = angular_velocity.x * dt, angular_velocity.y * dt, angular_velocity.z * dt

    local qx = sm.quat.angleAxis(angle_x, sm.vec3.new(1, 0, 0))
    local qy = sm.quat.angleAxis(angle_y, sm.vec3.new(0, 1, 0))
    local qz = sm.quat.angleAxis(angle_z, sm.vec3.new(0, 0, 1))

    local q = qz * qy * qx

    at = q * at
    right = q * right
    up = q * up

    return at, right, up
end

local function getNewParent(joint, creation)
	local childA = joint.childA
	local parentPos 
	local oldJointPos

	for _, body in pairs(creation.bodies) do
		local child = body.childs[childA + 1]
		local broke

		if child and child.joints then
			for _, v in pairs(child.joints) do
				if v.id == joint.id then
					parentPos = posToVec3(child.pos)

					broke = true
					break
				end
			end
		end

		if broke then break end
	end

	if not parentPos then return childA end

	for i, oldJoint in pairs(creation.joints) do
		if oldJoint.id == joint.id then
			oldJointPos = posToVec3(oldJoint.posA)
			break
		end
	end

	local newPos = (parentPos - oldJointPos) + posToVec3(joint.posA)

	for _, body in pairs(creation.bodies) do
		local broke

		for i, child in pairs(body.childs) do
			if posToVec3(child.pos) == newPos then
				childA = i - 1

				if childA < 0 then childA = joint.childA end
				broke = true
				break
			end
		end

		if broke then break end
	end

	return childA
end

local function quatFromRightUp(right, up)
    right = right:normalize()
    up = up:normalize()

    local forward = right:cross(up):normalize()

    local m = {
        { right.x, up.x, forward.x },
        { right.y, up.y, forward.y },
        { right.z, up.z, forward.z }
    }

    return quatFromMatrix(m)
end

function vectorToAxis(vec)
	local axis

	if vec.x > 0.5 then axis = 1 end
	if vec.y > 0.5 then axis = 2 end
	if vec.z > 0.5 then axis = 3 end

	if vec.x < -0.5 then axis = -1 end
	if vec.y < -0.5 then axis = -2 end
	if vec.z < -0.5 then axis = -3 end

	return axis
end

function axisToVector(axis)
	local vec = sm.vec3.zero()

	if axis == 1 then vec.x = 1 end
	if axis == 2 then vec.y = 1 end
	if axis == 3 then vec.z = 1 end

	if axis == -1 then vec.x = -1 end
	if axis == -2 then vec.y = -1 end
	if axis == -3 then vec.z = -1 end

	return vec
end

function posToVec3(pos)
	return sm.vec3.new(pos.x, pos.y, pos.z)
end

function isWithin(vec, lowVec, highVec)
	if  lowVec.x <= vec.x and vec.x <= highVec.x and 
		lowVec.y <= vec.y and vec.y <= highVec.y and 
		lowVec.z <= vec.z and vec.z <= highVec.z then
		return true
	end

	return false
end

-- SERVER --

function editor:server_onCreate()
	self.sv = {
		export = {},
		queue = {
			valid = true
		},
		effect = {},
		lift = {},
		backups = {}
	}
end

function editor:sv_exportSelected(data, player)
	local shapes = data.shapes
	local joints = data.joints
	local body = data.body

	if sm.exists(body) then
		local lifted = body:isOnLift()

		local originalShapes, newShapes = {}, {}
		local originalJoints, newJoints = {}, {}
		local exportedJson, exportedShapeIndexes, exportedJointIndexes = {}, {}, {}
		local oldShapes, oldJoints = {}, {}
		local exportError

		for _, shape in pairs(shapes) do
			if sm.exists(shape) then
				local rand = randCol()

				originalShapes[shape.id] = shape.color
				newShapes[formatCol(rand)] = shape

				shape.color = rand
			else	
				exportError = true
				break
			end
		end

		if not exportError then
			for _, joint in pairs(joints) do
				if sm.exists(joint) then
					local rand = randCol()

					originalJoints[joint.id] = joint.color
					newJoints[formatCol(rand)] = joint

					joint.color = rand
				else
					exportError = true
					break
				end
			end
		end

		if exportError then
			for _, shape in pairs(shapes) do
				if sm.exists(shape) then
					local color = originalShapes[shape.id]

					if color then
						shape.color = originalShapes[shape.id]
					end
				end
			end

			for _, joint in pairs(joints) do
				if sm.exists(joint) then
					local color = originalJoints[joint.id]

					if color then
						joint.color = color
					end
				end
			end

			self.network:sendToClient(player, "cl_chatMessage", "#ff0000Export selection invalid")
		else
			local creationJson = sm.creation.exportToTable(body, true, lifted)

			if getLength(shapes) > 0 then
				for i, body in pairs(creationJson.bodies) do
					for j, child in pairs(body.childs) do
						local shape = newShapes[child.color]

						if shape then
							newShapes[child.color] = nil

							local original = originalShapes[shape.id]

							shape.color = original
							child.color = formatCol(original)

							table.insert(exportedJson, child)
							table.insert(exportedShapeIndexes, {i1 = i, i2 = j, i3 = #exportedJson})
							table.insert(oldShapes, shape)
						end
					end
				end
			end

			if getLength(joints) > 0 then
				if creationJson.joints then
					for i, child in pairs(creationJson.joints) do
						local joint = newJoints[child.color]

						if joint then
							newJoints[child.color] = nil

							local original = originalJoints[joint.id]

							joint.color = original
							child.color = formatCol(original)

							table.insert(exportedJson, child)
							table.insert(exportedJointIndexes, {i1 = i, i2 = #exportedJson})
							table.insert(oldJoints, joint)
						end
					end
				end
			end

			local error

			if getLength(newShapes) > 0 then
				for i, shape in pairs(newShapes) do
					shape.color = originalShapes[shape.id]
				end

				error = true
			end

			if getLength(newJoints) > 0 then
				for i, joint in pairs(newJoints) do
					joint.color = originalJoints[joint.id]
				end

				error = true
			end

			if error then
				self.network:sendToClient(player, "cl_chatMessage", "#ff0000Unable to export all selected shapes/joints")
			end

			local jsonStr = beautifyJson(exportedJson)
			local strings = splitString(jsonStr, packetSize)

			for i, string in pairs(strings) do
				local finished = i == #strings
				self.network:sendToClient(player, "cl_rebuildJson", {string = string, finished = finished, i = i})
			end

			if self.sv.backups.isEnabled then
				local backupStrings = splitString(sm.json.writeJsonString(creationJson), packetSize)

				for i, string in pairs(backupStrings) do
					local finished = i == #backupStrings
					self.network:sendToClient(player, "cl_rebuildBackup", {string = string, finished = finished, i = i})
				end
			end

			self.sv.export.exportedShapeIndexes = exportedShapeIndexes
			self.sv.export.exportedJointIndexes = exportedJointIndexes
			self.sv.export.oldJson = creationJson
			self.sv.export.oldBody = body
			self.sv.export.oldShapes = oldShapes
			self.sv.export.oldJoints = oldJoints
		end
	else
		self.network:sendToClient(player, "cl_chatMessage", "#ff0000Unable to re-export creation")
		self.network:sendToClient(player, "cl_closeGui")
		
		self:sv_importErrorReset(player)
	end
end

function editor:sv_rebuildJson(data, player)
	if data.i == 1 then
        self.sv.export.json = data.string
    else
        self.sv.export.json = self.sv.export.json..data.string
    end

    if data.finished then
		local status, err = pcall(function()
			self.sv.export.json = sm.json.parseJsonString(self.sv.export.json)
		end)

		if not status then
			err = err:sub(64, #err)
			self.network:sendToClient(player, "cl_chatMessage", "#ff0000"..err)

			self:sv_importErrorReset(player)
		else
        	self:sv_importJson(player)
		end
    end
end

function editor:sv_importJson(player)
	local refindShapeColors, refindJointColors = {}, {}
	local findIds = {}

	for i, data in pairs(self.sv.export.exportedShapeIndexes) do
		local jsonData = self.sv.export.json[data.i3]

		if jsonData then
			local specialInstruction = self.sv.export.specialInstruction

			if specialInstruction then
				if specialInstruction.name == "move" then
					jsonData.pos.x = jsonData.pos.x + specialInstruction.data.x
					jsonData.pos.y = jsonData.pos.y + specialInstruction.data.y
					jsonData.pos.z = jsonData.pos.z + specialInstruction.data.z
				end

				if specialInstruction.name == "bound" and jsonData.bounds then
					jsonData.bounds.x = jsonData.bounds.x + specialInstruction.data.x
					jsonData.bounds.y = jsonData.bounds.y + specialInstruction.data.y
					jsonData.bounds.z = jsonData.bounds.z + specialInstruction.data.z
				end

				if specialInstruction.name == "rotate" then
					local rot = specialInstruction.data
					local shape = self.sv.export.oldShapes[i]
					local isBlock = shape.isBlock

					if isBlock then
						rot.y = rot.y * -1
						rot.x = rot.x * -1
					end

					local isNeg = rot.x < 0 or rot.y < 0 or rot.z < 0

					local right, up = axisToVector(jsonData.xaxis), axisToVector(jsonData.zaxis)
					local quat = quatFromRightUp(right, up)

					local rotQuat = sm.quat.angleAxis(isNeg and math.rad(270) or math.rad(90), absVec(rot))
					local translatedQuat = quat * rotQuat
					local newUp, newRight = sm.quat.getUp(translatedQuat), sm.quat.getRight(translatedQuat)

					jsonData.xaxis = vectorToAxis(newRight)
					jsonData.zaxis = vectorToAxis(newUp)

					local xaxis = shape:getXAxis()
					local yaxis = shape:getYAxis()
					local zaxis = shape:getZAxis()

					if rot.z ~= 0 then -- y
						if isNeg then
							jsonData.pos.x = jsonData.pos.x + zaxis.x
							jsonData.pos.y = jsonData.pos.y + zaxis.y
							jsonData.pos.z = jsonData.pos.z + zaxis.z
						else
							jsonData.pos.x = jsonData.pos.x + xaxis.x
							jsonData.pos.y = jsonData.pos.y + xaxis.y
							jsonData.pos.z = jsonData.pos.z + xaxis.z
						end
					elseif rot.y ~= 0 then -- z
						if isNeg then
							jsonData.pos.x = jsonData.pos.x + yaxis.x
							jsonData.pos.y = jsonData.pos.y + yaxis.y
							jsonData.pos.z = jsonData.pos.z + yaxis.z
						else
							jsonData.pos.x = jsonData.pos.x + xaxis.x
							jsonData.pos.y = jsonData.pos.y + xaxis.y
							jsonData.pos.z = jsonData.pos.z + xaxis.z
						end
					else
						if isNeg then
							jsonData.pos.x = jsonData.pos.x + zaxis.x
							jsonData.pos.y = jsonData.pos.y + zaxis.y
							jsonData.pos.z = jsonData.pos.z + zaxis.z
						else
							jsonData.pos.x = jsonData.pos.x + yaxis.x
							jsonData.pos.y = jsonData.pos.y + yaxis.y
							jsonData.pos.z = jsonData.pos.z + yaxis.z
						end
					end
				end
			end

			local rand = formatCol(randCol())

			refindShapeColors[rand] = sm.color.new(jsonData.color)
			jsonData.color = rand

			self.sv.export.oldJson.bodies[data.i1].childs[data.i2] = jsonData
		else
			for i, shape in pairs(self.sv.export.oldShapes) do
				shape:destroyShape()
			end

			local count = 0

			for i, shape in pairs(self.sv.export.oldBody:getCreationShapes()) do
				if shape.interactable then
					count = count + 1
				end
			end

			count = count + #self.sv.export.oldBody:getCreationJoints()

			self.sv.queue = {
				count = count,
				tick = sm.game.getCurrentTick(),
				player = player
			}

			self.network:sendToClient(player, "cl_closeGui")

			return
		end
	end

	for i, data in pairs(self.sv.export.exportedJointIndexes) do
		local jsonData = self.sv.export.json[data.i2]

		if jsonData then
			local specialInstruction = self.sv.export.specialInstruction

			if specialInstruction then
				if specialInstruction.name == "move" then
					jsonData.posA.x = jsonData.posA.x + specialInstruction.data.x
					jsonData.posA.y = jsonData.posA.y + specialInstruction.data.y
					jsonData.posA.z = jsonData.posA.z + specialInstruction.data.z

					jsonData.posB.x = jsonData.posB.x + specialInstruction.data.x
					jsonData.posB.y = jsonData.posB.y + specialInstruction.data.y
					jsonData.posB.z = jsonData.posB.z + specialInstruction.data.z
				end

				if specialInstruction.name == "wonkify" then
					if sm.shape.getShapeTitle(sm.uuid.new(jsonData.shapeId)):sub(1, 6) == "Piston" then
						local zaxisA = jsonData.zaxisA
						
						jsonData.zaxisB = zaxisA
						jsonData.xaxisA = zaxisA
						jsonData.xaxisB = zaxisA
					else
						jsonData.xaxisA = jsonData.zaxisA
						jsonData.xaxisB = jsonData.zaxisA
					end
				end

				if specialInstruction.name == "stack" then
					local newJson = deepCopy(jsonData)
					local isPiston = jsonData.controller

					local jid = 0
					local pid = 0

					for i, joint in pairs(self.sv.export.oldJson.joints) do
						if joint.controller and joint.controller.id > pid then
							pid = joint.controller.id
						end

						if joint.id > jid then
							jid = joint.id
						end
					end

					if isPiston then
						newJson.controller.id = pid + 1
					end

					newJson.id = jid + 1

					local newRand = formatCol(randCol())

					refindJointColors[newRand] = sm.color.new(newJson.color)
					newJson.color = newRand

					table.insert(self.sv.export.oldJson.joints, newJson)

					if isPiston then
						findIds[jsonData.controller.id] = {newId = newJson.controller.id}
						findIds[jsonData.id] = {newId = newJson.id}
					else
						findIds[jsonData.id] = {newId = newJson.id}
					end
				end
			end

			--local newChildA = getNewParent(jsonData, self.sv.export.oldJson)
			--jsonData.childA = newChildA

			local rand = formatCol(randCol())

			refindJointColors[rand] = sm.color.new(jsonData.color)
			jsonData.color = rand
		else
			local joint = self.sv.export.oldJson.joints[data.i1]
			findIds[joint.id] = {isDeleting = true}

			local controller = joint.controller

			if controller then
				findIds[joint.controller.id] = {isDeleting = true}
			end
		end

		self.sv.export.oldJson.joints[data.i1] = jsonData
	end

	if getLength(findIds) > 0 then
		for i, body in pairs(self.sv.export.oldJson.bodies) do
			for i, child in pairs(body.childs) do
				if child.controller then
					if child.controller.joints then
						for i, data in pairs(child.controller.joints) do
							local find = findIds[data.id]

							if find then
								if find.isDeleting then
									child.controller.joints[i] = nil
								else
									local newData = deepCopy(data)

									newData.id = find.newId
									newData.index = #child.controller.joints

									if newData.index < 10 then
										table.insert(child.controller.joints, newData)
									end
								end
							end
						end
					elseif child.controller.controllers then
						for i, data in pairs(child.controller.controllers) do
							local find = findIds[data.id]

							if find then
								if find.isDeleting then
									child.controller.controllers[i] = nil
								else
									local newData = deepCopy(data)

									newData.id = find.newId

									if data.index then
										newData.index = #child.controller.controllers

										if newData.index < 10 then
											table.insert(child.controller.controllers, newData)
										end
									else
										table.insert(child.controller.controllers, newData)
									end
								end
							end
						end
					end
				end
			end
		end
	end

	self.sv.export.specialInstruction = nil

	local isLifted = self.sv.export.oldBody:isOnLift()

	if not isLifted then
		local transformCreation = sm.creation.exportToTable(self.sv.export.oldBody, true, self.sv.export.oldBody:isOnLift())

		for i, body in pairs(transformCreation.bodies) do
			self.sv.export.oldJson.bodies[i].transform = body.transform
		end
	end

	self.sv.export.creation = sm.creation.importFromString(sm.world.getCurrentWorld(), sm.json.writeJsonString(self.sv.export.oldJson), _, _, true)

	if self.sv.export.creation then
		local exportBody

		for i, body in pairs(self.sv.export.creation) do
			if sm.exists(body) then
				exportBody = body
				break
			end
		end

		if isLifted then
			local liftPlayer = player

			if getLength(liftData) > 1 then
				local randomShape = self.sv.export.oldBody:getCreationShapes()[1]

				for playerId, lift in pairs(liftData) do
					for i, shape in pairs(lift.selectedShapes) do
						if sm.exists(shape) and sm.exists(randomShape) and shape.body.id == randomShape.body.id then
							liftPlayer = lift.player
						end
					end
				end
			end

			local hookedLift = liftData[player.id]
			local lowest
			local highest

			for i, body in pairs(self.sv.export.creation) do
				local low, high = body:getWorldAabb()

				if not lowest then 
					lowest = low 
				end
				if not highest then 
					highest = high 
				end

				lowest = lowest:min(low)
				highest = highest:max(high)
			end

			local bb = highest - lowest
			local creationCenter = lowest + (bb) / 2
			local difference = (creationCenter - hookedLift.liftPosition / 4) * 4

			if difference.x >= -1 and difference.x < 0 then 
				difference.x = 0 
			elseif difference.x <= 1 and difference.x > 0 then
				difference.x = 0 
			end

			if difference.y >= -1 and difference.y < 0 then 
				difference.y = 0 
			elseif  difference.y <= 1 and difference.y > 0 then
				difference.y = 0 
			end

			difference.z = 0

			for i, shape in pairs(self.sv.export.oldBody:getCreationShapes()) do
				shape:destroyShape()
			end

			sm.player.placeLift(liftPlayer, self.sv.export.creation, hookedLift.liftPosition + difference, hookedLift.liftLevel, hookedLift.rotationIndex)

			self:sv_refindImported(refindShapeColors, refindJointColors, exportBody, player)
		else
			for i, shape in pairs(self.sv.export.oldBody:getCreationShapes()) do
				shape:destroyShape()
			end

			self:sv_refindImported(refindShapeColors, refindJointColors, exportBody, player)
		end
	else
		self.network:sendToClient(player, "cl_chatMessage", "#ff0000Failed to import creation")

		self:sv_importErrorReset(player)
	end
end

function editor:sv_importBackup(json, player, pos)
	local creation = sm.creation.importFromString(sm.world.getCurrentWorld(), json, _, _, true)

	if creation then
		local liftPlayer = player

		if liftData and getLength(liftData) > 0 then
			local randomShape = self.sv.export.oldBody:getCreationShapes()[1]

			for playerId, lift in pairs(liftData) do
				for i, shape in pairs(lift.selectedShapes) do
					if sm.exists(shape) and sm.exists(randomShape) and shape.body.id == randomShape.body.id then
						liftPlayer = lift.player
					end
				end
			end
		

			local hookedLift = liftData[player.id]
			local lowest
			local highest

			for i, body in pairs(creation) do
				local low, high = body:getWorldAabb()

				if not lowest then 
					lowest = low 
				end
				if not highest then 
					highest = high 
				end

				lowest = lowest:min(low)
				highest = highest:max(high)
			end

			local bb = highest - lowest
			local creationCenter = lowest + (bb) / 2
			local difference = (creationCenter - hookedLift.liftPosition / 4) * 4

			if difference.x >= -1 and difference.x < 0 then 
				difference.x = 0 
			elseif difference.x <= 1 and difference.x > 0 then
				difference.x = 0 
			end

			if difference.y >= -1 and difference.y < 0 then 
				difference.y = 0 
			elseif  difference.y <= 1 and difference.y > 0 then
				difference.y = 0 
			end

			difference.z = 0

			for i, shape in pairs(self.sv.export.oldBody:getCreationShapes()) do
				shape:destroyShape()
			end

			sm.player.placeLift(liftPlayer, creation, hookedLift.liftPosition + difference, hookedLift.liftLevel, hookedLift.rotationIndex)
		else
			for i, shape in pairs(self.sv.export.oldBody:getCreationShapes()) do
				shape:destroyShape()
			end

			sm.player.placeLift(liftPlayer, creation, pos, 0, 0)
		end

		self:sv_importErrorReset(player)
		self.network:sendToClient(player, "cl_closeGui")
	else
		self.network:sendToClient(player, "cl_chatMessage", "#ff0000Failed to import backup")
	end
end

function editor:sv_rebuildBackup(data, player)
    if data.i == 1 then
        self.sv.backupJson = data.string
    else
        self.sv.backupJson = self.sv.backupJson..data.string
    end

    if data.finished then
        self:sv_importBackup(self.sv.backupJson, player, data.pos)
    end
end

function editor:sv_importErrorReset(player)
	self.sv.queue.data = nil
	self.sv.queue.valid = true

	self.network:sendToClient(player, "cl_setJsonSet", true)
	self.network:sendToClient(player, "cl_setQueueValid", true)

	self.sv.export.buttonMove = nil
	self.sv.export.buttonBound = nil
	self.sv.export.buttonRotate = nil
end

function editor:server_onFixedUpdate()
	if not self.sv.queue.valid and self.sv.queue.count then
		if math.max(self.sv.queue.count / 30, 10) + self.sv.queue.tick <= sm.game.getCurrentTick() then
			local data = self.sv.queue.data

			if data then
				local exportBody = sm.exists(self.sv.queue.body) and self.sv.queue.body or nil

				if not exportBody then
					for i, shape in pairs(data.shapes) do
						if sm.exists(shape) then
							local body = shape.body

							if sm.exists(body) then
								exportBody = body
								break
							end
						end
					end

					if not exportBody then
						for i, joint in pairs(data.joints) do
							if sm.exists(joint) then
								local bodyA = joint.shapeA.body

								if sm.exists(bodyA) then
									exportBody = bodyA
									break
								end

								if joint.shapeB then
									if sm.exists(joint.shapeB.body) then
										exportBody = joint.shapeB.body
										break
									end
								end
							end
						end
					end
				end

				self.sv.queue.data.body = exportBody
				
				self:sv_exportSelected(self.sv.queue.data, self.sv.queue.player)
			end

			self.sv.queue.valid = true
			self.network:sendToClient(self.sv.queue.player, "cl_setQueueValid", true)
		end
	end
end

function editor:sv_setSpecialInstruction(data)
	self.sv.export.specialInstruction = data
end

function editor:sv_refindImported(refindShapeColors, refindJointColors, body, player)
	local foundShapes, foundJoints = {}, {}
	local count = 0

	for i, shape in pairs(body:getCreationShapes()) do
		local color = refindShapeColors[formatCol(shape.color)]

		if color then
			shape.color = color
			table.insert(foundShapes, shape)
		end

		if shape.interactable then
			count = count + 1
		end
	end

	for i, joint in pairs(body:getCreationJoints()) do
		local color = refindJointColors[formatCol(joint.color)]

		if color then
			joint.color = color
			table.insert(foundJoints, joint)
		end
		count = count + 1
	end

	if self.sv.effect.pointerUpdate then
		local host = foundShapes[1] or foundJoints[1]

		self.network:sendToClient(player, "cl_setPointerShape", host)
		self.sv.effect.pointerUpdate = false
	end

	if #foundShapes > 0 or #foundJoints > 0 then
		self.sv.queue = {
			data = {
				shapes = foundShapes,
				joints = foundJoints,
				body = body
			},
			count = count,
			player = player,
			tick = sm.game.getCurrentTick()
		}

		self.network:sendToClient(player, "cl_setPostImportData", {shapes = foundShapes, joints = foundJoints})
	else
		self.sv.queue = {
			count = count,
			tick = sm.game.getCurrentTick(),
			player = player
		}

		self.network:sendToClient(player, "cl_closeGui")
	end
end

function editor:sv_updatePointer()
	self.sv.effect.pointerUpdate = true
end

function editor:sv_deletedJson(_, player)
	self.sv.export.json = {}

	self:sv_importJson(player)
end

function editor:sv_setQueueValid(bool)
	self.sv.queue.valid = bool
end

function editor:sv_setLiftLevel(level, player)
	liftData[player.id].liftLevel = level
end

function editor:sv_setBackupEnabled(bool)
	self.sv.backups.isEnabled = bool
end

-- CLIENT --

function editor:client_onCreate()
	self:cl_loadAnimations()

	self.cl = {
		effect = {
			pointerEffect = sm.effect.createEffect("ShapeRenderable"),
			selectedShapeEffects = {},
			selectedJointEffects = {},

			shapeDetails = {},
			jointDetails = {}
		},
		selectedShapes = {},
		selectedJoints = {},
		export = {},
		lift = {},
		queue = {
			valid = true
		},
		color = {
			rgb = sm.color.new(0, 0, 0, 0),
			isValid = true,
			hex = "000000",
			extraVisible = false
		},
		backups = {},
		rotationAxis = false,
		backupText = ""
	}

	self.cl.effect.pointerEffect:setParameter("visualization", true)

	self.cl.gui = sm.gui.createGuiFromLayout("$CONTENT_DATA/Gui/Layouts/Json_Editor_Layout_Side.layout")
	self.cl.gui:setOnCloseCallback("cl_onClose")

	self.cl.gui:setButtonCallback("Done", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("xUp", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("xDown", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("yUp", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("yDown", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("zUp", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("zDown", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("xUpB", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("xDownB", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("yUpB", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("yDownB", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("zUpB", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("zDownB", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("xCw", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("xACw", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("yCw", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("yACw", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("zCw", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("zACw", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("wonkify", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("stack", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("Replace All", "cl_onSub")
    self.cl.gui:setButtonCallback("Replace Next", "cl_onSub")
	self.cl.gui:setButtonCallback("Close", "cl_closeGui")
	self.cl.gui:setButtonCallback("Rotation Axis", "cl_axisChange")
	self.cl.gui:setButtonCallback("copyFind", "cl_copyTo")
	self.cl.gui:setButtonCallback("copyReplace", "cl_copyTo")
	self.cl.gui:setButtonCallback("applyAll", "cl_applyAll")
	self.cl.gui:setButtonCallback("expandColors", "cl_onExpand")
	self.cl.gui:setButtonCallback("backupLoad", "cl_onBackupLoad")

    self.cl.gui:setTextChangedCallback("Json", "cl_onChange")
	self.cl.gui:setTextChangedCallback("Find", "cl_onChange")
    self.cl.gui:setTextChangedCallback("Replace", "cl_onChange")
	self.cl.gui:setTextChangedCallback("hexText", "cl_onHexUpdate")
	self.cl.gui:setTextChangedCallback("backupSelect", "cl_onBackupChange")

	self.cl.gui:createHorizontalSlider("rSlider", 256, 0, "cl_onRSliderUpdate")
	self.cl.gui:createHorizontalSlider("gSlider", 256, 0, "cl_onGSliderUpdate")
	self.cl.gui:createHorizontalSlider("bSlider", 256, 0, "cl_onBSliderUpdate")

	self.cl.settingsGui = sm.gui.createGuiFromLayout("$CONTENT_DATA/Gui/Layouts/Tool_Settings.layout")
	self.cl.settingsGui:setButtonCallback("Close", "cl_closeSettings")
	self.cl.settingsGui:setButtonCallback("effectQuality", "cl_onSettingChange")
	self.cl.settingsGui:setButtonCallback("creationBackups", "cl_onSettingChange")
	self.cl.settingsGui:setButtonCallback("axisType", "cl_onSettingChange")

	for i = 1, 40 do
		if i < 10 then
			self.cl.gui:setButtonCallback("0"..i.."_paintColor", "cl_setPaintColor")
		else
			self.cl.gui:setButtonCallback(i.."_paintColor", "cl_setPaintColor")
		end

		self.cl.gui:setColor(i.."_paintIcon", sm.color.new(PAINT_COLORS[i]))
	end

	local json = sm.json.open(backupDir.."backupCache.json")
	local backupText = ""

	for i = 1, 10 do
		local data = json[i]

		if data then
			self.cl.backups[i] = data
			backupText = backupText.." "..i.." - "..data.name.."\n"
		else
			backupText = backupText.." "..i.." -\n"
		end
	end

	if backupText ~= "" then
		self.cl.gui:setText("backupList", backupText)
	end

	local settingsTbl = sm.json.open(settingsDir)

	self.cl.backupisEnabled = settingsTbl.creationBackups
	self.network:sendToServer("sv_setBackupEnabled", self.cl.backupisEnabled)
	self.cl.gui:setVisible("backupPannel", self.cl.backupisEnabled)

	if self.cl.backupisEnabled then
		self.cl.settingsGui:setText("creationBackups", "#00aa00Enabled")
	else
		self.cl.settingsGui:setText("creationBackups", "#aa0000Disabled")
	end

	self.cl.effect.isFancy = settingsTbl.fancyEffects

	if self.cl.effect.isFancy then
		self.cl.settingsGui:setText("effectQuality", "Fancy")
	else
		self.cl.settingsGui:setText("effectQuality", "Fast")
	end

	self.cl.effect.xEffect = sm.gui.createWorldIconGui(20, 20, "$GAME_DATA/Gui/Layouts/Hud/Hud_WorldIcon.layout", false)
	self.cl.effect.yEffect = sm.gui.createWorldIconGui(20, 20, "$GAME_DATA/Gui/Layouts/Hud/Hud_WorldIcon.layout", false)
	self.cl.effect.zEffect = sm.gui.createWorldIconGui(20, 20, "$GAME_DATA/Gui/Layouts/Hud/Hud_WorldIcon.layout", false)

	self.cl.effect.xLine = sm.effect.createEffect2D("ShapeRenderable")
	self.cl.effect.yLine = sm.effect.createEffect2D("ShapeRenderable")
	self.cl.effect.zLine = sm.effect.createEffect2D("ShapeRenderable")

	self.cl.effect.xEffect:setImage("Icon", "$CONTENT_DATA/Gui/HUD/x.png")
	self.cl.effect.yEffect:setImage("Icon", "$CONTENT_DATA/Gui/HUD/y.png")
	self.cl.effect.zEffect:setImage("Icon", "$CONTENT_DATA/Gui/HUD/z.png")

	self.cl.effect.xLine:setParameter("uuid", plasticUuid)
	self.cl.effect.yLine:setParameter("uuid", plasticUuid)
	self.cl.effect.zLine:setParameter("uuid", plasticUuid)

	self.cl.effect.xLine:setParameter("color", sm.color.new("ff0000"))
	self.cl.effect.yLine:setParameter("color", sm.color.new("00ff00"))
	self.cl.effect.zLine:setParameter("color", sm.color.new("0000ff"))

	self.cl.effect.xEffect:setColor("Icon", sm.color.new("#ff0000"))
	self.cl.effect.yEffect:setColor("Icon",  sm.color.new("#00ff00"))
	self.cl.effect.zEffect:setColor("Icon",  sm.color.new("#0000ff"))

	self.cl.effect.xEffect:open()
	self.cl.effect.yEffect:open()
	self.cl.effect.zEffect:open()
end

function editor:cl_loadAnimations()

	self.tpAnimations = createTpAnimations(
		self.tool,
		{
			idle = { "connecttool_idle" },
			pickup = { "connecttool_pickup", { nextAnimation = "idle" } },
			putdown = { "connecttool_putdown" },
		}
	)
	local movementAnimations = {
		idle = "connecttool_idle",
		idleRelaxed = "connecttool_idle_relaxed",

		sprint = "connecttool_sprint",
		runFwd = "connecttool_run_fwd",
		runBwd = "connecttool_run_bwd",

		jump = "connecttool_jump",
		jumpUp = "connecttool_jump_up",
		jumpDown = "connecttool_jump_down",

		land = "connecttool_jump_land",
		landFwd = "connecttool_jump_land_fwd",
		landBwd = "connecttool_jump_land_bwd",

		crouchIdle = "connecttool_crouch_idle",
		crouchFwd = "connecttool_crouch_fwd",
		crouchBwd = "connecttool_crouch_bwd"
	}

	for name, animation in pairs( movementAnimations ) do
		self.tool:setMovementAnimation( name, animation )
	end

	setTpAnimation( self.tpAnimations, "idle", 5.0 )

	if self.tool:isLocal() then
		self.fpAnimations = createFpAnimations(
			self.tool,
			{
				equip = { "connecttool_pickup", { nextAnimation = "idle" } },
				unequip = { "connecttool_putdown" },

				idle = { "connecttool_idle", { looping = true } },
				idleFlip = { "connecttool_idle_flip", { nextAnimation = "idle", blendNext = 0.5 } },
				idleUse = { "connecttool_use_idle", { nextAnimation = "idle", blendNext = 0.5 } },

				sprintInto = { "connecttool_sprint_into", { nextAnimation = "sprintIdle",  blendNext = 5.0 } },
				sprintExit = { "connecttool_sprint_exit", { nextAnimation = "idle",  blendNext = 0 } },
				sprintIdle = { "connecttool_sprint_idle", { looping = true } },
			}
		)
	end
	self.blendTime = 0.2
end

function editor:cl_onAnimUpdate(dt)
	local isSprinting =  self.tool:isSprinting()
	local isCrouching =  self.tool:isCrouching()

	if self.tool:isLocal() then
		if self.equipped then
			if self.fpAnimations.currentAnimation ~= "idleFlip" then
				if isSprinting and self.fpAnimations.currentAnimation ~= "sprintInto" and self.fpAnimations.currentAnimation ~= "sprintIdle" then
					swapFpAnimation( self.fpAnimations, "sprintExit", "sprintInto", 0.0 )
				elseif not self.tool:isSprinting() and ( self.fpAnimations.currentAnimation == "sprintIdle" or self.fpAnimations.currentAnimation == "sprintInto" ) then
					swapFpAnimation( self.fpAnimations, "sprintInto", "sprintExit", 0.0 )
				end
			end
		end
		updateFpAnimations( self.fpAnimations, self.equipped, dt )
	end

	if not self.equipped then
		if self.wantEquipped then
			self.wantEquipped = false
			self.equipped = true
		end
		return
	end

	for name, animation in pairs( self.tpAnimations.animations ) do
		animation.time = animation.time + dt

		if name == self.tpAnimations.currentAnimation then
			if animation.time >= animation.info.duration - self.blendTime then
				if name == "pickup" then
					setTpAnimation( self.tpAnimations, "idle", 0.001 )
				elseif animation.nextAnimation ~= "" then
					setTpAnimation( self.tpAnimations, animation.nextAnimation, 0.001 )
				end
			end
		end
	end
end

function editor:client_onUpdate(dt)
	self:cl_onAnimUpdate(dt)
	
	if self.tool:isLocal() and self.tool:isEquipped() then
		local selectedShape = self.cl.effect.selectedShape

		if selectedShape and not self.cl.deselect then
			if sm.exists(selectedShape) then
				local isShape = type(selectedShape) == "Shape"

				if self.cl.effect.pointerEffect:isPlaying() then 
					self.cl.effect.pointerEffect:stop()
				end

				if selectedShape.id ~= self.cl.effect.lastSelectedId then
					self.cl.effect.lastSelectedId = selectedShape.id

					if isShape then
						local uuid, scale = getEffectData(selectedShape)

						self.cl.effect.pointerEffect:setParameter("uuid", uuid)
						self.cl.effect.pointerEffect:setScale(scale)
					end
				end

				local position = isShape and selectedShape:getInterpolatedWorldPosition()
				local rotation = selectedShape:getWorldRotation()
				local velocity = isShape and selectedShape.velocity or selectedShape.shapeA.velocity

				if not isShape then
					local uuid, scale = getEffectData(selectedShape)

					self.cl.effect.pointerEffect:setParameter("uuid", uuid)
					self.cl.effect.pointerEffect:setScale(scale)
					self.cl.effect.pointerEffect:setRotation(rotation)

					position = getJointEffectPosiiton(selectedShape)
				else
					local at, right, up = rotateVectors(selectedShape:getInterpolatedAt(), selectedShape:getInterpolatedRight(), selectedShape:getInterpolatedUp(), selectedShape.body.angularVelocity, dt)
					self.cl.effect.pointerEffect:setRotation(better_quat_rotation(at, right, up))
				end

				self.cl.effect.pointerEffect:setPosition(position + velocity * dt)

				self.cl.effect.pointerEffect:start()

				if not self.cl.multiSelected then
					self.cl.effect.originPosition = selectedShape.worldPosition
				end
			end
		else
			if self.cl.effect.pointerEffect:isPlaying() then
				self.cl.effect.pointerEffect:stop()
			end

			--self.cl.effect.originPosition = nil
		end

		local tick = sm.game.getCurrentTick()

		if self.cl.effect.isFancy or tick ~= self.cl.lastTick then
			self.cl.lastTick = tick

			if getLength(self.cl.selectedShapes) > 0 then
				for i, shape in pairs(self.cl.selectedShapes) do
					local effect = self.cl.effect.selectedShapeEffects[i]

					if sm.exists(shape) then
						local uuid, scale = getEffectData(shape)

						local position
						local rotation

						if self.cl.effect.isFancy then
							local at, right, up = rotateVectors(shape:getInterpolatedAt(), shape:getInterpolatedRight(), shape:getInterpolatedUp(), shape.body.angularVelocity, dt)
							
							rotation = better_quat_rotation(at, right, up)
							position = shape:getInterpolatedWorldPosition() + shape.velocity * dt
						else
							rotation = shape.worldRotation
							position = shape.worldPosition
						end

						if not sm.exists(effect) then
							effect = sm.effect.createEffect("ShapeRenderable")

							effect:setParameter("visualization", true)
							effect:setParameter("uuid", uuid)
							effect:setScale(scale)

							self.cl.effect.shapeDetails[i] = {}

							self.cl.effect.shapeDetails[i].uuid = uuid
							self.cl.effect.shapeDetails[i].scale = scale

							self.cl.effect.selectedShapeEffects[i] = effect
							self.cl.effect.selectedShapeEffects[i]:start()
						end

						local lastPos = self.cl.effect.shapeDetails[i].position
						local lastRot = self.cl.effect.shapeDetails[i].rotation
						local lastUuid = self.cl.effect.shapeDetails[i].uuid
						local lastScale = self.cl.effect.shapeDetails[i].scale

						if not lastPos or lastPos ~= position then
							effect:setPosition(position)

							self.cl.effect.shapeDetails[i].position = position
						end

						if not lastRot or lastRot ~= rotation then
							effect:setRotation(rotation)

							self.cl.effect.shapeDetails[i].rotation = rotation
						end

						if not lastUuid or lastUuid ~= uuid then
							effect:setParameter("uuid", uuid)

							self.cl.effect.shapeDetails[i].uuid = uuid
						end

						if not lastScale or lastScale ~= scale then
							effect:setScale(scale)

							self.cl.effect.shapeDetails[i].scale = scale
						end
					else
						if effect then
							effect:destroy()
						end

						self.cl.effect.selectedShapeEffects[i] = nil
						self.cl.selectedShapes[i] = nil
						
						self.cl.effect.shapeDetails[i] = nil
					end
				end
			end

			if getLength(self.cl.selectedJoints) > 0 then
				for i, joint in pairs(self.cl.selectedJoints) do
					local effect = self.cl.effect.selectedJointEffects[i]

					if sm.exists(joint) then
						local uuid, scale = getEffectData(joint)

						local position = getJointEffectPosiiton(joint)
						local rotation = joint:getWorldRotation()

						if not effect or not sm.exists(effect) then
							effect = sm.effect.createEffect("ShapeRenderable")

							effect:setParameter("visualization", true)
							effect:setParameter("uuid", uuid)
							effect:setScale(scale)

							self.cl.effect.jointDetails[i] = {}

							self.cl.effect.jointDetails[i].uuid = uuid
							self.cl.effect.jointDetails[i].scale = scale

							self.cl.effect.selectedJointEffects[i] = effect
							self.cl.effect.selectedJointEffects[i]:start()
						end

						local lastUuid = self.cl.effect.jointDetails[i].uuid
						local lastScale = self.cl.effect.jointDetails[i].scale
						local lastPos = self.cl.effect.jointDetails[i].position
						local lastRot = self.cl.effect.jointDetails[i].rotation

						if not lastUuid or lastUuid ~= uuid then
							if effect:isPlaying() then
								effect:stop()
							end

							effect:setParameter("uuid", uuid)

							self.cl.effect.jointDetails[i].uuid = uuid
						end

						if not lastScale or lastScale ~= scale then
							if effect:isPlaying() then
								effect:stop()
							end

							effect:setScale(scale)

							self.cl.effect.jointDetails[i].scale = scale
						end

						if not lastPos or lastPos ~= position then
							effect:setPosition(position) 

							self.cl.effect.jointDetails[i].position = position
						end

						if not lastRot or lastRot ~= rotation then
							effect:setRotation(rotation)

							self.cl.effect.jointDetails[i].rotation = rotation
						end

						if not effect:isPlaying() then
							effect:start()
						end
					else
						if effect then
							effect:destroy()
						end

						self.cl.effect.selectedJointEffects[i] = nil
						self.cl.selectedJoints[i] = nil
						
						self.cl.effect.jointDetails[i] = nil
					end
				end
			end
		end

		if self.cl.multiSelected then
			local position = sm.vec3.zero()
			local count = getLength(self.cl.selectedJoints) + getLength(self.cl.selectedShapes)

			self.cl.lastCount = count

			for i, shape in pairs(self.cl.selectedShapes) do
				if sm.exists(shape) then
					position = position + shape.worldPosition
				else
					self.cl.selectedShapes[i] = nil
				end
			end

			for i, joint in pairs(self.cl.selectedJoints) do
				if sm.exists(joint) then
					position = position + joint.worldPosition
				else
					self.cl.selectedJoints[i] = nil
				end
			end

			if count ~= 0 then
				self.cl.effect.originPosition = position / count
			end
		end

		if self.cl.effect.originPosition then
			if not self.cl.effect.xEffect:isActive() then
				self.cl.effect.xEffect:open()
				self.cl.effect.yEffect:open()
				self.cl.effect.zEffect:open()
			end

			local firstShape = returnFirst(self.cl.selectedShapes)
			local firstJoint = returnFirst(self.cl.selectedJoints)
			local shape

			if sm.exists(selectedShape) then
				shape = selectedShape
			elseif sm.exists(firstShape) then
				shape = firstShape
			elseif sm.exists(firstJoint) then
				shape = firstjoint
			end

			if shape then
				local isShape = type(shape) == "Shape"

				local bodyRotation = isShape and shape.body.worldRotation or shape.shapeA.body.worldRotation
				local shapeRotation = isShape and shape.worldRotation or shape.shapeA.worldRotation
				local rotation = self.cl.rotationAxis and shapeRotation or bodyRotation

				local xPos, yPos, zPos = self.cl.effect.originPosition + rotation * sm.vec3.new(0.5, 0, 0),
										 self.cl.effect.originPosition + rotation * sm.vec3.new(0, 0.5, 0),
										 self.cl.effect.originPosition + rotation * sm.vec3.new(0, 0, 0.5)

				if self.cl.lastAxis ~= self.cl.rotationAxis then
					self.cl.lastAxis = self.cl.rotationAxis

					if self.cl.rotationAxis then
						self.cl.effect.xEffect:setColor("Icon", sm.color.new("00ffff"))
						self.cl.effect.yEffect:setColor("Icon", sm.color.new("ff00ff"))
						self.cl.effect.zEffect:setColor("Icon", sm.color.new("ffff00"))

						self.cl.effect.xLine:setParameter("color", sm.color.new("00ffff"))
						self.cl.effect.yLine:setParameter("color", sm.color.new("ff00ff"))
						self.cl.effect.zLine:setParameter("color", sm.color.new("ffff00"))
					else
						self.cl.effect.xEffect:setColor("Icon", sm.color.new("ff0000"))
						self.cl.effect.yEffect:setColor("Icon", sm.color.new("00ff00"))
						self.cl.effect.zEffect:setColor("Icon", sm.color.new("0000ff"))

						self.cl.effect.xLine:setParameter("color", sm.color.new("ff0000"))
						self.cl.effect.yLine:setParameter("color", sm.color.new("00ff00"))
						self.cl.effect.zLine:setParameter("color", sm.color.new("0000ff"))
					end
				end

				self.cl.effect.xEffect:setWorldPosition(xPos)
				self.cl.effect.yEffect:setWorldPosition(yPos)
				self.cl.effect.zEffect:setWorldPosition(zPos)

				drawLine(self.cl.effect.originPosition, xPos, self.cl.effect.xLine)
				drawLine(self.cl.effect.originPosition, yPos, self.cl.effect.yLine)
				drawLine(self.cl.effect.originPosition, zPos, self.cl.effect.zLine)
			else
				self.cl.effect.xEffect:close()
				self.cl.effect.yEffect:close()
				self.cl.effect.zEffect:close()

				self.cl.effect.xLine:stop()
				self.cl.effect.yLine:stop()
				self.cl.effect.zLine:stop()

				self.cl.effect.pointerEffect:stop()
			end
		else
			self.cl.effect.xEffect:close()
			self.cl.effect.yEffect:close()
			self.cl.effect.zEffect:close()

			self.cl.effect.xLine:stop()
			self.cl.effect.yLine:stop()
			self.cl.effect.zLine:stop()
		end
	end
end

function editor:client_onFixedUpdate()
	local lift = localPlayer.getOwnedLift()

	if lift and liftData and liftData[localPlayer.getPlayer().id] then
		local level = lift.level

		if level ~= self.cl.liftLevel then
			self.cl.liftLevel = level
			self.network:sendToServer("sv_setLiftLevel", level)
		end
	end

	if self.cl.closeLockout and self.cl.closeLockout + 10 < sm.game.getCurrentTick() then
		self.cl.closeLockout = nil
	end
end

function editor:client_onToggle()
	self.cl.settingsGui:open()

	return true
end

function editor:cl_closeSettings()
	self.cl.settingsGui:close()
end

function editor:client_onEquip()
	sm.audio.play("ConnectTool - Equip")
	self.wantEquipped = true
	self.jointWeight = 0.0

	currentRenderablesTp = {}
	currentRenderablesFp = {}

	for k,v in pairs( renderablesTp ) do currentRenderablesTp[#currentRenderablesTp+1] = v end
	for k,v in pairs( renderablesFp ) do currentRenderablesFp[#currentRenderablesFp+1] = v end
	for k,v in pairs( renderables ) do currentRenderablesTp[#currentRenderablesTp+1] = v end
	for k,v in pairs( renderables ) do currentRenderablesFp[#currentRenderablesFp+1] = v end
	self.tool:setTpRenderables( currentRenderablesTp )

	self:cl_loadAnimations()

	setTpAnimation( self.tpAnimations, "pickup", 0.0001 )

	if self.tool:isLocal() then
		self.tool:setFpRenderables( currentRenderablesFp )
		swapFpAnimation( self.fpAnimations, "unequip", "equip", 0.2 )
	end
end

function editor:client_onUnequip()
	sm.audio.play("ConnectTool - Unequip")

	self.wantEquipped = false
	self.equipped = false

	if sm.exists( self.tool ) then
		setTpAnimation( self.tpAnimations, "putdown" )
		if self.tool:isLocal() then
			if self.fpAnimations.currentAnimation ~= "unequip" then
				swapFpAnimation( self.fpAnimations, "equip", "unequip", 0.2 )
			end
		end
	end

	if self.cl.effect.pointerEffect:isPlaying() then
		self.cl.effect.pointerEffect:stop()
	end

	destroyEffectTable(self.cl.effect.selectedJointEffects)
	destroyEffectTable(self.cl.effect.selectedShapeEffects)

	self.cl.effect.shapeDetails = {}
	self.cl.effect.jointDetails = {}

	self.cl.selectedJoints = {}
	self.cl.selectedShapes = {}

	self.cl.effect.selectedShapeEffects = {}
	self.cl.effect.selectedJointEffects = {}

	self.cl.effect.xEffect:close()
	self.cl.effect.yEffect:close()
	self.cl.effect.zEffect:close()

	self.cl.effect.xLine:stop()
	self.cl.effect.yLine:stop()
	self.cl.effect.zLine:stop()
end

function editor:client_onReload()
	self.cl.creationSelect = true

	return true
end

function editor:cl_onSettingChange(button)
	local settingsTbl = sm.json.open(settingsDir)

	if button == "effectQuality" then
		self.cl.effect.isFancy = not self.cl.effect.isFancy

		if self.cl.effect.isFancy then
			self.cl.settingsGui:setText("effectQuality", "Fancy")
		else
			self.cl.settingsGui:setText("effectQuality", "Fast")
		end

		settingsTbl.fancyEffects = self.cl.effect.isFancy
	elseif button == "creationBackups" then
		self.cl.backupisEnabled = not self.cl.backupisEnabled
		self.network:sendToServer("sv_setBackupEnabled", self.cl.backupisEnabled)

		if self.cl.backupisEnabled then
			self.cl.settingsGui:setText("creationBackups", "#00aa00Enabled")
			self.cl.gui:setVisible("backupPannel", true)
		else
			self.cl.settingsGui:setText("creationBackups", "#aa0000Disabled")
			self.cl.gui:setVisible("backupPannel", false)
		end

		settingsTbl.creationBackups = self.cl.backupisEnabled
	end

	sm.json.save(settingsTbl, settingsDir)
end

function editor:client_onEquippedUpdate(primary, secondary, forceBuild)
	local filter = sm.physics.filter.joints + sm.physics.filter.dynamicBody + sm.physics.filter.staticBody
	local pos = camera.getPosition()

	local hit, result = sm.physics.raycast(pos, pos + camera.getDirection() * 7.5, localPlayer.getPlayer().character, filter)
	local localHit, localResult = localPlayer.getRaycast(7.5)

	if localHit and localResult.type == "joint" then
		hit, result = localHit, localResult
	end

	local valid

	if hit then
		valid = true

		local type_ = result.type

		local isShape = type_ == "body"
		local selectedShape = isShape and result:getShape() or result:getJoint()
		local selectedBody = isShape and selectedShape.body or selectedShape.shapeA.body

		local multiSelected = getLength(self.cl.selectedShapes) + getLength(self.cl.selectedJoints) > 0

		self.cl.multiSelected = multiSelected

		if not self.cl.gui:isActive() then
			self.cl.effect.selectedShape = selectedShape
		end

		local bodyDeselect = false
		local broke

		for i, shape in pairs(selectedBody:getShapes()) do
			if not self.cl.selectedShapes[shape.id] then
				broke = true
				break
			end
		end

		if not broke then
			for i, joint in pairs(selectedBody:getJoints()) do
				if not self.cl.selectedJoints[joint.id] then
					broke = true
					break
				end
			end

			if not broke then
				bodyDeselect = true
			end
		end

		sm.gui.setInteractionText(createStr, " "..attackStr)

		if bodyDeselect then
			sm.gui.setInteractionText(forceStrDeselect, " "..reloadStr)
		else
			sm.gui.setInteractionText(forceStrSelect, " "..reloadStr)
		end

		if primary == 1 then
			local exportShapes = self.cl.selectedShapes
			local exportJoints = self.cl.selectedJoints

			if not multiSelected then
				exportShapes[1] = isShape and selectedShape or nil
				exportJoints[1] = not isShape and selectedShape or nil
			end

			if getLength(exportJoints) > 0 then
				self.cl.gui:setVisible("Wonky Joint Window", true)
				self.cl.gui:setVisible("Stack Joint Window", true)
			end

			local status, err = pcall(function()
				self.network:sendToServer("sv_exportSelected", {shapes = exportShapes, joints = exportJoints, body = selectedBody})
			end)

			if not status then
				self:cl_chatMessage("#ff0000Selection ammount too large!")
			else
				self.cl.export.wasOpen = false
			end
		end

		if secondary == 1 or secondary == 2 then
			if isShape then
				local shape = self.cl.selectedShapes[selectedShape.id]

				if not shape then
					if secondary == 1 then
						self.cl.deselecting = false
					end

					if not self.cl.deselecting then
						self.cl.selectedShapes[selectedShape.id] = selectedShape
					end
				else
					if secondary == 1 then
						self.cl.deselecting = true
					end

					if self.cl.deselecting then
						self.cl.selectedShapes[selectedShape.id] = nil

						self.cl.effect.selectedShapeEffects[selectedShape.id]:destroy()
						self.cl.effect.selectedShapeEffects[selectedShape.id] = nil

						self.cl.effect.shapeDetails[selectedShape.id] = nil
					end
				end
			else
				local joint = self.cl.selectedJoints[selectedShape.id]

				if not joint then
					if secondary == 1 then
						self.cl.deselecting = false
					end

					if not self.cl.deselecting then
						self.cl.selectedJoints[selectedShape.id] = selectedShape
					end				
				else
					if secondary == 1 then
						self.cl.deselecting = true
					end

					if self.cl.deselecting then
						self.cl.selectedJoints[selectedShape.id] = nil

						self.cl.effect.selectedJointEffects[selectedShape.id]:destroy()
						self.cl.effect.selectedJointEffects[selectedShape.id] = nil
						
						self.cl.effect.jointDetails[selectedShape.id] = nil
					end
				end
			end
		end

		if secondary == 3 then
			self.cl.deselecting = false
		end

		if forceBuild and not self.cl.forceToggle then
			self.cl.forceToggle = true

			for _, shape in pairs(selectedBody:getShapes()) do
				if not bodyDeselect then
					local shapeA = self.cl.selectedShapes[shape.id]

					if not shapeA then
						self.cl.selectedShapes[shape.id] = shape
					end
				else
					self.cl.selectedShapes[shape.id] = nil

					self.cl.effect.selectedShapeEffects[shape.id]:destroy()
					self.cl.effect.selectedShapeEffects[shape.id] = nil
					
					self.cl.effect.shapeDetails[shape.id] = nil
				end
			end

			for _, joint in pairs(selectedBody:getJoints()) do
				if not bodyDeselect then
					local jointA = self.cl.selectedJoints[joint.id]

					if not jointA then
						self.cl.selectedJoints[joint.id] = joint
					end
				else
					self.cl.selectedJoints[joint.id] = nil

					self.cl.effect.selectedJointEffects[joint.id]:destroy()
					self.cl.effect.selectedJointEffects[joint.id] = nil

					self.cl.effect.jointDetails[joint.id] = nil
				end
			end
		elseif not forceBuild and self.cl.forceToggle then
			self.cl.forceToggle = false
		end

		if self.cl.creationSelect then
			self.cl.creationSelect = false

			for _, shape in pairs(selectedBody:getCreationShapes()) do
				local shapeA = self.cl.selectedShapes[shape.id]

				if not shapeA then
					self.cl.selectedShapes[shape.id] = shape
				end
			end

			for _, joint in pairs(selectedBody:getCreationJoints()) do
				local jointA = self.cl.selectedJoints[joint.id]

				if not jointA then
					self.cl.selectedJoints[joint.id] = joint
				end
			end
		end
	else	
		if primary == 1 then
			self.cl.selectedShapes = {}
			self.cl.selectedJoints = {}

			destroyEffectTable(self.cl.effect.selectedShapeEffects)
			destroyEffectTable(self.cl.effect.selectedJointEffects)

			self.cl.effect.selectedShapeEffects = {}
			self.cl.effect.selectedShapeEffects = {}

			self.cl.effect.shapeDetails = {}
			self.cl.effect.jointDetails = {}
		end
	end

	if not valid and not self.cl.gui:isActive() then
		self.cl.effect.selectedShape = nil
	end

	return true, true
end

function editor:client_onDestroy()
	self.cl.selectedShapes = {}
	self.cl.selectedJoints = {}

	destroyEffectTable(self.cl.effect.selectedShapeEffects)
	destroyEffectTable(self.cl.effect.selectedJointEffects)

	self.cl.effect.shapeDetails = {}
	self.cl.effect.jointDetails = {}

	self.cl.effect.selectedShapeEffects = {}
	self.cl.effect.selectedJointEffects = {}

	self.cl.effect.selectedShape = {}
	self.cl.effect.pointerEffect:stop()

	self.cl.effect.xEffect:close()
	self.cl.effect.yEffect:close()
	self.cl.effect.zEffect:close()

	self.cl.effect.xLine:stop()
	self.cl.effect.yLine:stop()
	self.cl.effect.zLine:stop()
end

function editor:cl_rebuildJson(data)
    if data.i == 1 then
        self.cl.export.json = data.string
    else
        self.cl.export.json = self.cl.export.json..data.string
    end

    if data.finished then
        self:cl_openEditMenu()
    end
end

function editor:cl_rebuildBackup(data)
    if data.i == 1 then
        self.cl.backupJson = data.string
    else
        self.cl.backupJson = self.cl.backupJson..data.string
    end

    if data.finished then
        self:cl_saveBackup(self.cl.backupJson)
    end
end

function editor:cl_openEditMenu()
	if (self.cl.export.wasOpen and self.cl.gui:isActive()) or not self.cl.export.wasOpen then
		self.cl.gui:setText("Json", self.cl.export.json)
		self.cl.gui:open()

		self.cl.closeLockout = sm.game.getCurrentTick()
		self.cl.export.jsonSet = true
		self.cl.export.editedJson = self.cl.export.json
	end
end

function editor:cl_onChange(name, text)
    if name == "Json" then
        self.cl.export.editedJson = text
    elseif name == "Find" then
        self.cl.export.findStr = text
    elseif name == "Replace" then
        self.cl.export.replaceStr = text
    end
end

function editor:cl_onButtonPress(button)
	self.network:sendToServer("sv_updatePointer")

	if self.cl.queue.valid and self.cl.export.jsonSet then
		self.cl.queue.valid = false

		self.network:sendToServer("sv_setQueueValid", false)

		self.cl.export.jsonSet = false

		if button ~= "Done" then
			local vec = positionButtonMap[button]
			local bound = boundsButtonMap[button]
			local rot = rotationButtonMap[button]

			if vec then
				self.network:sendToServer("sv_setSpecialInstruction", {name = "move", data = vec})
			elseif bound then
				self.network:sendToServer("sv_setSpecialInstruction", {name = "bound", data = bound})
			elseif rot then
				self.network:sendToServer("sv_setSpecialInstruction", {name = "rotate", data = rot})
			elseif button == "wonkify" then
				self.network:sendToServer("sv_setSpecialInstruction", {name = "wonkify"})
			elseif button == "stack" then
				self.network:sendToServer("sv_setSpecialInstruction", {name = "stack"})
			end
		end

		local json = uglifyJson(self.cl.export.editedJson)

		if json == "" then
			self.network:sendToServer("sv_deletedJson")
		else
			local strings = splitString(json, packetSize)

			for i, string in pairs(strings) do
				local finished = i == #strings
				self.network:sendToServer("sv_rebuildJson", {string = string, finished = finished, i = i})
			end
		end
	end
end

function editor:cl_onRSliderUpdate(value, dontUpdate)
	self.cl.gui:setText("rText", "#ff0000R#eeeeee: "..value)
	self.cl.color.rgb.r = value / 255

	if not dontUpdate then
		self:cl_updateHex(self.cl.color.rgb)
	else
		self.cl.gui:setSliderPosition("rSlider", value)
	end
end

function editor:cl_onGSliderUpdate(value, dontUpdate)
	self.cl.gui:setText("gText", "#00ff00G#eeeeee: "..value)
	self.cl.color.rgb.g = value / 255

	if not dontUpdate then
		self:cl_updateHex(self.cl.color.rgb)
	else
		self.cl.gui:setSliderPosition("gSlider", value)
	end
end

function editor:cl_onBSliderUpdate(value, dontUpdate)
	self.cl.gui:setText("bText", "#0000ffB#eeeeee: "..value)
	self.cl.color.rgb.b = value / 255

	if not dontUpdate then
		self:cl_updateHex(self.cl.color.rgb)
	else
		self.cl.gui:setSliderPosition("bSlider", value)
	end
end

function editor:cl_updateHex(rgb)
	local hex = tostring(rgb):sub(1, 6)

	self.cl.gui:setText("hexText", hex:lower())
	self.cl.color.hex = hex:upper()

	self.cl.gui:setColor("Preview", sm.color.new(hex))
end

function editor:cl_onHexUpdate(_, text)
	if text:match("%x%x%x%x%x%x$") ~= nil then
		self.cl.color.isValid = true
		self.cl.gui:setText("hexText", "#eeeeee"..text)

		self.cl.color.hex = text:upper()

		local r = tonumber(text:sub(1, 2), 16)
		local g = tonumber(text:sub(3, 4), 16)
		local b = tonumber(text:sub(5, 6), 16)

		self:cl_onRSliderUpdate(r, true)
		self:cl_onGSliderUpdate(g, true)
		self:cl_onBSliderUpdate(b, true)

		self.cl.gui:setColor("Preview", sm.color.new(text))
	else
		self.cl.color.isValid = false
		self.cl.gui:setText("hexText", "#ff0000"..text)
	end
end

function editor:cl_applyAll()
	local newJson = replaceHexColor(self.cl.export.editedJson, self.cl.color.hex)

	self.cl.export.editedJson = newJson
	self.cl.gui:setText("Json", self.cl.export.editedJson)
end

function editor:cl_onExpand()
	self.cl.color.extraVisible = not self.cl.color.extraVisible
	self.cl.gui:setVisible("extraColorWindow", self.cl.color.extraVisible)
end

function editor:cl_setPaintColor(button)
	local index

	if button:sub(1, 1) == "0" then
		index = tonumber(button:sub(2, 2))
	else
		index = tonumber(button:sub(1, 2))
	end

	self:cl_onHexUpdate(_, PAINT_COLORS[index]:sub(1, 6))
end

function editor:cl_copyTo(button)
	if self.cl.color.isValid then
		if button == "copyFind" then
			self.cl.gui:setText("Find", self.cl.color.hex)
			self.cl.export.findStr = self.cl.color.hex:upper()
		else
			self.cl.gui:setText("Replace", self.cl.color.hex)
			self.cl.export.replaceStr = self.cl.color.hex
		end
	end
end

function editor:cl_onSub(name) 
	local text = self.cl.export.editedJson:gsub("#%x%x%x%x%x%x", ""):gsub("(%d+%:)", "")
    local count = 0

    local pattern = self.cl.export.findStr:gsub('[%-%.%+%[%]%(%)%$%^%%%?%*]','%%%1')
    local replacement = self.cl.export.replaceStr

    if name == "Replace All" then
        text, count = text:gsub(pattern, replacement)
    else
        text, count = text:gsub(pattern, replacement, 1)
    end

	local status, err = pcall(function()
    	self.cl.export.editedJson = beautifyJson(sm.json.parseJsonString(text))
	end)

	if status then
		if count == 0 then
			sm.gui.displayAlertText("Couldn't find target string")
		else
			sm.gui.displayAlertText("Replaced " .. count .. " occurrence(s)")
		end

		self.cl.gui:setText("Json", self.cl.export.editedJson)
	else
		self:cl_chatMessage("#ff0000"..err:sub(64, #err))
	end
end

function editor:cl_saveBackup(json)
	local date, time = convertTimestamp(os.time())
	local newTable = {}

	for i = 1, 10 do
		newTable[i + 1] = self.cl.backups[i]
	end

	newTable[1] = {name = date.." | "..time.." | GMT"}
	self.cl.backups = newTable

	for i = 9, 1, -1 do
		local path = backupDir.."backup_"..i..".json"

		if sm.json.fileExists(path) then
			local transferJson = sm.json.open(path)

			sm.json.save(transferJson, backupDir.."backup_"..(i + 1)..".json")
		end
	end

	sm.json.save(sm.json.parseJsonString(json), backupDir.."backup_1.json")
	sm.json.save(self.cl.backups, backupDir.."backupCache.json")

	local backupText = ""

	for i = 1, 10 do
		local data = self.cl.backups[i]

		if data then
			backupText = backupText.." "..i.." - "..data.name.."\n"
		else
			backupText = backupText.." "..i.." -\n"
		end
	end

	self.cl.gui:setText("backupList", backupText)
end

function editor:cl_onBackupChange(_, text)
	local number = tonumber(text)
	
	if number then
		if number >= 1 and number <= 10 then
			if self.cl.backups[number] then
				if not self.cl.backupIsValid then
					self.cl.gui:setText("backupError", "")
				end

				self.cl.backupNumber = number
				self.cl.backupIsValid = true
			else
				self.cl.gui:setText("backupError", "#ff0000Backup doesnt exist")
				self.cl.backupIsValid = false
			end
		else
			self.cl.gui:setText("backupError", "#ff0000Selection out of range")
			self.cl.backupIsValid = false
		end
	else
		if text ~= "" then
			self.cl.gui:setText("backupError", "#ff0000Selection must be number")
			self.cl.backupIsValid = false
		else
			self.cl.gui:setText("backupError", "")
		end
	end
end

function editor:cl_onBackupLoad()
	if self.cl.backupIsValid then
		local json = sm.json.open(backupDir.."backup_"..self.cl.backupNumber..".json")
		local strings = splitString(sm.json.writeJsonString(json), packetSize)

		local pos = localPlayer.getPlayer().character.worldPosition - sm.vec3.new(0, 0, 0.5)
		local dir = sm.camera.getDirection()
		dir.z = 0

		for i, string in pairs(strings) do
			local finished = i == #strings
			self.network:sendToServer("sv_rebuildBackup", {string = string, finished = finished, i = i, pos = (pos + dir * 4) * 4})
		end
	end
end

function editor:cl_axisChange(button, userSet)
	self.cl.rotationAxis = not self.cl.rotationAxis
end

function editor:cl_setPointerShape(shape)
	self.cl.effect.selectedShape = shape
end

function editor:cl_setPostImportData(data)
	self.cl.export.wasOpen = true

	destroyEffectTable(self.cl.effect.selectedShapeEffects)
	destroyEffectTable(self.cl.effect.selectedJointEffects)

	self.cl.selectedShapes = data.shapes
	self.cl.selectedJoints = data.joints

	self.cl.effect.shapeDetails = {}
	self.cl.effect.jointDetails = {}

	self.cl.effect.selectedShapeEffects = {}
	self.cl.effect.selectedJointEffects = {}
end

function editor:cl_onClose()
	self.cl.selectedJoints = {}
	self.cl.selectedShapes = {}

	destroyEffectTable(self.cl.effect.selectedShapeEffects)
	destroyEffectTable(self.cl.effect.selectedJointEffects)

	self.cl.effect.selectedShapeEffects = {}
	self.cl.effect.selectedJointEffects = {}

	self.cl.effect.shapeDetails = {}
	self.cl.effect.jointDetails = {}

	self.cl.effect.selectedShape = nil
	self.cl.rotationAxis = false


	self.cl.gui:setVisible("Wonky Joint Window", false)
	self.cl.gui:setVisible("Stack Joint Window", false)
end

function editor:cl_setQueueValid(bool)
	self.cl.queue.valid = bool
end

function editor:cl_setJsonSet(bool)
	self.cl.export.jsonSet = bool
end

function editor:cl_closeGui()
	if not self.cl.closeLockout then
		self.cl.gui:close()
	end
end

function editor:cl_alertText(msg)
	sm.gui.displayAlertText(msg)
end

function editor:cl_chatMessage(msg)
	sm.gui.chatMessage("Error: "..msg)
end

-- HOOKS --

local oldFunc = sm.player.placeLift

function liftHook(player, selectedBodies, liftPosition, liftLevel, rotationIndex)
	if not liftData then liftData = {} end

	liftData[player.id] = {
		player = player,
		selectedBodies = selectedBodies,
		selectedShapes = sm.exists(selectedBodies[1]) and selectedBodies[1]:getCreationShapes() or {},
		liftPosition = liftPosition,
		liftLevel = liftLevel,
		rotationIndex = rotationIndex
	}

	oldFunc(player, selectedBodies, liftPosition, liftLevel, rotationIndex)
end

sm.player.placeLift = liftHook