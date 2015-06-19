-----------------------------------------------------------------------------------------------
-- Client Lua Script for InterfaceMenuList
-- Copyright (c) NCsoft. All rights reserved
-----------------------------------------------------------------------------------------------

require "Window"
require "GameLib"
require "Apollo"

local InterfaceMenuList = {}
local knVersion = 2

function InterfaceMenuList:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function InterfaceMenuList:Init()
    Apollo.RegisterAddon(self)
end

function InterfaceMenuList:OnSave(eType)
	if eType ~= GameLib.CodeEnumAddonSaveLevel.Account then
		return
	end
	
	local tSavedData = {
		nVersion = knVersion,
		tPinnedAddons = self.tPinnedAddons,
		bLiveEventSeen = self.bLiveEventSeen,
	}
	
	return tSavedData
end

function InterfaceMenuList:OnRestore(eType, tSavedData)
	if tSavedData.nVersion ~= knVersion then
		return
	end
	
	if eType ~= GameLib.CodeEnumAddonSaveLevel.Account then
		return
	end
	
	if tSavedData.tPinnedAddons then
		self.tPinnedAddons = tSavedData.tPinnedAddons
	end
	
	self.bLiveEventSeen = tSavedData.bLiveEventSeen
	
	self.tSavedData = tSavedData
end


function InterfaceMenuList:OnLoad()
	self.xmlDoc = XmlDoc.CreateFromFile("InterfaceMenuList.xml")
	self.xmlDoc:RegisterCallback("OnDocumentReady", self) 
end

function InterfaceMenuList:OnDocumentReady()
	if self.xmlDoc == nil then
		return
	end
	
	Apollo.RegisterEventHandler("InterfaceMenuList_NewAddOn", 			"OnNewAddonListed", self)
	Apollo.RegisterEventHandler("InterfaceMenuList_AlertAddOn", 		"OnDrawAlert", self)
	Apollo.RegisterEventHandler("CharacterCreated", 					"OnCharacterCreated", self)
	Apollo.RegisterEventHandler("Tutorial_RequestUIAnchor", 			"OnTutorial_RequestUIAnchor", self)
	Apollo.RegisterTimerHandler("TimeUpdateTimer", 						"OnUpdateTimer", self)
	Apollo.RegisterTimerHandler("QueueRedrawTimer", 					"OnQueuedRedraw", self)
	Apollo.RegisterEventHandler("ApplicationWindowSizeChanged", 		"ButtonListRedraw", self)
	Apollo.RegisterEventHandler("OptionsUpdated_HUDPreferences", 		"OnUpdateTimer", self)
	Apollo.RegisterEventHandler("LiveEvent_WindowClosed", 				"OnLiveEventClosed", self)

    self.wndMain = Apollo.LoadForm(self.xmlDoc , "InterfaceMenuListForm", "FixedHudStratumHigh", self)
	self.wndList = Apollo.LoadForm(self.xmlDoc , "FullListFrame", nil, self)

	self.wndMain:FindChild("OpenFullListBtn"):AttachWindow(self.wndList)
	self.wndMain:FindChild("OpenFullListBtn"):Enable(false)

	Apollo.CreateTimer("QueueRedrawTimer", 0.3, false)

	if not self.tPinnedAddons then
		self.tPinnedAddons = {
			Apollo.GetString("InterfaceMenu_AccountInventory"),
			Apollo.GetString("InterfaceMenu_Character"),
			Apollo.GetString("InterfaceMenu_AbilityBuilder"),
			Apollo.GetString("InterfaceMenu_QuestLog"),
			Apollo.GetString("InterfaceMenu_GroupFinder"),
			Apollo.GetString("InterfaceMenu_Social"),
			Apollo.GetString("InterfaceMenu_Mail"),
			Apollo.GetString("InterfaceMenu_Lore"),
		}
	end
	
	self.tMenuData = {
		[Apollo.GetString("InterfaceMenu_SystemMenu")] = { "", "Escape", "Icon_Windows32_UI_CRB_InterfaceMenu_EscMenu" }, --
	}
	
	self.tMenuTooltips = {}
	self.tMenuAlerts = {}

	self:ButtonListRedraw()

	if GameLib.GetPlayerUnit() then
		self:OnCharacterCreated()
	end
end

function InterfaceMenuList:OnListShow()
	self.wndList:ToFront()
end

function InterfaceMenuList:OnCharacterCreated()	
	Apollo.CreateTimer("TimeUpdateTimer", 1.0, true)
