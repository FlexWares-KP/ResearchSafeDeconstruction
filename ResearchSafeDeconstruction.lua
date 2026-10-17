-- AI assistance disclaimer: This addon was developed with assistance from AI tools.
-- AI-generated suggestions were reviewed and adapted by the author; verify behavior
-- and report issues through the project repository.

local NAME = "ResearchSafeDeconstruction"
local TITLE = "Research Safe Deconstruction"
local LCK = LibCharacterKnowledge

local DEFAULTS = {
	enabled = true,
	showUnsafe = true,
	showOverflow = true,
	excludedCharacters = {},
}

local DECONSTRUCTION_LIST_NAMES = {
	"ZO_SmithingTopLevelDeconstructionPanelInventoryBackpack",
	"ZO_UniversalDeconstructionTopLevel_KeyboardPanelInventoryBackpack",
}

local INDICATOR_TEXTURE = "esoui/art/crafting/smithing_tabicon_improve_up.dds"
local INDICATOR_SIZE = 32
local INDICATOR_OFFSET_X = -32
local CHARACTER_ROW_HEIGHT = 28
local CHARACTER_STATUS_HEIGHT = 28

local BLACKSMITH_WEAPONS = {
	[WEAPONTYPE_AXE] = true,
	[WEAPONTYPE_HAMMER] = true,
	[WEAPONTYPE_SWORD] = true,
	[WEAPONTYPE_TWO_HANDED_AXE] = true,
	[WEAPONTYPE_TWO_HANDED_HAMMER] = true,
	[WEAPONTYPE_TWO_HANDED_SWORD] = true,
	[WEAPONTYPE_DAGGER] = true,
}

local WOODWORKING_WEAPONS = {
	[WEAPONTYPE_BOW] = true,
	[WEAPONTYPE_FIRE_STAFF] = true,
	[WEAPONTYPE_FROST_STAFF] = true,
	[WEAPONTYPE_LIGHTNING_STAFF] = true,
	[WEAPONTYPE_HEALING_STAFF] = true,
	[WEAPONTYPE_SHIELD] = true,
}

local ARMOR_LINE_BY_EQUIP_TYPE = {
	[EQUIP_TYPE_CHEST] = 1,
	[EQUIP_TYPE_FEET] = 2,
	[EQUIP_TYPE_HAND] = 3,
	[EQUIP_TYPE_HEAD] = 4,
	[EQUIP_TYPE_LEGS] = 5,
	[EQUIP_TYPE_SHOULDERS] = 6,
	[EQUIP_TYPE_WAIST] = 7,
}

local WEAPON_LINE_BY_TYPE = {
	[WEAPONTYPE_AXE] = 1,
	[WEAPONTYPE_HAMMER] = 2,
	[WEAPONTYPE_SWORD] = 3,
	[WEAPONTYPE_TWO_HANDED_AXE] = 4,
	[WEAPONTYPE_TWO_HANDED_HAMMER] = 5,
	[WEAPONTYPE_TWO_HANDED_SWORD] = 6,
	[WEAPONTYPE_DAGGER] = 7,
	[WEAPONTYPE_BOW] = 1,
	[WEAPONTYPE_FIRE_STAFF] = 2,
	[WEAPONTYPE_FROST_STAFF] = 3,
	[WEAPONTYPE_LIGHTNING_STAFF] = 4,
	[WEAPONTYPE_HEALING_STAFF] = 5,
	[WEAPONTYPE_SHIELD] = 6,
}

local COLOR_SAFE = { 0.35, 1, 0.35, 1 }
local COLOR_UNSAFE = { 1, 0.35, 0.35, 1 }
local COLOR_OVERFLOW = { 1, 0.95, 0.25, 1 }
local COLOR_RESEARCHING = { 1, 0.85, 0.3, 1 }
local COLOR_NORMAL = { 1, 1, 1, 1 }

local function IsExcludedTrait(traitType)
	return traitType == ITEM_TRAIT_TYPE_WEAPON_INTRICATE
		or traitType == ITEM_TRAIT_TYPE_WEAPON_ORNATE
		or traitType == ITEM_TRAIT_TYPE_ARMOR_INTRICATE
		or traitType == ITEM_TRAIT_TYPE_ARMOR_ORNATE
		or traitType == ITEM_TRAIT_TYPE_JEWELRY_INTRICATE
		or traitType == ITEM_TRAIT_TYPE_JEWELRY_ORNATE
end

ResearchSafeDeconstruction = {
	vars = nil,
	lckReady = false,
	hookedLists = {},
	hookedInventories = {},
	hookedScenes = {},
	smithingModeHooked = false,
	stationHookWarningShown = false,
	statusCache = {},
	researchItemsByKey = nil,
	researchItemAllocations = nil,
	characterSettingsControl = nil,
	nextCharacterRowId = 0,
}

