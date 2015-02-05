-----------------------------------------------------------------------------------------------
-- Client Lua Script for CharacterCustomization
-- Copyright (c) NCsoft. All rights reserved
-----------------------------------------------------------------------------------------------
 
require "Window"
require "GameLib"
 
-----------------------------------------------------------------------------------------------
-- CharacterCustomization Module Definition
-----------------------------------------------------------------------------------------------
local CharacterCustomization = {} 
 
-----------------------------------------------------------------------------------------------
-- Constants
-----------------------------------------------------------------------------------------------
-- e.g. local kiExampleVariableMax = 999

local knTokenItemId = 50763

local ktOverlayTypes =
{
	Purchase = 1,
	Cancel = 2,
	Code = 3,
}

local ktRaceStrings =
{
	[GameLib.CodeEnumRace.Human]	= Apollo.GetString("RaceHuman"),
	[GameLib.CodeEnumRace.Granok]	= Apollo.GetString("CRB_DemoCC_Granok"),
	[GameLib.CodeEnumRace.Aurin]	= Apollo.GetString("CRB_DemoCC_Aurin"),
	[GameLib.CodeEnumRace.Draken]	= Apollo.GetString("RaceDraken"),
	[GameLib.CodeEnumRace.Mechari]	= Apollo.GetString("RaceMechari"),
	[GameLib.CodeEnumRace.Mordesh]	= Apollo.GetString("CRB_Mordesh"),
	[GameLib.CodeEnumRace.Chua]		= Apollo.GetString("RaceChua"),
}

local ktGenderStrings =
{
	[Unit.CodeEnumGender.Male] = Apollo.GetString("CRB_Male"),
	[Unit.CodeEnumGender.Female] = Apollo.GetString("CRB_Female"),
}

local ktFactionStrings =
{
	[Unit.CodeEnumFaction.DominionPlayer] 	= Apollo.GetString("CRB_Dominion"),
	[Unit.CodeEnumFaction.ExilesPlayer] 	= Apollo.GetString("CRB_Exile"),
}

local ktFaceSliderIds =
{
	[1] = true,
	[21] = true,
	[22] = true,
}

local knBodyTypeId = 25
 
-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------
function CharacterCustomization:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self 

    -- initialize variables here

    return o
end

function CharacterCustomization:Init()
	local tDependencies = {}
    Apollo.RegisterAddon(self, bHasConfigureFunction, strConfigureButtonText, tDependencies)
end
 