end

function InterfaceMenuList:OnUpdateTimer()
	if not self.bHasLoaded then
		Event_FireGenericEvent("InterfaceMenuListHasLoaded")
		self.wndMain:FindChild("OpenFullListBtn"):Enable(true)
		self.bHasLoaded = true
	end
	
	if self.bHasLoaded and not self.bLiveEventLoaded and GameLib.IsCharacterLoaded() then
		-- PublicEventStart will catch it if this loads too early
		local bLiveEventActive = false
		for idx, peEvent in pairs(PublicEvent.GetActiveEvents() or {}) do
			if peEvent:GetEventType() == PublicEvent.PublicEventType_LiveEvent then
				bLiveEventActive = true
				break
			end
		end
		
		--reset bLiveEventSeen if it was previously active and now isn't.
		if not bLiveEventActive then
			self.bLiveEventSeen = false
		end
		
		if bLiveEventActive then
			local wndLiveEvent = self.wndMain:FindChild("LiveEvent")
			wndLiveEvent:Show(true)
			
			local btnLiveEvent = wndLiveEvent:FindChild("EventMoreInfoBtn")
			btnLiveEvent:SetTooltip(string.format(
				"%s%s%s", 
				Apollo.GetString("Event_WorldEventTitle"), 
				Apollo.GetString("Chat_ColonBreak"), 
				Apollo.GetString("Event_ShadesEveTitle")
			))
			
			local wndButtons = self.wndMain:FindChild("ButtonList")
			local nLeft, nTop, nRight, nBottom = wndButtons:GetAnchorOffsets()
			
			wndButtons:SetAnchorOffsets(nLeft + wndLiveEvent:GetWidth(), nTop, nRight, nBottom)
			
			if not self.bLiveEventSeen then
				Event_FireGenericEvent("LiveEvent_ToggleWindow")
				self.bLiveEventSeen = true
				wndLiveEvent:FindChild("EventAlert"):Show(true)
			end
			
			self.bLiveEventLoaded = true
		end
	end

	--Toggle Visibility based on ui preference
	local nVisibility = Apollo.GetConsoleVariable("hud.TimeDisplay")
	
	local tLocalTime = GameLib.GetLocalTime()
	local tServerTime = GameLib.GetServerTime()
	local b24Hour = true
	local nLocalHour = tLocalTime.nHour > 12 and tLocalTime.nHour - 12 or tLocalTime.nHour == 0 and 12 or tLocalTime.nHour
	local nServerHour = tServerTime.nHour > 12 and tServerTime.nHour - 12 or tServerTime.nHour == 0 and 12 or tServerTime.nHour
		
	self.wndMain:FindChild("Time"):SetText(string.format("%02d:%02d", tostring(tLocalTime.nHour), tostring(tLocalTime.nMinute)))
	
	if nVisibility == 2 then --Local 12hr am/pm
		self.wndMain:FindChild("Time"):SetText(string.format("%02d:%02d", tostring(nLocalHour), tostring(tLocalTime.nMinute)))
		
		b24Hour = false
	elseif nVisibility == 3 then --Server 24hr
		self.wndMain:FindChild("Time"):SetText(string.format("%02d:%02d", tostring(tServerTime.nHour), tostring(tServerTime.nMinute)))
	elseif nVisibility == 4 then --Server 12hr am/pm
		self.wndMain:FindChild("Time"):SetText(string.format("%02d:%02d", tostring(nServerHour), tostring(tServerTime.nMinute)))
		
		b24Hour = false
	end
	
	nLocalHour = b24Hour and tLocalTime.nHour or nLocalHour
	nServerHour = b24Hour and tServerTime.nHour or nServerHour
	
	self.wndMain:FindChild("Time"):SetTooltip(
		string.format("%s%02d:%02d\n%s%02d:%02d", 
			Apollo.GetString("OptionsHUD_Local"), tostring(nLocalHour), tostring(tLocalTime.nMinute),
			Apollo.GetString("OptionsHUD_Server"), tostring(nServerHour), tostring(tServerTime.nMinute)
		)
	)
end

function InterfaceMenuList:OnNewAddonListed(strKey, tParams)
	strKey = string.gsub(strKey, ":", "|") -- ":'s don't work for window names, sorry!"

	self.tMenuData[strKey] = tParams
	
	self:FullListRedraw()
	self:ButtonListRedraw()
end