local addon = ResearchSafeDeconstruction

local function AddTooltipLine(text, color)
	local r, g, b = color[1], color[2], color[3]
	InformationTooltip:AddLine(text, "ZoFontGame", r, g, b, LEFT, MODIFY_TEXT_TYPE_NONE, TEXT_ALIGN_CENTER, true)
end

local function FormatRemaining(seconds)
	if type(seconds) ~= "number" or seconds <= 0 then
		return ""
	end

	if type(FormatTimeSeconds) == "function" and TIME_FORMAT_STYLE_SHOW_LARGEST_TWO_UNITS then
		return FormatTimeSeconds(seconds, TIME_FORMAT_STYLE_SHOW_LARGEST_TWO_UNITS)
	end

	if seconds >= 86400 then
		return string.format("%.1fd", seconds / 86400)
	elseif seconds >= 3600 then
		return string.format("%.1fh", seconds / 3600)
	else
		return string.format("%.1fm", seconds / 60)
	end
end

function addon:GetServerKey()
	local servers = LCK.GetServerList()
	return servers[1] or "current"
end

function addon:GetExcludedCharacters()
	self.vars.excludedCharacters = self.vars.excludedCharacters or {}

	local server = self:GetServerKey()
	self.vars.excludedCharacters[server] = self.vars.excludedCharacters[server] or {}
	return self.vars.excludedCharacters[server]
end

function addon:GetTrackedCharacters()
	if not self.lckReady then
		return {}
	end

	return LCK.GetCharacterList()
end

function addon:GetCrafters()
	local excluded = self:GetExcludedCharacters()
	local crafters = {}

	for _, character in ipairs(self:GetTrackedCharacters()) do
		if not excluded[character.id] then
			table.insert(crafters, character)
		end
	end

	return crafters
end

function addon:GetResearchKey(craftingSkillType, researchLineIndex, traitIndex)
	return string.format("%d:%d:%d", craftingSkillType, researchLineIndex, traitIndex)
end

function addon:GetSlotKey(bagId, slotIndex)
	return tostring(bagId) .. ":" .. tostring(slotIndex)
end

function addon:InvalidateCaches()
	self.statusCache = {}
	self.researchItemsByKey = nil
	self.researchItemAllocations = nil
end

function addon:IsListVisible(list)
	return type(list.IsHidden) ~= "function" or not list:IsHidden()
end

function addon:GetAvailableResearchItems()
	if self.researchItemsByKey then
		return self.researchItemsByKey
	end

	local itemsByKey = {}
	local seenSlots = {}

	for _, list in pairs(self.hookedLists) do
		local dataList = ZO_ScrollList_GetDataList(list)
		for _, entry in ipairs(dataList or {}) do
			local data = entry
			if type(entry.data) == "table" and entry.data.bagId ~= nil and entry.data.slotIndex ~= nil then
				data = entry.data
			end

			local bagId, slotIndex = data.bagId, data.slotIndex
			if bagId ~= nil and slotIndex ~= nil then
				local slotKey = self:GetSlotKey(bagId, slotIndex)
				if not seenSlots[slotKey] then
					seenSlots[slotKey] = true

					local itemLink = GetItemLink(bagId, slotIndex, LINK_STYLE_BRACKETS)
					if itemLink and itemLink ~= "" then
						local craftingSkillType, researchLineIndex, traitIndex = self:GetResearchIndices(itemLink)
						if craftingSkillType and researchLineIndex and traitIndex then
							local stackCount
							if type(GetSlotStackSize) == "function" then
								stackCount = GetSlotStackSize(bagId, slotIndex)
							end
							if type(stackCount) ~= "number" or stackCount <= 0 then
								stackCount = tonumber(data.stackCount) or 1
							end

							local researchKey = self:GetResearchKey(craftingSkillType, researchLineIndex, traitIndex)
							local items = itemsByKey[researchKey]
							if not items then
								items = {}
								itemsByKey[researchKey] = items
							end

							table.insert(items, {
								bagId = bagId,
								slotIndex = slotIndex,
								slotKey = slotKey,
								stackCount = stackCount,
								quality = type(GetItemDisplayQuality) == "function"
									and (GetItemDisplayQuality(bagId, slotIndex) or 0)
									or 0,
							})
						end
					end
				end
			end
		end
	end

	self.researchItemsByKey = itemsByKey
	return itemsByKey
end