-----------------------------------------------------------------------------------------------
-- CharacterCustomization OnLoad
-----------------------------------------------------------------------------------------------
function CharacterCustomization:OnLoad()
    -- load our form file
	self.xmlDoc = XmlDoc.CreateFromFile("CharacterCustomization.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
end

-----------------------------------------------------------------------------------------------
-- CharacterCustomization OnDocLoaded
-----------------------------------------------------------------------------------------------
function CharacterCustomization:OnDocLoaded()
	if self.xmlDoc == nil or not self.xmlDoc:IsLoaded() then
		return
	end
	
	Apollo.RegisterEventHandler("UpdateInventory", "CheckForTokens", self)
	Apollo.RegisterEventHandler("PlayerCurrencyChanged", "CalculateTotalCost", self)
	Apollo.RegisterEventHandler("GenericEvent_InitializeCustomization", "OnInit", self)
	Apollo.RegisterEventHandler("GenericEvent_CloseCustomization", "OnCancel", self)
	Apollo.RegisterEventHandler("Customize_ShowTab", "OnTabShow", self)
	
	-- by sequential index
	self.arCharacterBones = {}
	self.arCurrentCustomizationOptions = {}
	
	-- indexed by sliderIds
	self.tPreviousBones = {}
	self.tPreviousOptions = {}
	self.tOptionWindows = {}
	self.tBoneWindows = {}
	self.tChangedBones = {}

	
	--just for customization options, not bones
	self.tCustomizationCosts = {}
	
	self.wndBonePreviewItem = nil
	self.idSelectedCategory = nil
	
	self.bUseToken = false
	self.bHasToken = false
end

--Init
function CharacterCustomization:OnInit(wndParent)
	
	if not GameLib.IsCharacterLoaded() or (self.wndMain and self.wndMain:IsShown()) then
		return
	end
	
	if not self.wndMain or not self.wndMain:IsValid() then	
		self.wndMain = Apollo.LoadForm(self.xmlDoc, "CharacterCustomizationForm", wndParent, self)		
		self.wndPreview = self.wndMain:FindChild("RightContent:Costume")
		self.wndHideHelm = self.wndMain:FindChild("RightContent:HideHelmBtn")
		
		self.wndMain:FindChild("Footer:BuyBtn"):Enable(false)		
		self.wndMain:FindChild("RightContent:SetSheatheBtn"):SetCheck(true)
	end
	
	local unitPlayer = GameLib.GetPlayerUnit()	
	self.wndMain:FindChild("ToggleFlyout"):AttachWindow(self.wndMain:FindChild("PreviewChangesFlyout"))
	self.wndPreview:SetCostume(unitPlayer)
	self:GetCharacterInfo()
	self.wndMain:FindChild("LeftContainer:CategoryScrollContainer"):DestroyChildren()
	
	--Loads headers, followed by options within the headers
	self:LoadCustomizationHeaders()
	self:CheckForTokens()
	self:ResizePreview()
	self.wndMain:Invoke()
end

function CharacterCustomization:OnTabShow()
	local nCostumeIdx = GameLib.GetCostumeIndex()
	local unitPlayer = GameLib.GetPlayerUnit()	
	self.itemDisplayedHelm = nil
	
	if nCostumeIdx > 0 then
		self.bEnableHelmSwap = GameLib.IsCostumeSlotVisible(GameLib.GetCostumeIndex(), GameLib.CodeEnumItemSlots.Head)
		self.itemDisplayedHelm = GameLib.GetCostumeItem(nCostumeIdx, GameLib.CodeEnumItemSlots.Head)
	end
	
	if not self.itemDisplayedHelm or nCostumeIdx == 0 then
		for idx, itemEquipment in pairs(unitPlayer:GetEquippedItems()) do
			if itemEquipment:GetSlot() == GameLib.CodeEnumEquippedItems.Head then
				self.itemDisplayedHelm = itemEquipment
			end
		end
		
		self.bEnableHelmSwap = self.itemDisplayedHelm ~= nil
	end
	self:HelperToggleHelm()
	self:ResetTabs()
end

function CharacterCustomization:GetCharacterInfo()
	self.arCharacterBones = self.wndPreview:GetBones()
	self.arCurrentCustomizationOptions = self.wndPreview:GetLooks()
end

function CharacterCustomization:LoadCustomizationHeaders()
	local wndCustomizationContainer = self.wndMain:FindChild("LeftContainer:CategoryScrollContainer")
	
	Apollo.LoadForm(self.xmlDoc, "CodeCategoryHeader", wndCustomizationContainer, self)
	
	-- We want to make sure we're loading the Face and Face Customization first
	for idx, tCategory in pairs(self.arCurrentCustomizationOptions) do
		if ktFaceSliderIds[tCategory.sliderId] then
			self:LoadHeader(tCategory.sliderId, tCategory)
		
			local wndBoneHeader = Apollo.LoadForm(self.xmlDoc, "BoneCategoryHeader", wndCustomizationContainer, self)
			wndBoneHeader:FindChild("CategorySelectBtn"):SetText(Apollo.GetString("CharacterCustomize_CustomizeFace"))
			self.tBoneWindows = 
			{
				wndHeader = wndBoneHeader,
				tSliders = {},
			}

			for idx, tBone in pairs(self.arCharacterBones) do
				self:LoadBoneCustomizationOption(wndBoneHeader, "BoneOptionItem", tBone)
				self.tPreviousBones[tBone.sliderId] = tBone.value
			end
		end
	end
	
	for idx, tCategory in pairs(self.arCurrentCustomizationOptions) do
		if not ktFaceSliderIds[tCategory.sliderId] then
			self:LoadHeader(tCategory.sliderId, tCategory)
		end
	end

	wndCustomizationContainer:ArrangeChildrenVert()
end

function CharacterCustomization:LoadHeader(idSlider, tCategory)
	local wndHeader = Apollo.LoadForm(self.xmlDoc, "CategoryHeader", self.wndMain:FindChild("LeftContainer:CategoryScrollContainer"), self)
	
	if not self.nCategoryHeight then
		self.nCategoryHeight = wndHeader:GetHeight()
	end
	
	wndHeader:SetData(tCategory)
	wndHeader:FindChild("CategorySelectBtn"):SetData(idSlider)
	wndHeader:FindChild("CategorySelectBtn"):SetText(tCategory.name)
	
	self.tPreviousOptions[idSlider] = tCategory.valueIdx
	
	-- we want face options on top.

	self.tOptionWindows[idSlider] =
	{
		wndHeader = wndHeader,
		tOptions = {},
	}
	self:LoadCustomizationOptions(wndHeader, tCategory)
end

-----------------------------------------------------------------------------------------------
-- Customization Options
-----------------------------------------------------------------------------------------------

function CharacterCustomization:LoadCustomizationOptions(wndCategoryHeader, tCategory)
	local wndContainer = wndCategoryHeader:FindChild("GroupContents")
	local unitPlayer = GameLib.GetPlayerUnit()
	
	wndContainer:DestroyChildren()
	
	for idx = 1, tCategory.count do
		local wndOption = Apollo.LoadForm(self.xmlDoc, "OptionItem", wndContainer, self)
		local wndOptionPreview = wndOption:FindChild("CostumeWindow")
		wndOptionPreview:SetCostume(unitPlayer)
		
		-- Use the correct values for the open category.
		for nLookIdx, tOptions in pairs(self.arCurrentCustomizationOptions) do
			nValue = nil
			if tOptions.sliderId ~= self.idSelectedCategory then
				nValue = tOptions.values[tOptions.valueIdx]
			else
				nValue = tCategory.values[idx]
			end
			
			wndOptionPreview:SetLook(tOptions.sliderId, nValue)
		end
		
		if tCategory.sliderId ~= knBodyTypeId then
			wndOptionPreview:SetCamera("Portrait")
		else
			wndOptionPreview:SetCamera("Paperdoll")
		end
		
		wndOptionPreview:SetAnimated(false)
		
		wndOption:SetData(tCategory.values[idx])
		wndOption:FindChild("OptionBtn"):SetData(idx)
		
		if self.tPreviousOptions[tCategory.sliderId] == idx then
			local tPixieOverlay =
			{
				strSprite = "bk3:UI_BK3_Options_Telegraph_Outline",
				loc = {fPoints = {0, 0, 1, 1}, nOffsets = {-6, -6, 5, 6}}	
			}
			wndOptionPreview:AddPixie(tPixieOverlay)
		end
		
		self.tOptionWindows[tCategory.sliderId].tOptions[idx] = wndOption
	end
	
	wndContainer:ArrangeChildrenTiles()
	wndContainer:Show(false)
end

function CharacterCustomization:OnCategoryCheck(wndHandler, wndControl)
	local wndParent = wndControl:GetParent()
	local tCategory = wndParent:GetData()
	
	self.idSelectedCategory = wndControl:GetData()
	
	if tCategory.sliderId ~= knBodyTypeId then
		self.wndPreview:SetCamera("Portrait")
	else
		self.wndPreview:SetCamera("Paperdoll")
	end

	self:LoadCustomizationOptions(wndParent, tCategory)
	
	wndParent:FindChild("GroupContents"):Invoke()
	self:ResizeTree()
	
	local wndSelectedOption = self.tOptionWindows[tCategory.sliderId].tOptions[tCategory.valueIdx]
	wndSelectedOption:FindChild("OptionBtn"):SetCheck(true)
	
	self:HelperToggleHelm()
	self.wndMain:FindChild("LeftContainer:CategoryScrollContainer"):ArrangeChildrenVert()
end

function CharacterCustomization:OnCategoryUncheck(wndHandler, wndControl)
	self.wndMain:SetGlobalRadioSel("CharacterCustomization_SelectedOption", -1)
	self.idSelectedCategory = nil
	
	wndControl:GetParent():FindChild("GroupContents"):Show(false)
	self:ResizeTree()
	
	self.wndMain:FindChild("LeftContainer:CategoryScrollContainer"):ArrangeChildrenVert()
end

function CharacterCustomization:OnOptionCheck(wndHandler, wndControl)
	local idSelectedOption = wndHandler:GetData()
	
	if not self.idSelectedCategory or not idSelectedOption then
		return
	end

	local wndHeader = self.tOptionWindows[self.idSelectedCategory].wndHeader
	local tOptions = wndHeader:GetData()
	tOptions.valueIdx = idSelectedOption
	
	local wndCostPreview = self.tCustomizationCosts[tOptions.sliderId] and self.tCustomizationCosts[tOptions.sliderId].wndPreview or nil
	if self.tPreviousOptions[tOptions.sliderId] ~= idSelectedOption then
		local monCost = self.wndPreview:GetCostForCustomizationSelection(tOptions.sliderId, tOptions.values[idSelectedOption])
		
		if not wndCostPreview then
			wndCostPreview = Apollo.LoadForm(self.xmlDoc, "PreviewLineItem", self.wndMain:FindChild("PreviewChangesFlyout:CostPreviewContainer"), self)
			wndCostPreview:FindChild("ListItemName"):SetText(tOptions.name)
			wndCostPreview:FindChild("UndoBtn"):SetData(tOptions.sliderId)
		end
		wndCostPreview:FindChild("CashWindow"):SetAmount(monCost, true)
		wndHeader:FindChild("CategorySelectBtn:ElementChangedIcon"):Show(true)
		self.tCustomizationCosts[tOptions.sliderId] = {strName = tOptions.name, monCost = monCost, wndPreview = wndCostPreview}
		
	elseif self.tCustomizationCosts[tOptions.sliderId] then
		if self.tCustomizationCosts[tOptions.sliderId].wndPreview then
			self.tCustomizationCosts[tOptions.sliderId].wndPreview:Destroy()
			self.tCustomizationCosts[tOptions.sliderId].wndPreview = nil
			wndCostPreview = nil
		end
		
		wndHeader:FindChild("CategorySelectBtn:ElementChangedIcon"):Show(false)
		self.tCustomizationCosts[tOptions.sliderId] = nil
	end
	
	if wndCostPreview then
		wndCostPreview:GetParent():ArrangeChildrenVert()
	end
	
	self.wndPreview:SetLook(tOptions.sliderId, tOptions.values[tOptions.valueIdx])
	self:ResizePreview()
	self:CalculateTotalCost()
	self.arCurrentCustomizationOptions = self.wndPreview:GetLooks()
end

function CharacterCustomization:OnOptionUndo(wndHandler, wndControl)
	local idSlider = wndHandler:GetData()
	local wndHeader = nil
	if idSlider ~= -1 then
		local nOptionIdx = nil
		for idx, tOption in pairs(self.arCurrentCustomizationOptions) do
			if tOption.sliderId == idSlider then
				nOptionIdx = idx
			end
		end
		
		if idSlider == self.idSelectedCategory then
			self.wndMain:SetGlobalRadioSel("CharacterCustomization_SelectedOption", -1)
		end
	
		self.arCurrentCustomizationOptions[nOptionIdx].valueIdx = self.tPreviousOptions[idSlider]
		self.wndPreview:SetLook(idSlider, self.arCurrentCustomizationOptions[nOptionIdx].values[self.arCurrentCustomizationOptions[nOptionIdx].valueIdx])
		
		self.tOptionWindows[idSlider].tOptions[self.tPreviousOptions[idSlider]]:FindChild("OptionBtn"):SetCheck(true)
		self.tCustomizationCosts[idSlider] = nil
		
		wndHeader = self.tOptionWindows[idSlider].wndHeader
		
		wndHandler:GetParent():Destroy()
		self.wndMain:FindChild("PreviewChangesFlyout:CostPreviewContainer"):ArrangeChildrenVert()
	else		
		for idx, tInfo in pairs(self.arCharacterBones) do
			local wndUndoBtn = self.tBoneWindows.tSliders[tInfo.sliderId]:FindChild("UndoBtn")
			self:OnUndoBone(wndUndoBtn, wndUndoBtn)
		end
		wndHeader = self.tBoneWindows.wndHeader
	end
	
	wndHeader:FindChild("CategorySelectBtn:ElementChangedIcon"):Show(false)
	self:CalculateTotalCost()
	self:ResizePreview()
	
	self.arCurrentCustomizationOptions = self.wndPreview:GetLooks()
end

-----------------------------------------------------------------------------------------------
-- Bones!
-----------------------------------------------------------------------------------------------

function CharacterCustomization:LoadBoneCustomizationOption(wndCategoryHeader, strOptionWindow, tBone)
	local wndContainer = wndCategoryHeader:FindChild("GroupContents")
	
	local wndOption = Apollo.LoadForm(self.xmlDoc, strOptionWindow, wndContainer, self)
	wndOption:SetData(tBone)
	wndOption:FindChild("SliderContainer:SliderTitle"):SetText(tBone.name)
	
	local wndSlider = wndOption:FindChild("SliderContainer:SliderBar")
	wndSlider:SetData(tBone.sliderId)
	wndSlider:SetMinMax(-1, 1)
	
	wndOption:FindChild("UndoBtn"):Enable(false)	
	
	self.tBoneWindows.tSliders[tBone.sliderId] = wndOption
	
	wndContainer:ArrangeChildrenVert()
	wndContainer:Show(false)
end

function CharacterCustomization:OnBoneCategoryCheck(wndHandler, wndControl)
	local wndContainer = wndControl:GetParent():FindChild("GroupContents")
	
	for idx, tBone in pairs(self.arCharacterBones) do
		local wndBone = self.tBoneWindows.tSliders[tBone.sliderId]
		wndBone:FindChild("SliderContainer:SliderBar"):SetValue(tBone.value)
		wndBone:FindChild("SliderContainer:SliderValue"):SetText(string.format("%.2f", tBone.value))
	end
	
	
	self.wndPreview:SetCamera("Portrait")
	wndContainer:Invoke()
	self:ResizeTree()
	
	self.wndMain:FindChild("LeftContainer:CategoryScrollContainer"):ArrangeChildrenVert()
end

function CharacterCustomization:OnBoneChanged(wndHandler, wndControl)
	local nValue = wndHandler:GetValue()
	local idBone = wndHandler:GetData()
	local strCurrentValue = string.format("%.2f", nValue)
	
	wndHandler:GetParent():FindChild("SliderValue"):SetText(strCurrentValue)
	self.wndPreview:SetBone(idBone, nValue)
	wndHandler:GetParent():GetParent():FindChild("UndoBtn"):Enable(true)
	
	self.arCharacterBones = self.wndPreview:GetBones()
	
	self.tChangedBones[idBone] = self.tPreviousBones[idBone] ~= nValue
	
	self:SetBoneCostPreview()
	self:CalculateTotalCost()
end

function CharacterCustomization:SetBoneCostPreview()
	local bBonesChanged = self:CheckForBoneChanges()
	
	if bBonesChanged and not self.wndBonePreviewItem then
		self.wndBonePreviewItem = Apollo.LoadForm(self.xmlDoc, "PreviewLineItem", self.wndMain:FindChild("PreviewChangesFlyout:CostPreviewContainer"), self)
		self.wndBonePreviewItem:FindChild("ListItemName"):SetText(Apollo.GetString("CharacterCustomize_Bones"))
		self.wndBonePreviewItem:FindChild("CashWindow"):SetAmount(self.wndPreview:GetCostForBoneChanges(), true)
		
		-- Using -1 for the UndoBtn's data since bones do use the same set of sliderIds as other categories
		self.wndBonePreviewItem:FindChild("UndoBtn"):SetData(-1)		
	elseif not bBonesChanged and self.wndBonePreviewItem then
		self.wndBonePreviewItem:Destroy()
		self.wndBonePreviewItem = nil
	end
	self.wndMain:FindChild("PreviewChangesFlyout:CostPreviewContainer"):ArrangeChildrenVert()
	self:ResizePreview()
end

function CharacterCustomization:OnUndoBone(wndHandler, wndControl)
	local wndContainer = wndHandler:GetParent():FindChild("SliderContainer")
	local tBone = wndHandler:GetParent():GetData()
	
	local wndContainer = wndHandler:GetParent():FindChild("SliderContainer")
	
	wndContainer:FindChild("SliderBar"):SetValue(self.tPreviousBones[tBone.sliderId])
	wndContainer:FindChild("SliderValue"):SetText(string.format("%.2f", self.tPreviousBones[tBone.sliderId]))
	wndContainer:GetParent():FindChild("UndoBtn"):Enable(false)

	self.wndPreview:SetBone(tBone.sliderId, self.tPreviousBones[tBone.sliderId])
	self.arCharacterBones = self.wndPreview:GetBones()
	self.tChangedBones[tBone.sliderId] = false
	
	self:SetBoneCostPreview()	
	self:CalculateTotalCost()
end

-----------------------------------------------------------------------------------------------
-- CostPreview Window
-----------------------------------------------------------------------------------------------

function CharacterCustomization:OnCostPreview(wndHandler, wndControl)
	local wndCostPreview = self.wndMain:FindChild("PreviewChangesFlyout")
	
	if wndCostPreview:IsShown() then
		wndCostPreview:Show(false)
	else
		wndCostPreview:Show(true)
	end
end
	
function CharacterCustomization:ResizePreview()
	local wndCostPreview = self.wndMain:FindChild("PreviewChangesFlyout")
	local wndContainer = wndCostPreview:FindChild("CostPreviewContainer")
	local arPreviewWindows = wndContainer:GetChildren()
	local bHasChanges = arPreviewWindows and #arPreviewWindows > 0
	
	local nContainerHeight = 0
	
	wndCostPreview:FindChild("NoChangesLabel"):Show(not bHasChanges)
	
	if bHasChanges then
		nContainerHeight = arPreviewWindows[1]:GetHeight() * #arPreviewWindows
	else
		--Create enough room to show the "no changes" label
		nContainerHeight = 34
	end		

	if not self.nHeightOfPreview then -- get the height just once
		local tOriginalOffsets = wndCostPreview:GetOriginalLocation():ToTable().nOffsets
		self.nHeightOfPreview = (tOriginalOffsets[4] - tOriginalOffsets[2])
	end
			
	local nLeft, nTop, nRight, nBottom = wndCostPreview:GetAnchorOffsets()
	wndCostPreview:SetAnchorOffsets(nLeft, nBottom - self.nHeightOfPreview - nContainerHeight, nRight, nBottom)
end

-----------------------------------------------------------------------------------------------
-- Buy Confirmation
-----------------------------------------------------------------------------------------------

function CharacterCustomization:OnBuyBtn(wndHandler, wndControl)
	local wndPurchaseConfirm = self.wndMain:FindChild("ConfirmationOverlay:PurchaseConfirmation")
	local wndPriceContainer = wndPurchaseConfirm:FindChild("LineItemContainer")
	wndPriceContainer:DestroyChildren()
	
	local monTotalCost = Money.new()
	
	for idSlider, tCost in pairs(self.tCustomizationCosts) do
		local wndCostItem = Apollo.LoadForm(self.xmlDoc, "ConfirmationLineItem", wndPriceContainer, self)
		wndCostItem:FindChild("ListItemName"):SetText(tCost.strName)
		wndCostItem:FindChild("CashWindow"):Show(not self.bUseToken)
		wndCostItem:FindChild("CashWindow"):SetAmount(tCost.monCost, true)
		
		monTotalCost:SetAmount(monTotalCost:GetAmount() + tCost.monCost:GetAmount())
	end
	
	if self.wndBonePreviewItem then
		local wndCostItem = Apollo.LoadForm(self.xmlDoc, "ConfirmationLineItem", wndPriceContainer, self)
		local monCost = self.wndPreview:GetCostForBoneChanges()
		wndCostItem:FindChild("ListItemName"):SetText(Apollo.GetString("CharacterCustomize_Bones"))
		wndCostItem:FindChild("CashWindow"):Show(not self.bUseToken)
		wndCostItem:FindChild("CashWindow"):SetAmount(monCost, true)
		
		monTotalCost:SetAmount(monTotalCost:GetAmount() + monCost:GetAmount())
	end

	wndPriceContainer:ArrangeChildrenVert()

	local arPreviewEntries = wndPriceContainer:GetChildren()
	
	if arPreviewEntries and #arPreviewEntries > 0 then -- make sure the table exists
		local nPreviewLineItemHeight = arPreviewEntries[1]:GetHeight() --get height of first entry
		local nTotalLineItemHeight = #arPreviewEntries * nPreviewLineItemHeight -- height entries * single entry
		local tOffsets = wndPurchaseConfirm:GetOriginalLocation():ToTable().nOffsets
		
		wndPurchaseConfirm:SetAnchorOffsets(tOffsets[1], tOffsets[2] - (nTotalLineItemHeight / 2), tOffsets[3], tOffsets[4] + (nTotalLineItemHeight / 2))
	end
	
	
	local wndSubtotal = wndPurchaseConfirm:FindChild("TotalCost")
	wndSubtotal:Show(not self.bUseToken)
	wndSubtotal:SetAmount(monTotalCost, true)
	
	
	local wndTokenIcon = wndPurchaseConfirm:FindChild("TokenIcon")
	local wndTokenLabel = wndPurchaseConfirm:FindChild("TokenLabel")
	local luaSubclass = wndTokenIcon:GetWindowSubclass()
	local itemToken = Item.GetDataFromId(knTokenItemId)
	luaSubclass:SetItem(itemToken)
	
	-- things only cost 1 token at the moment
	wndTokenLabel:SetText(String_GetWeaselString(Apollo.GetString("ChallengeReward_Multiplier"), 1))
	
	wndTokenIcon:Show(self.bUseToken)
	wndTokenLabel:Show(self.bUseToken)
	
	self:ToggleOverlay(ktOverlayTypes.Purchase, true)
end

function CharacterCustomization:OnPurchaseConfirm(wndHandler, wndControl)
	self.wndPreview:CommitCustomizationChanges(self.bUseToken)
	local wndFooterContainer = self.wndMain:FindChild("Footer")
	wndFooterContainer:FindChild("CostPreview:TotalCost"):SetAmount(0, true)
	wndFooterContainer:FindChild("BuyBtn"):Enable(false)
	
	self.wndMain:FindChild("PreviewChangesFlyout:CostPreviewContainer"):DestroyChildren()
	self.wndBonePreviewItem = nil
	self.tCustomizationCosts = {}
	self.tChangedBones = {}
	self:GetCharacterInfo()
	
	for idx, tBone in pairs(self.arCharacterBones) do
		self.tPreviousBones[tBone.sliderId] = tBone.value
	end
	
	for idx, tOption in pairs(self.arCurrentCustomizationOptions) do
		self.tPreviousOptions[tOption.sliderId] = tOption.valueIdx
	end
	
	if self.idSelectedCategory and self.tOptionWindows[self.idSelectedCategory] then
		local wndHeaderBtn = self.tOptionWindows[self.idSelectedCategory].wndHeader:FindChild("CategorySelectBtn")
		wndHeaderBtn:SetCheck(false)
		self:OnCategoryUncheck(wndHeaderBtn, wndHeaderBtn)
	end
	
	for idx, tWindowInfo in pairs(self.tOptionWindows) do
		tWindowInfo.wndHeader:FindChild("CategorySelectBtn:ElementChangedIcon"):Show(false)
	end
	
	self.wndMain:FindChild("RightContent:PurchaseConfirmFlash"):SetSprite("CRB_WindowAnimationSprites:sprWinAnim_BirthSmallTemp")
	self:ToggleOverlay(ktOverlayTypes.Purchase, false)
	self:ResizePreview()
	self:HelperToggleHelm()
end

function CharacterCustomization:OnPurchaseCancel(wndHandler, wndControl)
	self:ToggleOverlay(ktOverlayTypes.Purchase, false)
end

function CharacterCustomization:OnUseTokenToggle(wndHandler, wndControl)
	self.bUseToken = wndHandler:IsChecked()
	self:CalculateTotalCost()
end

-----------------------------------------------------------------------------------------------
-- Close Confirmation
-----------------------------------------------------------------------------------------------
function CharacterCustomization:OnClose()
	self:UndoAll()
	
	self.wndMain:FindChild("PreviewChangesFlyout:CostPreviewContainer"):DestroyChildren()
	self.wndMain:FindChild("ConfirmationOverlay"):Show(false)
	self.tCustomizationCosts = {}
	self.tBoneChanges = {}
	self:CalculateTotalCost()
	
	if self.idSelectedCategory and self.tOptionWindows[self.idSelectedCategory] then
		local wndHeaderBtn = self.tOptionWindows[self.idSelectedCategory].wndHeader:FindChild("CategorySelectBtn")
		wndHeaderBtn:SetCheck(false)
		self:OnCategoryUncheck(wndHeaderBtn, wndHeaderBtn)
	end

	if self.wndMain:IsShown() then
		self.wndMain:GetParent():Show(false)
		self:OnRestoreHelm()
	end
	
	self.wndMain:SetGlobalRadioSel("CharacterCustomization_SelectedOption", -1)
	for idx, tCategory in pairs(self.arCurrentCustomizationOptions) do
		tCategory.valueIdx = self.tPreviousOptions[tCategory.sliderId]
		self.tOptionWindows[tCategory.sliderId].wndHeader:SetData(tCategory)
	end
	Event_CancelDyeWindow()
end

function CharacterCustomization:OnCancel(wndHandler, wndControl)
	local wndOverlay = self.wndMain:FindChild("ConfirmationOverlay")
	local wndCancelConfirm = wndOverlay:FindChild("CancelConfirmation")
	
	local arChanges = self.wndMain:FindChild("PreviewChangesFlyout:CostPreviewContainer"):GetChildren()
	if not wndOverlay:IsShown() and (arChanges and #arChanges > 0 or self:CheckForBoneChanges()) then
		self:ToggleOverlay(ktOverlayTypes.Cancel, true)
		local wndParent = self.wndMain:GetParent()
		local wndGrandparent = wndParent:GetParent()
		wndParent:Show(true)
		wndGrandparent:Invoke()		
	else
		self:OnClose()
	end
end

function CharacterCustomization:OnCloseConfirm(wndHandler, wndControl)
	self:ToggleOverlay(ktOverlayTypes.Cancel, false)
	self:OnClose()
end

function CharacterCustomization:OnCloseCancel(wndHandler, wndControl)
	self:ToggleOverlay(ktOverlayTypes.Cancel, false)
end

-----------------------------------------------------------------------------------------------
-- Costume Window Controls
-----------------------------------------------------------------------------------------------
function CharacterCustomization:OnRotateRight()
	self.wndPreview:ToggleLeftSpin(true)
end

function CharacterCustomization:OnRotateRightCancel()
	self.wndPreview:ToggleLeftSpin(false)
end

function CharacterCustomization:OnRotateLeft()
	self.wndPreview:ToggleRightSpin(true)
end

function CharacterCustomization:OnRotateLeftCancel()
	self.wndPreview:ToggleRightSpin(false)
end

function CharacterCustomization:OnSheatheCheck(wndHandler, wndControl)
	self.wndPreview:SetSheathed(wndHandler:IsChecked())
end

---------------------------------------------------------------------------------------------------
-- Save/Load Code window
---------------------------------------------------------------------------------------------------

function CharacterCustomization:OnSaveLoadBtn( wndHandler, wndControl)
	local wndSaveLoadForm = self.wndMain:FindChild("ConfirmationOverlay:CharacterCode")
	self:ToggleOverlay(ktOverlayTypes.Code, true)
	wndSaveLoadForm:FindChild("EditBox"):SetText(self.wndPreview:GetSliderCodes())
end

function CharacterCustomization:OnLoadCode(wndHandler, wndControl)
	local wndSaveLoadForm = self.wndMain:FindChild("ConfirmationOverlay:CharacterCode")
	
	local strCodes = wndSaveLoadForm:FindChild("CodeFraming:EditBox"):GetText()
	local tResults = self.wndPreview:SetBySliderCodes(strCodes)
	
	local bFailed = false
	local strErrorText = ""
	
	if not tResults then
		strErrorText = Apollo.GetString("Pregame_InvalidCode")
		wndSaveLoadForm:FindChild("CodeErrorText"):SetText(strErrorText)
		return
	end
	
	if tResults.bUnsupportedVersion then
		strErrorText = Apollo.GetString("Pregame_OutdatedCode")
		wndSaveLoadForm:FindChild("CodeErrorText"):SetText(strErrorText)
		return
	end
	
	if tResults.bFactionDoesntMatch then
		bFailed = true
		strErrorText = strErrorText .. ktFactionStrings[tResults.nFaction] .. "    "
	end
	
	if tResults.bRaceDoesntMatch then
		bFailed = true
		strErrorText = strErrorText .. ktRaceStrings[tResults.nRace] .. "    "
	end
	
	if tResults.bGenderDoesntMatch then
		bFailed = true
		strErrorText = strErrorText .. ktGenderStrings[tResults.nGender]
	end
	
	if not bFailed then
		self:ToggleOverlay(ktOverlayTypes.Code, false)
		self.wndMain:FindChild("PreviewChangesFlyout:CostPreviewContainer"):DestroyChildren()
		self.tCustomizationCosts = {}
		self.tChangedBones = {}
		self.wndBonePreviewItem = nil
		self:ToggleOverlay(ktOverlayTypes.Code)
		self:GetCharacterInfo()
		
		for idx, tCategoryInfo in pairs(self.arCurrentCustomizationOptions) do
			if tCategoryInfo.valueIdx ~= self.tPreviousOptions[tCategoryInfo.sliderId] then
				local wndCostPreview = Apollo.LoadForm(self.xmlDoc, "PreviewLineItem", self.wndMain:FindChild("PreviewChangesFlyout:CostPreviewContainer"), self)
				local monCost = self.wndPreview:GetCostForCustomizationSelection(tCategoryInfo.sliderId, tCategoryInfo.values[tCategoryInfo.valueIdx])
				wndCostPreview:FindChild("ListItemName"):SetText(tCategoryInfo.name)
				wndCostPreview:FindChild("UndoBtn"):SetData(tCategoryInfo.sliderId)
				wndCostPreview:FindChild("CashWindow"):SetAmount(monCost, true)
				self.tCustomizationCosts[tCategoryInfo.sliderId] = {strName = tCategoryInfo.name, monCost = monCost, wndPreview = wndCostPreview}
				self.tOptionWindows[tCategoryInfo.sliderId].wndHeader:FindChild("CategorySelectBtn:ElementChangedIcon"):Show(true)
			else
				self.tOptionWindows[tCategoryInfo.sliderId].wndHeader:FindChild("CategorySelectBtn:ElementChangedIcon"):Show(false)
			end
		end
		
		for idx, tBoneInfo in pairs(self.arCharacterBones) do
			self.tBoneWindows.tSliders[tBoneInfo.sliderId]:FindChild("SliderContainer:SliderBar"):SetValue(tBoneInfo.value)
			self.tBoneWindows.tSliders[tBoneInfo.sliderId]:FindChild("SliderContainer:SliderValue"):SetText(string.format("%.2f", tBoneInfo.value))
			
			self.tChangedBones[tBoneInfo.sliderId] = self.tPreviousBones[tBoneInfo.sliderId] ~= tBoneInfo.value
		end
		
		local bBonesChanged = self:CheckForBoneChanges()
		
		if bBonesChanged then
			self.wndBonePreviewItem = Apollo.LoadForm(self.xmlDoc, "PreviewLineItem", self.wndMain:FindChild("PreviewChangesFlyout:CostPreviewContainer"), self)
			self.wndBonePreviewItem:FindChild("ListItemName"):SetText(Apollo.GetString("CharacterCustomize_CustomizeFace"))
			self.wndBonePreviewItem:FindChild("CashWindow"):SetAmount(self.wndPreview:GetCostForBoneChanges(), true)
			self.wndBonePreviewItem:FindChild("UndoBtn"):SetData(-1)
		end
		
		self.tBoneWindows.wndHeader:FindChild("CategorySelectBtn:ElementChangedIcon"):Show(bBonesChanged)
		self:ReloadOpenCategory()
		self.wndMain:FindChild("PreviewChangesFlyout:CostPreviewContainer"):ArrangeChildrenVert()
		self:CalculateTotalCost()
		self:ResizePreview()
	else
		wndSaveLoadForm:FindChild("CodeErrorText"):SetText(strErrorText)
	end		
end

function CharacterCustomization:OnCancelLoad(wndHandler, wndControl)
	self:ToggleOverlay(ktOverlayTypes.Code, false)
end

-----------------------------------------------------------------------------------------------
-- Helpers?
-----------------------------------------------------------------------------------------------

function CharacterCustomization:ToggleOverlay(eConfirmationType, bShow)
	local wndOverlay = self.wndMain:FindChild("ConfirmationOverlay")
		
	wndOverlay:Show(bShow)
	wndOverlay:FindChild("PurchaseConfirmation"):Show(eConfirmationType == ktOverlayTypes.Purchase and bShow)
	wndOverlay:FindChild("CancelConfirmation"):Show(eConfirmationType == ktOverlayTypes.Cancel and bShow)
	wndOverlay:FindChild("CharacterCode"):Show(eConfirmationType == ktOverlayTypes.Code and bShow)
	
	local wndFooter = self.wndMain:FindChild("Footer")
	wndFooter:FindChild("BuyBtn"):Enable(not bShow)
	wndFooter:FindChild("CancelBtn"):Enable(not bShow)
	wndFooter:FindChild("CostPreview:ToggleFlyout"):Enable(not bShow)
	wndFooter:FindChild("UseTokenBtn"):Enable(not bShow and self.bHasToken)
	self.wndMain:FindChild("PreviewChangesFlyout"):Show(false)
end

function CharacterCustomization:CalculateTotalCost()
	if self.wndMain and self.wndMain:IsValid() then
		local wndCostPreviewContainer = self.wndMain:FindChild("Footer:CostPreview")
		local wndTotalCost = wndCostPreviewContainer:FindChild("TotalCost")
		local wndTokenLabel = wndCostPreviewContainer:FindChild("TokenLabel")
		local wndTokenIcon = wndCostPreviewContainer:FindChild("TokenIcon")
		
		if not self.bUseToken then
			wndTokenIcon:Show(false)
			wndTokenLabel:Show(false)
			wndTotalCost:Show(true)
			
			local monTotal = Money.new()
			
			for idx, tCost in pairs(self.tCustomizationCosts) do
				monTotal:SetAmount(monTotal:GetAmount() + tCost.monCost:GetAmount())
			end
			
			if self:CheckForBoneChanges() then
				local monBoneCost = self.wndPreview:GetCostForBoneChanges()
				
				if monTotal then
					monTotal:SetAmount(monTotal:GetAmount() + monBoneCost:GetAmount())
				else
					monTotal = monBoneCost
				end
			end

			local unitPlayer = GameLib.GetPlayerUnit()
			local monPlayerCurrency = GameLib.GetPlayerCurrency(Money.CodeEnumCurrencyType.Credits)
			
			self.wndMain:FindChild("Footer:BuyBtn"):Enable(monTotal and monTotal:GetAmount() > 0 and monPlayerCurrency:GetAmount() >= monTotal:GetAmount())
				
			if monTotal and monPlayerCurrency:GetAmount() < (monTotal:GetAmount()) then
				wndTotalCost:SetTextColor(ApolloColor.new("xkcdReddish"))
			else
				wndTotalCost:SetTextColor(ApolloColor.new("UI_TextMetalBodyHighlight"))
			end
				
			wndTotalCost:SetAmount(monTotal or 0, true)
		else
			wndTokenIcon:Show(true)
			wndTokenLabel:Show(true)
			wndTotalCost:Show(false)
			
			local nCostCount = 0
			for idx, value in pairs(self.tCustomizationCosts or {}) do
				nCostCount = nCostCount + 1
			end
			
			self.wndMain:FindChild("Footer:BuyBtn"):Enable(nCostCount > 0 or self:CheckForBoneChanges())
			
			local luaSubclass = wndTokenIcon:GetWindowSubclass()
			local itemToken = Item.GetDataFromId(knTokenItemId)
			luaSubclass:SetItem(itemToken)
		end
		
		local arPreviewWindows = self.wndMain:FindChild("PreviewChangesFlyout:CostPreviewContainer"):GetChildren()
		for idx, wndPreview in pairs(arPreviewWindows) do
			wndPreview:FindChild("CashWindow"):Show(not self.bUseToken)
		end
	end
end

function CharacterCustomization:ResizeTree()
	local wndLeftScroll = self.wndMain:FindChild("LeftContainer:CategoryScrollContainer")
	local arHeaders = wndLeftScroll:GetChildren()
	local nHeaderHeight = arHeaders[1]:GetHeight()
	local nOpenIndex = nil

	for idx, wndCategory in pairs(arHeaders) do
		if wndCategory:GetName() ~= "CodeCategoryHeader" then
			local wndOptionContainer = wndCategory:FindChild("GroupContents")
			local wndTopButton = wndCategory:FindChild("CategorySelectBtn")
			local nCurrentCategoryOffset = 0
			
			if wndTopButton:IsChecked() and wndOptionContainer:IsShown() then
				local arOptions = wndOptionContainer:GetChildren()
				
				--Customization options are treated differently than Bone options
				if arOptions[1]:GetName() == "OptionItem" then
					nCurrentCategoryOffset = arOptions[1]:GetHeight() * (math.ceil(#arOptions / 2))
				else
					nCurrentCategoryOffset = arOptions[1]:GetHeight() * #arOptions
				end

				if nCurrentCategoryOffset > 0 then
					nCurrentCategoryOffset = nCurrentCategoryOffset + 6
				end
				
				nOpenIndex = idx
			end

			local nLeft, nTop, nRight, nBottom = wndOptionContainer:GetAnchorOffsets()
			wndOptionContainer:SetAnchorOffsets(nLeft, nTop, nRight, nTop + nCurrentCategoryOffset)
			wndOptionContainer:ArrangeChildrenTiles(0)
			
			local tOffset = wndCategory:GetOriginalLocation():ToTable().nOffsets
			wndCategory:SetAnchorOffsets(tOffset[1], tOffset[2], tOffset[3], tOffset[4] + nCurrentCategoryOffset)
		end
	end

	wndLeftScroll:ArrangeChildrenVert(0)
	
	if nOpenIndex then
		local nVScrollRange = wndLeftScroll:GetVScrollRange()
		local nHeaderTop = nHeaderHeight * (nOpenIndex - 1)
		wndLeftScroll:SetVScrollPos(nHeaderTop < nVScrollRange and nHeaderTop or nVScrollRange)
	end
end

function CharacterCustomization:CheckForBoneChanges()
	local bBonesChanged = false
	for idx, bHasChanged in pairs(self.tChangedBones) do
		if bHasChanged then
			bBonesChanged = true
		end
	end
	
	if self.tBoneWindows.wndHeader then
		self.tBoneWindows.wndHeader:FindChild("CategorySelectBtn:ElementChangedIcon"):Show(bBonesChanged)
	end
	
	return bBonesChanged
end

function CharacterCustomization:CheckForTokens()
	if self.wndMain and self.wndMain:IsValid() then
		local unitPlayer = GameLib.GetPlayerUnit()
		local tInventory = unitPlayer:GetInventoryItems()
		self.bHasToken = false
		for idx, tInventoryInfo in pairs(tInventory) do
			if not self.bHasToken and tInventoryInfo.itemInBag:GetItemId() == knTokenItemId then
				self.bHasToken = true
			end
		end
		
		local wndUseTokenBtn = self.wndMain:FindChild("Footer:UseTokenBtn")
		wndUseTokenBtn:Enable(self.bHasToken)
		wndUseTokenBtn:SetCheck(self.bHasToken and wndUseTokenBtn:IsChecked())
		
		self:OnUseTokenToggle(wndUseTokenBtn, wndUseTokenBtn)
	end
end

function CharacterCustomization:ReloadOpenCategory()
	if self.idSelectedCategory then
		local arCategoryWindows = self.wndMain:FindChild("LeftContainer:CategoryScrollContainer"):GetChildren()
		local wndOpenHeader = nil
		
		for idx, wndHeader in pairs(arCategoryWindows) do
			if wndHeader:FindChild("CategorySelectBtn"):GetData() == self.idSelectedCategory then
				wndOpenHeader = wndHeader
			end
		end
		
		if wndOpenHeader then
			self:LoadCustomizationOptions(wndOpenHeader, wndOpenHeader:GetData())
			wndOpenHeader:FindChild("GroupContents"):Show(true)
		end
	end
end

function CharacterCustomization:OnGenerateIconTooltip(wndHandler, wndControl)
	Tooltip.GetItemTooltipForm(self, wndControl, Item.GetDataFromId(knTokenItemId), {})
end

function CharacterCustomization:UndoAll()
	for idx, tBone in pairs(self.tPreviousBones) do
		local wndBone = self.tBoneWindows.tSliders[idx]:FindChild("UndoBtn")
		self:OnUndoBone(wndBone, wndBone)
	end
	
	for idx, tInfo in pairs(self.tCustomizationCosts) do
		local wndOptionUndo = tInfo.wndPreview:FindChild("UndoBtn")
		self:OnOptionUndo(wndOptionUndo, wndOptionUndo)
	end
end

-- Done to redraw characters
function CharacterCustomization:ResetTabs()
	if self.idSelectedCategory and self.tOptionWindows[self.idSelectedCategory] then
		local wndHeaderBtn = self.tOptionWindows[self.idSelectedCategory].wndHeader:FindChild("CategorySelectBtn")
		wndHeaderBtn:SetCheck(false)
		self:OnCategoryUncheck(wndHeaderBtn, wndHeaderBtn)
	end
end

function CharacterCustomization:OnHideHelm()
	self.wndPreview:RemoveItem(GameLib.CodeEnumItemSlots.Head)
	
	if self.idSelectedCategory and self.tOptionWindows[self.idSelectedCategory] then
		for idx, wndOption in pairs(self.tOptionWindows[self.idSelectedCategory].tOptions) do
			wndOption:FindChild("CostumeWindow"):RemoveItem(GameLib.CodeEnumItemSlots.Head)
		end
	end
end

function CharacterCustomization:OnRestoreHelm()
	self.wndPreview:SetItem(self.itemDisplayedHelm)
	
	if self.idSelectedCategory and self.tOptionWindows[self.idSelectedCategory] then
		for idx, wndOption in pairs(self.tOptionWindows[self.idSelectedCategory].tOptions) do
			wndOption:FindChild("CostumeWindow"):SetItem(self.itemDisplayedHelm)
		end
	end
end

function CharacterCustomization:HelperToggleHelm()
	local wndHideHelm = self.wndMain:FindChild("RightContent:HideHelmBtn")
	if self.bEnableHelmSwap then
		wndHideHelm:Show(true)
		
		if wndHideHelm:IsChecked() then
			self:OnHideHelm()
		else
			self:OnRestoreHelm()
		end
	else
		wndHideHelm:Show(false)
	end
end

function CharacterCustomization:OnReloadPreviewWindow()	
	for idx, tOption in pairs(self.arCurrentCustomizationOptions) do
		self.wndPreview:SetLook(tOption.sliderId, tOption.values[self.tPreviousOptions[tOption.sliderId]])
		self.wndPreview:SetLook(tOption.sliderId, tOption.values[tOption.valueIdx])
	end

	for idx, tOption in pairs(self.arCharacterBones) do
		self.wndPreview:SetBone(tOption.sliderId, tOption.value)
	end
end

-----------------------------------------------------------------------------------------------
-- CharacterCustomization Instance
-----------------------------------------------------------------------------------------------
local CharacterCustomizationInst = CharacterCustomization:new()
CharacterCustomizationInst:Init()
Window" Name="LeftAreaTimeCountdown" LAnchorPoint="0" LAnchorOffset="195" TAnchorPoint="0" TAnchorOffset="63" RAnchorPoint="1" RAnchorOffset="0" BAnchorPoint="1" BAnchorOffset="25" RelativeToClient="1" Font="CRB_HeaderGigantic_O" IgnoreMouse="1" NoClip="1" TooltipType="OnCursor" Text="00:09" TextId="" BGColor="white" TextColor="UI_BtnTextRedNormal" TooltipColor=""/>
        <Control Class="Window" LAnchorPoint="0" LAnchorOffset="0" TAnchorPoint="0" TAnchorOffset="0" RAnchorPoint="1" RAnchorOffset="0" BAnchorPoint="1" BAnchorOffset="0" RelativeToClient="1" Font="Default" Text="" Template="Default" Name="LeftAreaMouseCatcher" BGColor="white" TextColor="white" Tooltip="" TooltipColor="">
            <Control Class="Button" Base="CRB_Basekit:kitBtn_Holo_Close" Font="CRB_InterfaceMedium" ButtonType="PushButton" RadioGroup="" LAnchorPoint="1" LAnchorOffset="-36" TAnchorPoint="0" TAnchorOffset="11" RAnchorPoint="1" RAnchorOffset="-18" BAnchorPoint="0" BAnchorOffset="29" DT_VCENTER="1" DT_CENTER="1" Name="TrackerAbandonButton" NoClip="1" NewControlDepth="3" WindowSoundTemplate="CloseWindowPhys" HideInEditor="1" Visible="1" BGColor="white" TextColor="white" NormalTextColor="white" PressedTextColor="white" FlybyTextColor="white" PressedFlybyTextColor="white" DisabledTextColor="white" TooltipColor="">
                <Event Name="ButtonSignal" Function="OnHideLeftAreaWindow"/>
            </Control>
        </Control>
    </Form>
    <Form Class="Window" LAnchorPoint="1" LAnchorOffset="-415" TAnchorPoint="0" TAnchorOffset="208" RAnchorPoint="1" RAnchorOffset="0" BAnchorPoint="0" BAnchorOffset="348" RelativeToClient="1" Font="Default" Text="" Template="Default" Name="ChallengeMinimized" Border="0" Picture="0" SwallowMouseClicks="1" Moveable="0" Escapable="0" Overlapped="0" BGColor="white" TextColor="white" IgnoreMouse="1" Visible="1" TooltipColor="" Tooltip="">
        <Control Class="Window" LAnchorPoint="1" LAnchorOffset="-40" TAnchorPoint="0" TAnchorOffset="12" RAnchorPoint="1" RAnchorOffset="0" BAnchorPoint="0" BAnchorOffset="140" RelativeToClient="1" Font="Default" Text="" Template="Default" Name="MinimizedContents" BGColor="white" TextColor="white" HideInEditor="0" Visible="0" TooltipType="OnCursor" Tooltip="" TooltipId="Challenges_ChallengeTracker" IgnoreMouse="1" TooltipColor="" TooltipFont="CRB_InterfaceSmall_O">
            <Control Class="Button" LAnchorPoint="0" LAnchorOffset="0" TAnchorPoint="0" TAnchorOffset="0" RAnchorPoint="1" RAnchorOffset="0" BAnchorPoint="1" BAnchorOffset="0" RelativeToClient="1" Font="Default" Text="" Template="Default" Name="SeparatorBG" Picture="0" IgnoreMouse="0" Sprite="" BGColor="white" TextColor="white" HideInEditor="0" NormalTextColor="white" PressedTextColor="white" FlybyTextColor="white" PressedFlybyTextColor="white" DisabledTextColor="white" Base="PlayerPathContent_TEMP:btn_Challenge_Expand" TooltipColor="" Visible="1">
                <Event Name="ButtonSignal" Function="OnMinimizedExpandClick"/>
            </Control>
        </Control>
        <Control Class="Window" LAnchorPoint="0" LAnchorOffset="105" TAnchorPoint="0" TAnchorOffset="24" RAnchorPoint="1" RAnchorOffset="0" BAnchorPoint="0" BAnchorOffset="126" RelativeToClient="1" Font="Default" Text="" Template="Default" Name="BlankTrackerMessage" BGColor="white" TextColor="white" Sprite="CRB_ChallengeTrackerSprites:sprChallengeFrame" Picture="1" IgnoreMouse="1" HideInEditor="1" Visible="0" TooltipColor="">
            <Control Class="Window" LAnchorPoint="0" LAnchorOffset="-1"