function InterfaceMenuList:IsPinned(strText)
	for idx, strWindowText in pairs(self.tPinnedAddons) do
		if (strText == strWindowText) then
			return true
		end
	end
	
	return false
end

function InterfaceMenuList:FullListRedraw()
	local strUnbound = Apollo.GetString("Keybinding_Unbound")
	local wndParent = self.wndList:FindChild("FullListScroll")
	
	local strQuery = Apollo.StringToLower(tostring(self.wndList:FindChild("SearchEditBox"):GetText()) or "")
	if strQuery == nil or strQuery == "" or not strQuery:match("[%w%s]+") then
		strQuery = ""
	end

	for strWindowText, tData in pairs(self.tMenuData) do
		local bSearchResultMatch = string.find(Apollo.StringToLower(strWindowText), strQuery) ~= nil
		
		if strQuery == "" or bSearchResultMatch then
			local wndMenuItem = self:LoadByName("MenuListItem", wndParent, strWindowText)
			local wndMenuButton = self:LoadByName("InterfaceMenuButton", wndMenuItem:FindChild("Icon"), strWindowText)
			local strTooltip = strWindowText
			
			if string.len(tData[2]) > 0 then
				local strKeyBindLetter = GameLib.GetKeyBinding(tData[2])
				strKeyBindLetter = strKeyBindLetter == strUnbound and "" or string.format(" (%s)", strKeyBindLetter)  -- LOCALIZE
				
				strTooltip = strKeyBindLetter ~= "" and strTooltip .. strKeyBindLetter or strTooltip
			end
			
			if tData[3] ~= "" then
				wndMenuButton:FindChild("Icon"):SetSprite(tData[3])
			else 
				wndMenuButton:FindChild("Icon"):SetText(string.sub(strTooltip, 1, 1))
			end
			
			wndMenuButton:FindChild("ShortcutBtn"):SetData(strWindowText)
			wndMenuButton:FindChild("Icon"):SetTooltip(strTooltip)
			self.tMenuTooltips[strWindowText] = strTooltip
			
			wndMenuItem:FindChild("MenuListItemBtn"):SetText(strWindowText)
			wndMenuItem:FindChild("MenuListItemBtn"):SetData(tData[1])
			
			wndMenuItem:FindChild("PinBtn"):SetCheck(self:IsPinned(strWindowText))
			wndMenuItem:FindChild("PinBtn"):SetData(strWindowText)
			
			if string.len(tData[2]) > 0 then
				local strKeyBindLetter = GameLib.GetKeyBinding(tData[2])
				wndMenuItem:FindChild("MenuListItemBtn"):FindChild("MenuListItemKeybind"):SetText(strKeyBindLetter == strUnbound and "" or string.format("(%s)", strKeyBindLetter))  -- LOCALIZE
			end
		elseif not bSearchResultMatch and wndParent:FindChild(strWindowText) then
			wndParent:FindChild(strWindowText):Destroy()
		end
	end
	
	wndParent:ArrangeChildrenVert(0, function (a,b) return a:GetName() < b:GetName() end)
end

function InterfaceMenuList:ButtonListRedraw()
	Apollo.StopTimer("QueueRedrawTimer")
	Apollo.StartTimer("QueueRedrawTimer")
end

function InterfaceMenuList:OnQueuedRedraw()
	local strUnbound = Apollo.GetString("Keybinding_Unbound")
	local wndParent = self.wndMain:FindChild("ButtonList")
	wndParent:DestroyChildren()
	local nParentWidth = wndParent:GetWidth()
	
	local nLastButtonWidth = 0
	local nTotalWidth = 0

	for idx, strWindowText in pairs(self.tPinnedAddons) do
		tData = self.tMenuData[strWindowText]
		
		--Magic number below is allowing the 1 pixel gutter on the right
		if tData and nTotalWidth + nLastButtonWidth <= nParentWidth + 1 then
			local wndMenuItem = self:LoadByName("InterfaceMenuButton", wndParent, strWindowText)
			local strTooltip = strWindowText
			nLastButtonWidth = wndMenuItem:GetWidth()
			nTotalWidth = nTotalWidth + nLastButtonWidth

			if string.len(tData[2]) > 0 then
				local strKeyBindLetter = GameLib.GetKeyBinding(tData[2])
				strKeyBindLetter = strKeyBindLetter == strUnbound and "" or string.format(" (%s)", strKeyBindLetter)  -- LOCALIZE
				strTooltip = strKeyBindLetter ~= "" and strTooltip .. strKeyBindLetter or strTooltip
			end
			
			if tData[3] ~= "" then
				wndMenuItem:FindChild("Icon"):SetSprite(tData[3])
			else 
				wndMenuItem:FindChild("Icon"):SetText(string.sub(strTooltip, 1, 1))
			end
			
			wndMenuItem:FindChild("ShortcutBtn"):SetData(strWindowText)
			wndMenuItem:FindChild("Icon"):SetTooltip(strTooltip)
		end
		
		if self.tMenuAlerts[strWindowText] then
			self:OnDrawAlert(strWindowText, self.tMenuAlerts[strWindowText])
		end
	end
	
	wndParent:ArrangeChildrenHorz(0)