function addon:GetResearchItemAllocation(researchKey, requiredCopies)
	self.researchItemAllocations = self.researchItemAllocations or {}
	local cachedAllocation = self.researchItemAllocations[researchKey]
	if cachedAllocation and cachedAllocation.requiredCopies == requiredCopies then
		return cachedAllocation
	end

	local items = self:GetAvailableResearchItems()[researchKey] or {}
	table.sort(items, function(left, right)
		if left.quality ~= right.quality then
			return left.quality < right.quality
		end
		return left.slotKey < right.slotKey
	end)

	local availableCopies = 0
	for _, item in ipairs(items) do
		availableCopies = availableCopies + item.stackCount
	end

	local allocation = {
		requiredCopies = requiredCopies,
		availableCopies = availableCopies,
		overflowCopies = math.max(0, availableCopies - requiredCopies),
		bySlot = {},
	}
	local remainingRequired = requiredCopies

	for _, item in ipairs(items) do
		local reservedCopies = math.min(item.stackCount, remainingRequired)
		allocation.bySlot[item.slotKey] = {
			reservedCopies = reservedCopies,
			overflowCopies = item.stackCount - reservedCopies,
		}
		remainingRequired = remainingRequired - reservedCopies
	end

	self.researchItemAllocations[researchKey] = allocation
	return allocation
end

function addon:SetCharacterIncluded(characterId, included)
	local excluded = self:GetExcludedCharacters()
	if included then
		excluded[characterId] = nil
	else
		excluded[characterId] = true
	end

	self:RefreshLists()
	self:UpdateCharacterSettings(self.characterSettingsControl)
end

function addon:FindCharacter(query)
	local characters = self:GetTrackedCharacters()
	local numericQuery = tonumber(query)

	if numericQuery and characters[numericQuery] then
		return characters[numericQuery]
	end

	local lowerQuery = string.lower(query)
	local partialMatches = {}

	for _, character in ipairs(characters) do
		local name = string.lower(character.name or "")
		if name == lowerQuery then
			return character
		elseif string.find(name, lowerQuery, 1, true) then
			table.insert(partialMatches, character)
		end
	end

	if #partialMatches == 1 then
		return partialMatches[1]
	end

	return nil, partialMatches
end

function addon:Print(message)
	local formatted = string.format("|c66FF66[%s]|r %s", TITLE, message)
	if CHAT_ROUTER and CHAT_ROUTER.AddSystemMessage then
		CHAT_ROUTER:AddSystemMessage(formatted)
	else
		d(formatted)
	end
end

function addon:PrintHelp()
	self:Print("Green markers are research-safe; red markers mean at least one included crafter does not know the trait.")
	self:Print("Use /rsd list, /rsd toggle <number or name>, or /rsd all.")
	self:Print("Log in to every crafter at least once so LibCharacterKnowledge has current research data.")
end

function addon:PrintCharacters()
	local characters = self:GetTrackedCharacters()
	if #characters == 0 then
		self:Print("No tracked characters are available yet. Log in to each crafter and wait for the research scan.")
		return
	end

	local excluded = self:GetExcludedCharacters()
	self:Print("Tracked characters on the current megaserver:")

	for index, character in ipairs(characters) do
		local marker = excluded[character.id] and "-" or "+"
		local scanTime = LCK.GetLastScanTime(nil, character.id)
		local dataState = scanTime > 0 and "research data recorded" or "no research data"
		self:Print(string.format("%s %d. %s (%s)", marker, index, character.name, dataState))
	end

	self:Print("Included characters use '+'. Excluded characters use '-'.")
end

function addon:ToggleCharacter(query)
	if query == "" then
		self:Print("Usage: /rsd toggle <character number or name>")
		return
	end

	local character, partialMatches = self:FindCharacter(query)
	if not character then
		if #partialMatches > 1 then
			self:Print("More than one character matches. Use the number from /rsd list.")
		else
			self:Print("Character not found. Use /rsd list.")
		end
		return
	end

	local excluded = self:GetExcludedCharacters()
	local included = excluded[character.id] ~= nil
	self:SetCharacterIncluded(character.id, included)
	if included then
		self:Print(string.format("%s is now included as a crafter.", character.name))
	else
		self:Print(string.format("%s is now excluded from the safety check.", character.name))
	end
end

function addon:HandleSlashCommand(command)
	local action, query = string.match(command or "", "^%s*(%S*)%s*(.-)%s*$")
	action = string.lower(action or "")

	if action == "" or action == "help" then
		self:PrintHelp()
	elseif action == "list" or action == "chars" or action == "characters" then
		self:PrintCharacters()
	elseif action == "toggle" then
		self:ToggleCharacter(query)
	elseif action == "all" or action == "reset" then
		self:GetExcludedCharacters()
		self.vars.excludedCharacters[self:GetServerKey()] = {}
		self:Print("All tracked characters are included again.")
		self:RefreshLists()
		self:UpdateCharacterSettings(self.characterSettingsControl)
	else
		self:PrintHelp()
	end