end

-----------------------------------------------------------------------------------------------
-- Search
-----------------------------------------------------------------------------------------------

function InterfaceMenuList:OnSearchEditBoxChanged(wndHandler, wndControl)
	self.wndList:FindChild("SearchClearBtn"):Show(string.len(wndHandler:GetText() or "") > 0)
	self:FullListRedraw()
end

function InterfaceMenuList:OnSearchClearBtn(wndHandler, wndControl)
	self.wndList:FindChild("SearchFlash"):SetSprite("CRB_WindowAnimationSprites:sprWinAnim_BirthSmallTemp")
	self.wndList:FindChild("SearchFlash"):SetFocus()
	self.wndList:FindChild("SearchClearBtn"):Show(false)
	self.wndList:FindChild("SearchEditBox"):SetText("")
	self:FullListRedraw()
end

function InterfaceMenuList:OnSearchCommitBtn(wndHandler, wndControl)
	self.wndList:FindChild("SearchFlash"):SetSprite("CRB_WindowAnimationSprites:sprWinAnim_BirthSmallTemp")
	self.wndList:FindChild("SearchFlash"):SetFocus()
	self:FullListRedraw()
end

-----------------------------------------------------------------------------------------------
-- Alerts
-----------------------------------------------------------------------------------------------

function InterfaceMenuList:OnDrawAlert(strWindowName, tParams)
	self.tMenuAlerts[strWindowName] = tParams
	for idx, wndTarget in pairs(self.wndMain:FindChild("ButtonList"):GetChildren()) do
		if wndTarget and tParams then
			local wndButton = wndTarget:FindChild("ShortcutBtn")
			if wndButton then 
				local wndIcon = wndButton:FindChild("Icon")
				
				if wndButton:GetData() == strWindowName then
					if tParams[1] then
						local wndIndicator = self:LoadByName("AlertIndicator", wndButton:FindChild("Alert"), "AlertIndicator")
						
					elseif wndButton:FindChild("AlertIndicator") ~= nil then
						wndButton:FindChild("AlertIndicator"):Destroy()
					end
					
					if tParams[2] then
						wndIcon:SetTooltip(string.format("%s\n\n%s", self.tMenuTooltips[strWindowName], tParams[2]))
					end
					
					if tParams[3] and tParams[3] > 0 then
						local strColor = tParams[1] and "UI_WindowTextOrange" or "UI_TextHoloTitle"
						
						wndButton:FindChild("Number"):Show(true)
						wndButton:FindChild("Number"):SetText(tParams[3])
						wndButton:FindChild("Number"):SetTextColor(ApolloColor.new(strColor))
					else
						wndButton:FindChild("Number"):Show(false)
						wndButton:FindChild("Number"):SetText("")
						wndButton:FindChild("Number"):SetTextColor(ApolloColor.new("UI_TextHoloTitle"))
					end
				end
			end
		end
	end
	
	local wndParent = self.wndList:FindChild("FullListScroll")
	for idx, wndTarget in pairs(wndParent:GetChildren()) do
		local wndButton = wndTarget:FindChild("ShortcutBtn")
		local wndIcon = wndButton:FindChild("Icon")
		
		if wndButton:GetData() == strWindowName then
			if tParams[1] then
				local wndIndicator = self:LoadByName("AlertIndicator", wndButton:FindChild("Alert"), "AlertIndicator")
			elseif wndButton:FindChild("AlertIndicator") ~= nil then
				wndButton:FindChild("AlertIndicator"):Destroy()
			end
			
			if tParams[2] then
				wndIcon:SetTooltip(string.format("%s\n\n%s", self.tMenuTooltips[strWindowName], tParams[2]))
			end
			
			if tParams[3] and tParams[3] > 0 then
				local strColor = tParams[1] and "UI_WindowTextOrange" or "UI_TextHoloTitle"
				
				wndButton:FindChild("Number"):Show(true)
				wndButton:FindChild("Number"):SetText(tParams[3])
				wndButton:FindChild("Number"):SetTextColor(ApolloColor.new(strColor))
			else
				wndButton:FindChild("Number"):Show(false)
			end
		end
	end
end

function InterfaceMenuList:OnLiveEventClosed()
	self.wndMain:FindChild("EventAlert"):Show(false)
end

-----------------------------------------------------------------------------------------------
-- Helpers and Errata
-----------------------------------------------------------------------------------------------

function InterfaceMenuList:OnMenuListItemClick(wndHandler, wndControl)
	if wndHandler ~= wndControl then return end
	
	if string.len(wndControl:GetData()) > 0 then
		Event_FireGenericEvent(wndControl:GetData())
	else
		InvokeOptionsScreen()
	end
	self.wndList:Show(false)
end

function InterfaceMenuList:OnPinBtnChecked(wndHandler, wndControl)
	if wndHandler ~= wndControl then return end
	
	local wndParent = wndControl:GetParent():GetParent()
	
	self.tPinnedAddons = {}
	
	for idx, wndMenuItem in pairs(wndParent:GetChildren()) do
		if wndMenuItem:FindChild("PinBtn"):IsChecked() then
		
			table.insert(self.tPinnedAddons, wndMenuItem:FindChild("PinBtn"):GetData())
		end
	end
	
	self:ButtonListRedraw()
end

function InterfaceMenuList:OnListBtnClick(wndHandler, wndControl) -- These are the five always on icons on the top
	if wndHandler ~= wndControl then return end
	local strMappingResult = wndHandler:GetData() and self.tMenuData[wndHandler:GetData()][1] or ""
	
	if string.len(strMappingResult) > 0 then
		Event_FireGenericEvent(strMappingResult)
	else
		InvokeOptionsScreen()
	end
end

function InterfaceMenuList:OnListBtnMouseEnter(wndHandler, wndControl)
	wndHandler:SetBGColor("ffffffff")
	if wndHandler ~= wndControl or self.wndList:IsVisible() then
		return
	end
end

function InterfaceMenuList:OnListBtnMouseExit(wndHandler, wndControl) -- Also self.wndMain MouseExit and ButtonList MouseExit
	wndHandler:SetBGColor("9dffffff")
end

function InterfaceMenuList:OnOpenFullListCheck(wndHandler, wndControl)
	self.wndList:FindChild("SearchEditBox"):SetFocus()
	self:FullListRedraw()
end

function InterfaceMenuList:OnEventMoreInfoBtn(wndHandler, wndControl)
	Event_FireGenericEvent("LiveEvent_ToggleWindow")
end

function InterfaceMenuList:LoadByName(strForm, wndParent, strCustomName)
	local wndNew = wndParent:FindChild(strCustomName)
	if not wndNew then
		wndNew = Apollo.LoadForm(self.xmlDoc , strForm, wndParent, self)
		wndNew:SetName(strCustomName)
	end
	return wndNew
end

function InterfaceMenuList:OnTutorial_RequestUIAnchor(eAnchor, idTutorial, strPopupText)
	local arTutorialAnchorMapping =
	{
		--[GameLib.CodeEnumTutorialAnchor.Abilities] 			= "LASBtn",
		--[GameLib.CodeEnumTutorialAnchor.Character] 		= "CharacterBtn",
		--[GameLib.CodeEnumTutorialAnchor.Mail] 				= "MailBtn",
		--[GameLib.CodeEnumTutorialAnchor.GalacticArchive] = "LoreBtn",
		--[GameLib.CodeEnumTutorialAnchor.Social] 			= "SocialBtn",
		--[GameLib.CodeEnumTutorialAnchor.GroupFinder] 		= "GroupFinderBtn",
	}

	local strWindowName = "ButtonList" or false
	if not strWindowName then
		return
	end

	local tRect = {}
	tRect.l, tRect.t, tRect.r, tRect.b = self.wndMain:FindChild(strWindowName):GetRect()
	tRect.r = tRect.r - 26
	
	if arTutorialAnchorMapping[eAnchor] then
		Event_FireGenericEvent("Tutorial_RequestUIAnchorResponse", eAnchor, idTutorial, strPopupText, tRect)
	end
end

local InterfaceMenuListInst = InterfaceMenuList:new()
InterfaceMenuListInst:Init()