end

function addon:RegisterSlashCommands()
	SLASH_COMMANDS["/rsd"] = function(command)
		self:HandleSlashCommand(command)
	end
end

function addon:UpdateCharacterSettings(control)
	if not control then
		return
	end

	local characters = self:GetTrackedCharacters()
	local excluded = self:GetExcludedCharacters()
	control.characterRows = control.characterRows or {}
	control.visibleCharacterRows = {}

	if not control.statusLabel then
		control.statusLabel = WINDOW_MANAGER:CreateControl(nil, control, CT_LABEL)
		control.statusLabel:SetFont("ZoFontGame")
		control.statusLabel:SetColor(ZO_DEFAULT_ENABLED_COLOR:UnpackRGBA())
		control.statusLabel:SetAnchor(TOPLEFT)
	end

	control.statusLabel:SetWidth(control:GetWidth())
	control.statusLabel:SetHeight(CHARACTER_STATUS_HEIGHT)
	control.statusLabel:SetText(
		#characters > 0
			and "Check a character to include it in the research safety checks."
			or "No characters are available yet. Log in to each character at least once so LibCharacterKnowledge can discover it."
	)

	local previousControl = control.statusLabel
	for _, character in ipairs(characters) do
		local characterId = character.id
		local row = control.characterRows[characterId]
		if not row then
			self.nextCharacterRowId = self.nextCharacterRowId + 1
			row = WINDOW_MANAGER:CreateControlFromVirtual(
				NAME .. "CharacterRow" .. tostring(self.nextCharacterRowId),
				control,
				"ZO_Options_Checkbox"
			)
			row.data = {}
			row:SetMouseEnabled(true)

			local checkBox = row:GetNamedChild("Checkbox")
			checkBox.data = row.data
			ZO_CheckButton_SetToggleFunction(checkBox, function(_, included)
				self:SetCharacterIncluded(characterId, included)
			end)
			control.characterRows[characterId] = row
		end

		row:ClearAnchors()
		row:SetAnchor(TOPLEFT, previousControl, BOTTOMLEFT, 0, 2)
		row:SetWidth(control:GetWidth())
		row:SetHeight(CHARACTER_ROW_HEIGHT)
		row:SetHidden(false)

		local nameControl = row:GetNamedChild("Name")
		nameControl:SetText(character.name)
		row.data.tooltipText = "Include " .. character.name .. " in the research safety checks."

		local included = not excluded[characterId]
		if included then
			ZO_CheckButton_SetChecked(row:GetNamedChild("Checkbox"))
		else
			ZO_CheckButton_SetUnchecked(row:GetNamedChild("Checkbox"))
		end
		local nameColor = included and ZO_DEFAULT_ENABLED_COLOR or ZO_DEFAULT_DISABLED_COLOR
		nameControl:SetColor(nameColor:UnpackRGBA())

		control.visibleCharacterRows[characterId] = true
		previousControl = row
	end

	for characterId, row in pairs(control.characterRows) do
		if not control.visibleCharacterRows[characterId] then
			row:ClearAnchors()
			row:SetHidden(true)
		end
	end

	control:SetHeight(CHARACTER_STATUS_HEIGHT + (#characters * CHARACTER_ROW_HEIGHT) + 2)
end

function addon:RegisterSettings()
	if not LibAddonMenu2 then
		return
	end

	local panelId = NAME .. "Options"
	LibAddonMenu2:RegisterAddonPanel(panelId, {
		type = "panel",
		name = TITLE,
		author = "FlexWares Gaming",
		version = "1.3.0",
		registerForRefresh = true,
	})

	LibAddonMenu2:RegisterOptionControls(panelId, {
		{
			type = "description",
			text = "Marks items in the smithing and universal deconstruction lists according to the research status of every included character on the current megaserver.",
		},
		{
			type = "checkbox",
			name = "Enable deconstruction markers",
			tooltip = "Show the research safety marker in deconstruction lists.",
			getFunc = function()
				return self.vars.enabled
			end,
			setFunc = function(value)
				self.vars.enabled = value
				self:RefreshLists()
			end,
			default = DEFAULTS.enabled,
		},
		{
			type = "checkbox",
			name = "Show unsafe warning markers",
			tooltip = "Show a red warning when any included crafter has not completed or started the item's trait research.",
			getFunc = function()
				return self.vars.showUnsafe
			end,
			setFunc = function(value)
				self.vars.showUnsafe = value
				self:RefreshLists()
			end,
			default = DEFAULTS.showUnsafe,
		},
		{
			type = "checkbox",
			name = "Mark overflow research items",
			tooltip = "Show a yellow marker when the list contains more research-compatible copies than the included characters still need.",
			getFunc = function()
				return self.vars.showOverflow
			end,
			setFunc = function(value)
				self.vars.showOverflow = value
				self:RefreshLists()
			end,
			default = DEFAULTS.showOverflow,
		},
		{
			type = "header",
			name = "Monitored characters",
		},
		{
			type = "custom",
			reference = NAME .. "Characters",
			minHeight = CHARACTER_STATUS_HEIGHT,
			maxHeight = 2000,
			createFunc = function(control)
				self.characterSettingsControl = control
				self:UpdateCharacterSettings(control)
			end,
			refreshFunc = function(control)
				self:UpdateCharacterSettings(control)
			end,
		},
		{
			type = "description",
			text = "Completing research refreshes the markers automatically, but does not remove a character from monitoring. Yellow overflow markers reserve one copy for each included character that still needs the trait. Use /rsd list to see included characters or /rsd toggle <number or name> to change them.",
		},
	})
end

function addon:GetResearchIndices(itemLink)
	local traitType = GetItemLinkTraitType(itemLink)
	if IsExcludedTrait(traitType) then
		return nil, nil, nil, "excluded"
	end

	if not traitType or traitType == ITEM_TRAIT_TYPE_NONE then
		return nil, nil, nil, "no-research"
	end

	if not LCK.GetTraitInfo(traitType) then
		return nil, nil, nil, "no-research"
	end

	local craftingSkillType, researchLineIndex, traitIndex = LCK.GetSmithingResearchFromItemLink(itemLink)
	if craftingSkillType and researchLineIndex and traitIndex then
		return craftingSkillType, researchLineIndex, traitIndex
	end

	local itemType = GetItemLinkItemType(itemLink)
	local armorType = GetItemLinkArmorType(itemLink)
	local weaponType = GetItemLinkWeaponType(itemLink)
	local equipType = GetItemLinkEquipType(itemLink)

	if itemType == ITEMTYPE_ARMOR then
		if equipType == EQUIP_TYPE_RING then
			craftingSkillType = CRAFTING_TYPE_JEWELRYCRAFTING
			researchLineIndex = 1
		elseif equipType == EQUIP_TYPE_NECK then
			craftingSkillType = CRAFTING_TYPE_JEWELRYCRAFTING
			researchLineIndex = 2
		else
			local line = ARMOR_LINE_BY_EQUIP_TYPE[equipType]
			if line then
				if armorType == ARMORTYPE_HEAVY then
					craftingSkillType = CRAFTING_TYPE_BLACKSMITHING
					researchLineIndex = line + 7
				elseif armorType == ARMORTYPE_LIGHT then
					craftingSkillType = CRAFTING_TYPE_CLOTHIER
					researchLineIndex = line
				elseif armorType == ARMORTYPE_MEDIUM then
					craftingSkillType = CRAFTING_TYPE_CLOTHIER
					researchLineIndex = line + 7
				end
			end
		end
	elseif itemType == ITEMTYPE_WEAPON then
		researchLineIndex = WEAPON_LINE_BY_TYPE[weaponType]
		if BLACKSMITH_WEAPONS[weaponType] then
			craftingSkillType = CRAFTING_TYPE_BLACKSMITHING
		elseif WOODWORKING_WEAPONS[weaponType] then
			craftingSkillType = CRAFTING_TYPE_WOODWORKING
		end
	end

	if not craftingSkillType and type(GetItemLinkCraftingSkillType) == "function" then
		craftingSkillType = select(1, GetItemLinkCraftingSkillType(itemLink))
	end

	if not craftingSkillType or not researchLineIndex then
		return nil, nil, nil, "unsupported"
	end

	local numTraits = select(3, GetSmithingResearchLineInfo(craftingSkillType, researchLineIndex))
	if not numTraits then
		return nil, nil, nil, "unsupported"
	end
	for candidateTraitIndex = 1, numTraits do
		local candidateTraitType = GetSmithingResearchLineTraitInfo(craftingSkillType, researchLineIndex, candidateTraitIndex)
		if candidateTraitType == traitType then
			return craftingSkillType, researchLineIndex, candidateTraitIndex
		end
	end

	return nil, nil, nil, "unsupported"
end

function addon:GetResearchStatus(itemLink, craftingSkillType, researchLineIndex, traitIndex)
	local status = {
		safe = true,
		traitName = GetString("SI_ITEMTRAITTYPE", GetItemLinkTraitType(itemLink)),
		craftingName = GetString("SI_TRADESKILLTYPE", craftingSkillType),
		researchLineName = GetSmithingResearchLineInfo(craftingSkillType, researchLineIndex),
		details = {},
		researchNeeded = 0,
		researchDataComplete = true,
	}

	local crafters = self:GetCrafters()
	if #crafters == 0 then
		status.safe = false
		status.reason = "No included crafters are available."
		return status
	end

	for _, character in ipairs(crafters) do
		local knowledge, remaining = LCK.GetSmithingResearchStatusForCharacter(
			craftingSkillType,
			researchLineIndex,
			traitIndex,
			self:GetServerKey(),
			character.id
		)

		local detail = {
			name = character.name,
			state = "not known",
		}

		if knowledge == LCK.KNOWLEDGE_KNOWN or (type(remaining) == "number" and remaining <= 0) then
			detail.state = "known"
		elseif type(remaining) == "number" and remaining > 0 then
			detail.state = "researching"
			detail.remaining = remaining
		elseif knowledge == LCK.KNOWLEDGE_NODATA then
			detail.state = "no data"
			status.researchDataComplete = false
		elseif knowledge == LCK.KNOWLEDGE_UNKNOWN then
			status.researchNeeded = status.researchNeeded + 1
		else
			status.researchDataComplete = false
			status.safe = false
		end

		if detail.state == "no data" or detail.state == "not known" then
			status.safe = false
		end

		table.insert(status.details, detail)
	end

	if status.safe then
		status.reason = "Every included crafter knows or is researching this trait."
	else
		status.reason = "At least one included crafter does not know or has no recorded data for this trait."
	end

	return status
end

function addon:GetItemStatus(bagId, slotIndex)
	local itemLink = GetItemLink(bagId, slotIndex, LINK_STYLE_BRACKETS)
	if not itemLink or itemLink == "" then
		return nil
	end

	local statusCacheKey = self:GetSlotKey(bagId, slotIndex)
	if self.statusCache[statusCacheKey] then
		return self.statusCache[statusCacheKey]
	end

	local craftingSkillType, researchLineIndex, traitIndex, reason = self:GetResearchIndices(itemLink)
	local status

	if reason == "excluded" then
		return nil
	elseif reason == "no-research" then
		status = {
			safe = true,
			noResearch = true,
			reason = "This item has no researchable trait.",
		}
	elseif reason == "unsupported" then
		status = {
			safe = false,
			traitName = GetString("SI_ITEMTRAITTYPE", GetItemLinkTraitType(itemLink)),
			reason = "The item's research line could not be identified.",
			details = {},
		}
	else
		status = self:GetResearchStatus(itemLink, craftingSkillType, researchLineIndex, traitIndex)

		if self.vars.showOverflow and status.researchDataComplete and status.researchNeeded > 0 then
			local researchKey = self:GetResearchKey(craftingSkillType, researchLineIndex, traitIndex)
			local allocation = self:GetResearchItemAllocation(researchKey, status.researchNeeded)
			if allocation.overflowCopies > 0 then
				status.availableCopies = allocation.availableCopies
				status.overflowCopies = allocation.overflowCopies

				local itemAllocation = allocation.bySlot[self:GetSlotKey(bagId, slotIndex)]
				if itemAllocation and itemAllocation.reservedCopies == 0 then
					status.overflow = true
					status.reason = string.format(
						"%d excess copies are available after reserving one for each included crafter that needs this trait.",
						allocation.overflowCopies
					)
				elseif itemAllocation then
					status.overflowReserved = true
				end
			end
		end
	end

	self.statusCache[statusCacheKey] = status
	return status
end

function addon:ShowStatusTooltip(control)
	local status = control.status
	if not status then
		return
	end

	local color = status.overflow and COLOR_OVERFLOW or (status.safe and COLOR_SAFE or COLOR_UNSAFE)
	InitializeTooltip(InformationTooltip, control, RIGHT, -10)
	local title = status.overflow and "Research overflow: safe to deconstruct"
		or (status.safe and "Research-safe to deconstruct" or "Do not deconstruct for research")
	AddTooltipLine(title, color)

	if status.noResearch then
		AddTooltipLine(status.reason, COLOR_NORMAL)
		return
	end

	if status.traitName then
		AddTooltipLine(string.format("%s: %s", status.craftingName or "Crafting", status.traitName), COLOR_NORMAL)
	end
	if status.researchLineName then
		AddTooltipLine(string.format("Research line: %s", status.researchLineName), COLOR_NORMAL)
	end
	if status.availableCopies and status.overflowCopies and status.overflowCopies > 0 then
		AddTooltipLine(
			string.format(
				"%d copies available; %d excess%s",
				status.availableCopies,
				status.overflowCopies,
				status.overflowReserved and " (this item is reserved for research)" or ""
			),
			status.overflow and COLOR_OVERFLOW or COLOR_NORMAL
		)
	end

	for _, detail in ipairs(status.details or {}) do
		local detailColor = COLOR_NORMAL
		if detail.state == "researching" then
			detailColor = COLOR_RESEARCHING
		elseif detail.state == "no data" or detail.state == "not known" then
			detailColor = COLOR_UNSAFE
		end

		local suffix = ""
		local remaining = FormatRemaining(detail.remaining)
		if remaining ~= "" then
			suffix = " (" .. remaining .. ")"
		end

		AddTooltipLine(string.format("%s: %s%s", detail.name, detail.state, suffix), detailColor)
	end

	AddTooltipLine(status.reason, color)
end

function addon:CreateIndicator(control)
	local indicator = control:GetNamedChild("ResearchSafeIndicator")
	if not indicator then
		indicator = CreateControl("$(parent)ResearchSafeIndicator", control, CT_TEXTURE)
		indicator:SetDimensions(INDICATOR_SIZE, INDICATOR_SIZE)
		indicator:SetDrawTier(DT_MEDIUM)
		indicator:SetMouseEnabled(true)
		indicator:SetHandler("OnMouseEnter", function(indicatorControl)
			addon:ShowStatusTooltip(indicatorControl)
		end)
		indicator:SetHandler("OnMouseExit", function()
			ClearTooltip(InformationTooltip)
		end)
	end

	local horizontalAnchor = control:GetNamedChild("TraitInfo") or control
	local _, controlCenterY = control:GetCenter()
	local _, anchorCenterY = horizontalAnchor:GetCenter()
	indicator:ClearAnchors()
	indicator:SetAnchor(RIGHT, horizontalAnchor, RIGHT, INDICATOR_OFFSET_X, controlCenterY - anchorCenterY)
	return indicator
end

function addon:SetupIndicator(control, dataEntryData)
	if not control then
		return
	end

	local indicator = self:CreateIndicator(control)
	indicator.status = nil
	indicator:SetHidden(true)

	if not self.vars.enabled or not self.lckReady or not dataEntryData then
		return
	end

	local status = self:GetItemStatus(dataEntryData.bagId, dataEntryData.slotIndex)
	if not status then
		return
	end

	local showOverflow = status.overflow and self.vars.showOverflow
	local showUnsafe = not status.safe and not status.overflow and self.vars.showUnsafe
	if not status.safe and not showOverflow and not showUnsafe then
		return
	end

	indicator.status = status
	indicator:SetTexture(INDICATOR_TEXTURE)
	indicator:SetTextureCoords(0, 1, 0, 1)
	if status.overflow then
		indicator:SetColor(unpack(COLOR_OVERFLOW))
	elseif status.safe then
		indicator:SetColor(unpack(COLOR_SAFE))
	else
		indicator:SetColor(unpack(COLOR_UNSAFE))
	end
	indicator:SetHidden(false)
end

function addon:InitializeInventoryHooks()
	local inventories = {}
	local smithing = _G["SMITHING"]
	if smithing and smithing.deconstructionPanel then
		table.insert(inventories, smithing.deconstructionPanel.inventory)
	end

	local universalDeconstruction = _G["UNIVERSAL_DECONSTRUCTION"]
	if universalDeconstruction and universalDeconstruction.deconstructionPanel then
		table.insert(inventories, universalDeconstruction.deconstructionPanel.inventory)
	end

	for _, inventory in ipairs(inventories) do
		if inventory and not self.hookedInventories[inventory] then
			local hasRefreshHook = false
			for _, methodName in ipairs({ "PerformFullRefresh", "Refresh", "ChangeFilter" }) do
				if type(inventory[methodName]) == "function" then
					ZO_PreHook(inventory, methodName, function()
						addon:InvalidateCaches()
					end)
					hasRefreshHook = true
				end
			end

			if hasRefreshHook then
				self.hookedInventories[inventory] = true
			end
		end
	end
end

function addon:InitializeSmithingModeHook()
	if self.smithingModeHooked then
		return
	end

	local smithing = _G["SMITHING"]
	if not smithing or type(smithing.SetMode) ~= "function" then
		return
	end

	ZO_PreHook(smithing, "SetMode", function(_, mode)
		if mode == SMITHING_MODE_DECONSTRUCTION then
			addon:PrepareForDeconstruction(true)
		end
	end)
	self.smithingModeHooked = true
end

function addon:InitializeSceneHooks()
	if not SCENE_MANAGER or type(SCENE_MANAGER.GetScene) ~= "function" then
		return
	end

	for _, sceneName in ipairs({ "smithing", "universalDeconstructionSceneKeyboard" }) do
		if not self.hookedScenes[sceneName] then
			local scene = SCENE_MANAGER:GetScene(sceneName)
			if scene and type(scene.RegisterCallback) == "function" then
				local refreshNow = sceneName == "universalDeconstructionSceneKeyboard"
				scene:RegisterCallback("StateChange", function(_, newState)
					if newState == SCENE_SHOWING then
						addon:PrepareForDeconstruction(refreshNow)
					end
				end)
				self.hookedScenes[sceneName] = scene
			end
		end
	end
end

function addon:InitializeStationHooks()
	self:InitializeInventoryHooks()
	self:InitializeSmithingModeHook()
	self:InitializeSceneHooks()

	for _, listName in ipairs(DECONSTRUCTION_LIST_NAMES) do
		if not self.hookedLists[listName] then
			local list = _G[listName]
			if list then
				local dataType = ZO_ScrollList_GetDataTypeTable(list, 1)
				if dataType and dataType.setupCallback then
					SecurePostHook(dataType, "setupCallback", function(control, dataEntryData)
						addon:SetupIndicator(control, dataEntryData)
					end)
					self.hookedLists[listName] = list
				end
			end
		end
	end

	if next(self.hookedLists) == nil and not self.stationHookWarningShown then
		d("[" .. TITLE .. "] Could not find a deconstruction inventory list to hook.")
		self.stationHookWarningShown = true
	elseif next(self.hookedLists) ~= nil then
		self.stationHookWarningShown = false
	end
end

function addon:PrepareForDeconstruction(refreshNow)
	self:InitializeStationHooks()
	if refreshNow then
		self:RefreshLists(true)
	else
		self:InvalidateCaches()
	end
end

function addon:RefreshLists(force)
	self:InvalidateCaches()

	for _, list in pairs(self.hookedLists) do
		if type(ZO_ScrollList_RefreshVisible) == "function"
			and (force or self:IsListVisible(list)) then
			ZO_ScrollList_RefreshVisible(list)
		end
	end
end

function addon:OnLckInitialized()
	if self.lckReady then
		return
	end

	self.lckReady = true
	self:InitializeStationHooks()
	self:RefreshLists()
	self:UpdateCharacterSettings(self.characterSettingsControl)
end

function addon:OnLckUpdate()
	if self.lckReady then
		self:RefreshLists()
		self:UpdateCharacterSettings(self.characterSettingsControl)
	end
end

function addon:OnRefreshEvent()
	self:InitializeStationHooks()
	if self.lckReady then
		self:RefreshLists()
	end
end

function addon:TryInitializeFromPlayerActivation()
	self:InitializeStationHooks()

	if self.lckReady then
		return
	end

	if #LCK.GetCharacterList() > 0 then
		self:OnLckInitialized()
	end
end

function addon:RegisterRefreshEvents()
	EVENT_MANAGER:RegisterForEvent(NAME .. "CraftingStation", EVENT_CRAFTING_STATION_INTERACT, function()
		addon:PrepareForDeconstruction(false)
	end)

	for _, eventCode in ipairs({
		EVENT_INVENTORY_SINGLE_SLOT_UPDATE,
		EVENT_INVENTORY_FULL_UPDATE,
		EVENT_SMITHING_TRAIT_RESEARCH_CANCELED,
		EVENT_SMITHING_TRAIT_RESEARCH_COMPLETED,
		EVENT_SMITHING_TRAIT_RESEARCH_STARTED,
		EVENT_SMITHING_TRAIT_RESEARCH_TIMES_UPDATED,
	}) do
		EVENT_MANAGER:RegisterForEvent(NAME .. tostring(eventCode), eventCode, function()
			addon:OnRefreshEvent()
		end)
	end
end

local function OnAddOnLoaded(_, addonName)
	if addonName ~= NAME then
		return
	end

	EVENT_MANAGER:UnregisterForEvent(NAME, EVENT_ADD_ON_LOADED)
	addon.vars = ZO_SavedVars:NewAccountWide("ResearchSafeDeconstructionSavedVariables", 1, nil, DEFAULTS)
	addon:RegisterSlashCommands()
	addon:RegisterSettings()
	addon:RegisterRefreshEvents()
	addon:InitializeStationHooks()

	LCK.RegisterForCallback(NAME, LCK.EVENT_INITIALIZED, function()
		addon:OnLckInitialized()
	end)
	LCK.RegisterForCallback(NAME, LCK.EVENT_UPDATE_REFRESH, function()
		addon:OnLckUpdate()
	end)

	EVENT_MANAGER:RegisterForEvent(NAME, EVENT_PLAYER_ACTIVATED, function()
		addon:TryInitializeFromPlayerActivation()
		if addon.lckReady then
			EVENT_MANAGER:UnregisterForEvent(NAME, EVENT_PLAYER_ACTIVATED)
		end
	end)
end

EVENT_MANAGER:RegisterForEvent(NAME, EVENT_ADD_ON_LOADED, OnAddOnLoaded)
