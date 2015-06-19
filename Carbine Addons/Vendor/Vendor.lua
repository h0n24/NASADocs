-----------------------------------------------------------------------------------------------
-- Client Lua Script
-- Copyright (c) NCsoft. All rights reserved
-----------------------------------------------------------------------------------------------

require "Window"
require "string"
require "math"
require "Sound"
require "Item"
require "Money"
require "GameLib"

local Vendor = {}

local kstrTabBuy     	= "VendorTab0"
local kstrTabSell    	= "VendorTab1"
local kstrTabBuyback 	= "VendorTab2"
local kstrTabRepair  	= "VendorTab3"
local knMaxGuildLimit 	= 2000000000 -- 2000 plat
local knMaxSpinnerValue = 99

local knHeaderContainerMinHeight = 8

local ktVendorRespondEvent =
{
	[Item.CodeEnumItemUpdateReason.Vendor] 		= Apollo.GetString("Vendor_Bought"),
	[Item.CodeEnumItemUpdateReason.Buyback] 	= Apollo.GetString("Vendor_BoughtBack"),
}

local karEvalColors =
{
	[Item.CodeEnumItemQuality.Inferior] 		= "ItemQuality_Inferior",
	[Item.CodeEnumItemQuality.Average] 			= "ItemQuality_Average",
	[Item.CodeEnumItemQuality.Good] 			= "ItemQuality_Good",
	[Item.CodeEnumItemQuality.Excellent] 		= "ItemQuality_Excellent",
	[Item.CodeEnumItemQuality.Superb] 			= "ItemQuality_Superb",
	[Item.CodeEnumItemQuality.Legendary] 		= "ItemQuality_Legendary",
	[Item.CodeEnumItemQuality.Artifact]		 	= "ItemQuality_Artifact",
}

function Vendor:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self

	o.tFactoryCache = {}
	o.idOpenedGroup = nil

	return o
end

function Vendor:Init()
	Apollo.RegisterAddon(self, false, "", {"Util"})
end

function Vendor:OnLoad()
	self.xmlDoc = XmlDoc.CreateFromFile("Vendor.xml")
	self.xmlDoc:RegisterCallback("OnDocumentReady", self)
end

function Vendor:OnDocumentReady()
	if self.xmlDoc == nil then
		return
	end

	Apollo.RegisterEventHandler("WindowManagementReady", 		"OnWindowManagementReady", self)

	Apollo.RegisterEventHandler("UpdateInventory", 				"OnUpdateInventory", self)
	Apollo.RegisterEventHandler("VendorItemsUpdated", 			"OnVendorItemsUpdated", self)
	Apollo.RegisterEventHandler("BuybackItemsUpdated", 			"OnBuybackItemsUpdated", self)
	Apollo.RegisterEventHandler("CloseVendorWindow", 			"OnCloseVendorWindow", self)
	Apollo.RegisterEventHandler("InvokeVendorWindow", 			"OnInvokeVendorWindow", self)
	Apollo.RegisterEventHandler("PlayerCurrencyChanged", 		"OnPlayerCurrencyChanged", self)

	-- Return events for buy/sell/repair
	Apollo.RegisterEventHandler("GenericError", 				"OnGenericError", self)
	Apollo.RegisterEventHandler("ItemDurabilityUpdate", 		"OnItemDurabilityUpdate", self)
	Apollo.RegisterEventHandler("ItemAdded", 					"OnItemAdded", self)
	Apollo.RegisterEventHandler("ItemRemoved", 					"OnItemRemoved", self)

	-- Guild events
	Apollo.RegisterEventHandler("GuildChange",					"OnGuildChange", self)
	Apollo.RegisterEventHandler("GuildBankWithdraw",			"OnGuildChange", self)
	Apollo.RegisterEventHandler("GuildWarCoinsChanged",			"OnPlayerCurrencyChanged", self)

    Apollo.RegisterTimerHandler("AlertMessageTimer", 			"OnAlertMessageTimer", self)
	Apollo.CreateTimer("AlertMessageTimer", 4.0, false)
	Apollo.StopTimer("AlertMessageTimer")

	self.wndVendor = Apollo.LoadForm(self.xmlDoc, "VendorWindow", nil, self)
	self.wndVendor:FindChild(kstrTabBuy):SetCheck(true)
	self.wndVendor:FindChild("GuildRepairBtn"):Enable(false)
	self.wndVendor:Show(false, true)

	self.wndItemContainer = self.wndVendor:FindChild("LeftSideContainer:ItemsList")
	self.wndBagWindow = self.wndVendor:FindChild("BagWindow")

	self.tAltCurrency = nil
	self.wndVendor:FindChild("AltCurrency"):Show(false, true)
	self.tDefaultSelectedItem = nil
	
	self.wndInteractBlocker = self.wndVendor:FindChild("InteractBlocker")
	self.wndInteractBlocker:Show(false, true)
	self.wndVendor:FindChild("AmountValue"):SetMinMax(0, 0)

	self.tVendorItems = {}
	self.tItemWndList = {}
	self.tBuybackItems = {}
	self.tRepairableItems = {}
	self.nCount = 0
end

function Vendor:OnWindowManagementReady()
	Event_FireGenericEvent("WindowManagementAdd", {wnd = self.wndVendor, strName = Apollo.GetString("CRB_Vendor"), nSaveVersion=3})
end

-----------------------------------------------------------------------------------------------

function Vendor:OnInvokeVendorWindow(unitArg) -- REFACTOR
	Event_FireGenericEvent("VendorInvokedWindow")

	local bIsRepairVendor = IsRepairVendor(unitArg)
	self.wndVendor:Show(true)
	self.wndVendor:SetData(unitArg)
	self.wndVendor:FindChild("VendorName"):SetText(unitArg:GetName())
	self.wndVendor:FindChild("VendorPortrait"):SetCostume(unitArg)
	self.wndVendor:FindChild("VendorPortrait"):SetModelSequence(150)
	self.wndVendor:FindChild(kstrTabBuy):SetCheck(true)
	self.wndVendor:FindChild(kstrTabSell):SetCheck(false)
	self.wndVendor:FindChild(kstrTabBuyback):SetCheck(false)
	self.wndVendor:FindChild(kstrTabRepair):SetCheck(false)
	self.wndVendor:FindChild(kstrTabRepair):Enable(bIsRepairVendor)

	if bIsRepairVendor then
		self:RefreshRepairTab()
	end

	self:RedrawFully()
end

function Vendor:OnUpdateInventory()
	if self.wndVendor and self.wndVendor:FindChild("VendorFlash") then
		self.wndVendor:FindChild("VendorFlash"):SetSprite("CRB_WindowAnimationSprites:sprWinAnim_BirthLargeTemp")
	end
	self:Redraw()
end

function Vendor:OnVendorItemsUpdated()
	self:Redraw()
end

function Vendor:OnBuybackItemsUpdated()
	self:RefreshBuyBackTab()
	self:Redraw()
end

function Vendor:OnPlayerCurrencyChanged()
	self.wndVendor:FindChild("Cash"):SetAmount(GameLib.GetPlayerCurrency(), false)
	if self.wndVendor:FindChild("AltCurrency"):IsShown() and self.tAltCurrency then
		self.wndVendor:FindChild("AltCurrency"):SetAmount(GameLib.GetPlayerCurrency(self.tAltCurrency.eMoneyType, self.tAltCurrency.eAltType), false)
	end

	self:Redraw()
end

---------------------------------------------------------------------------------------------------
-- Main Update Method
---------------------------------------------------------------------------------------------------

function Vendor:RedrawFully()
	if not self.wndVendor or not self.wndVendor:IsShown() then
		return
	end

	local nVScrollPos = self.wndItemContainer:GetVScrollPos()
	self.wndItemContainer:DestroyChildren()

	self:DisableBuyButton()

	self:Redraw()
	self:RefreshBuyBackTab()

	self.wndItemContainer:SetVScrollPos(nVScrollPos)
	self:OnPlayerCurrencyChanged()
	self:DisableAmountValue() 

	if not self.tDefaultSelectedItem then
		return
	end

	for key, wndHeader in pairs(self.wndItemContainer:GetChildren()) do
		for key2, wndItem in pairs(wndHeader:FindChild("VendorHeaderContainer"):GetChildren()) do
			local tData = wndItem:GetData()
			if tData ~= nil and tData.idUnique == self.tDefaultSelectedItem.idUnique then -- GOTCHA: We can't == compare item objects, but we can compare .id
				wndItem:FindChild("VendorListItemBtn"):SetCheck(true)
				self:FocusOnVendorListItem(wndItem:GetData())
				break
			end
		end
	end
end

function Vendor:Redraw()
	if not self.wndVendor or not self.wndVendor:IsShown() then
		return
	end

	self:HelperTabManagement()

	local tUpdateInfo = nil
	if self.wndVendor:FindChild(kstrTabBuy):IsChecked() then
		tUpdateInfo = self:UpdateVendorItems()
	elseif self.wndVendor:FindChild(kstrTabSell):IsChecked() then
		tUpdateInfo = self.tLastSellItems
	elseif self.wndVendor:FindChild(kstrTabBuyback):IsChecked() then
		tUpdateInfo = self:UpdateBuybackItems()
	elseif self.wndVendor:FindChild(kstrTabRepair):IsChecked() then
		tUpdateInfo = self:UpdateRepairableItems()
	end

	local bFullRedraw = tUpdateInfo and tUpdateInfo.tUpdatedItems and (tUpdateInfo.bChanged or tUpdateInfo.bItemCountChanged or tUpdateInfo.bGroupCountChanged)
	--if no more items in current tab, reset the tab to buy
	if not tUpdateInfo then
		self:HelperResetToBuyTab()
	elseif bFullRedraw then
		local nVScrollPos = self.wndItemContainer:GetVScrollPos()
		self.wndItemContainer:DestroyChildren()
		self:DisableBuyButton()

		self:DrawHeaderAndItems(tUpdateInfo.tUpdatedItems, tUpdateInfo.bChanged)

		self.wndItemContainer:SetVScrollPos(nVScrollPos)
	else
		self:DrawHeaderAndItems(tUpdateInfo.tUpdatedItems, tUpdateInfo.bChanged)
	end

	self:OnGuildChange() -- Also check Guild Repair
end

function Vendor:HelperTabManagement(tVendorList, bChanged)
	local unitVendor = self.wndVendor:GetData()
	if unitVendor then
		--check to disable Buy Tab
		local tBuybackItems = unitVendor:GetBuybackItems()
		self.wndVendor:FindChild(kstrTabBuyback):Enable(tBuybackItems and #tBuybackItems ~= 0)

		--check to disable Repair Tab
		if IsRepairVendor(unitVendor) then
			local tRepairableItems = unitVendor:GetRepairableItems()
			local bHasRepair = tRepairableItems and #tRepairableItems ~= 0
			self.wndVendor:FindChild(kstrTabRepair):Enable(bHasRepair)
			if not bHasRepair then
				self.wndVendor:FindChild(kstrTabRepair):SetText(Apollo.GetString("CRB_Repair"))
			end
		end
	end

	--check to disable Sell Tab
	self.tLastSellItems = self:UpdateSellItems()
	local tOtherItems = self.tLastSellItems.tUpdatedItems.tOther
	self.wndVendor:FindChild(kstrTabSell):Enable(tOtherItems and (tOtherItems.tItems and #tOtherItems.tItems ~= 0))
end

function Vendor:HelperResetToBuyTab()
	self.wndItemContainer:DestroyChildren()
	self:DisableBuyButton()
	self.wndVendor:FindChild(kstrTabSell):SetCheck(false)
	self.wndVendor:FindChild(kstrTabBuyback):SetCheck(false)
	self.wndVendor:FindChild(kstrTabRepair):SetCheck(false)
	
	self.wndVendor:FindChild(kstrTabBuy):SetCheck(true)
	self:DisableAmountValue()
	self:Redraw()

	self.timerBlockInteract = ApolloTimer.Create(self.wndItemContainer:ContainsMouse() and 2.0 or 0.2, false, "OnBlockBuyTimer", self)
	self.wndInteractBlocker:Show(true, true)
end

function Vendor:OnBlockBuyTimer()
	self.wndInteractBlocker:Show(false, false)
end

function Vendor:DrawHeaderAndItems(tVendorList, bChanged)
	for idHeader, tHeaderValue in pairs(tVendorList) do
		local wndCurr = self:FactoryCacheProduce(self.wndItemContainer, "VendorHeaderItem", "H"..idHeader)
		wndCurr:SetData(tHeaderValue)
		if self.idOpenedGroup == nil then
			self.idOpenedGroup = tHeaderValue.idGroup
		end
		wndCurr:FindChild("VendorHeaderBtn"):SetCheck(self.idOpenedGroup == tHeaderValue.idGroup)
		wndCurr:FindChild("VendorHeaderName"):SetText(tHeaderValue.strName)

		if wndCurr:FindChild("VendorHeaderBtn"):IsChecked() then
			self:DrawListItems(wndCurr:FindChild("VendorHeaderContainer"), tHeaderValue.tItems)
		end
		self:SizeHeader(wndCurr)
	end

	self.wndItemContainer:ArrangeChildrenVert(0)

	-- TODO: Advanced item info in frame
	-- TODO: Destroy advanced item info if nothing is selected
end

function Vendor:SizeHeader(wndHeader)
	local wndVendorHeaderContainer = wndHeader:FindChild("VendorHeaderContainer")

	-- Children, if checked
	local nOnGoingHeight = math.max(knHeaderContainerMinHeight, wndVendorHeaderContainer:ArrangeChildrenVert(0))

	-- Resize
	local nLeft, nTop, nRight, nBottom = wndVendorHeaderContainer:GetAnchorOffsets()
	wndVendorHeaderContainer:SetAnchorOffsets(nLeft, nTop, nRight, nTop + nOnGoingHeight)
	local nLeft2, nTop2, nRight2, nBottom2 = wndHeader:GetAnchorOffsets()
	wndHeader:SetAnchorOffsets(nLeft2, nTop2, nRight2, nTop2 + nOnGoingHeight + 57) -- Padding to the container and below it -- TODO Hardcoded formatting
end

function Vendor:DrawListItems(wndParent, tItems)
	for key, tCurrItem in pairs(tItems) do
		if not tCurrItem.bFutureStock then
			local wndCurr = self:FactoryCacheProduce(wndParent, "VendorListItem", "I"..tCurrItem.idUnique)
			self:DrawListItem(wndCurr, tCurrItem)
		end
	end

	-- After iterating
	if self.tAltCurrency then
		self.wndVendor:FindChild("AltCurrency"):SetAmount(GameLib.GetPlayerCurrency(self.tAltCurrency.eMoneyType, self.tAltCurrency.eAltType))
		self.wndVendor:FindChild("AltCurrency"):Show(true, true)
		self.wndVendor:FindChild("YourCashLabel"):Show(false)
		self.wndVendor:FindChild("CashBagBG"):ArrangeChildrenVert(0)
	else
		self.wndVendor:FindChild("AltCurrency"):Show(false)
		self.wndVendor:FindChild("YourCashLabel"):Show(true)
		self.wndVendor:FindChild("CashBagBG"):ArrangeChildrenVert(0)
	end

	local nHeight = wndParent:ArrangeChildrenVert(0)
	return nHeight
end

function Vendor:DrawListItem(wndCurr, tCurrItem)
	wndCurr:FindChild("VendorListItemBtn"):SetData(tCurrItem)
	wndCurr:FindChild("VendorListItemCantUse"):Show(self:HelperPrereqFailed(tCurrItem))

	if tCurrItem.eType ~= Item.CodeEnumLootItemType.AdventureSpell or tCurrItem.eType ~= Item.CodeEnumLootItemType.Cash then
		wndCurr:FindChild("VendorListItemIcon"):GetWindowSubclass():SetItem(tCurrItem.itemData)
	else
		wndCurr:FindChild("VendorListItemIcon"):SetSprite(tCurrItem.strIcon)
	end

	local monPrice = nil
	local tPrice = nil
	if tCurrItem.tPriceInfo then
		-- If the first price value is a token, use the 2nd to determine what to show as the player's cash.
		local bIsToken = tCurrItem.tPriceInfo.monPrice1:GetMoneyType() == Money.CodeEnumCurrencyType.GroupCurrency and tCurrItem.tPriceInfo.monPrice1:GetAltType() == Money.CodeEnumGroupCurrencyType.None
		
		tPrice = {}
		tPrice[1] = tCurrItem.tPriceInfo.monPrice1
		tPrice[2] = tCurrItem.tPriceInfo.monPrice2
		monPrice = bIsToken and tPrice[2] or tPrice[1]
	elseif tCurrItem.itemData then
		local itemData = tCurrItem.itemData
		if self.wndVendor:FindChild(kstrTabSell):IsChecked() or self.wndVendor:FindChild(kstrTabBuyback):IsChecked()then
			monPrice = itemData:GetSellPrice()
		elseif self.wndVendor:FindChild(kstrTabBuy):IsChecked() then
			monPrice = itemData:GetBuyPrice()
		elseif self.wndVendor:FindChild(kstrTabRepair):IsChecked() then
			monPrice = Money.new(Money.CodeEnumCurrencyType.Credits)
			monPrice:SetAmount(itemData:GetRepairCost())
		end
	end
	
	local strItemTitle = tCurrItem.strName
	local nSpinnerValue = self.wndVendor:FindChild("AmountValue"):GetValue()
	
	if not self.wndVendor:FindChild(kstrTabBuyback):IsChecked() and (tCurrItem.nStackSize > 1 or nSpinnerValue > 1) then
		if tCurrItem.nStackSize > 1 then
			wndCurr:FindChild("VendorListItemStackCount"):SetText(tCurrItem.nStackSize)
		end
		
		local nStackSize = tCurrItem.nStackSize
		if nSpinnerValue > 1 then
			nStackSize = nSpinnerValue
		end
		
		if tPrice then
			tPrice[1] = tPrice[1]:Multiply(nStackSize)
			tPrice[2] = tPrice[2]:Multiply(nStackSize)
		elseif monPrice then
			monPrice = monPrice:Multiply(nStackSize)
		end
	end
	
	if tCurrItem.nStockCount > 0 and self.wndVendor:FindChild(kstrTabBuy):IsChecked() then
		wndCurr:FindChild("VendorListItemStackCount"):SetText(String_GetWeaselString(Apollo.GetString("Vendor_LimitedItemCount"), tCurrItem.nStockCount))
		strItemTitle = String_GetWeaselString(Apollo.GetString("Vendor_LimitedItemCountTitle"), strItemTitle, tCurrItem.nStockCount)
	end
	wndCurr:FindChild("VendorListItemTitle"):SetText(strItemTitle)

	-- Costs
	local eCurrencyType = monPrice and monPrice:GetMoneyType() or 0
	
	if eCurrencyType ~= Money.CodeEnumCurrencyType.Credits and eCurrencyType ~= 0 then
		self.tAltCurrency = {}
		self.tAltCurrency.eMoneyType = eCurrencyType
		self.tAltCurrency.eAltType = monPrice:GetAltType()
	else
		self.tAltCurrency = nil
	end
	
	local wndCash = wndCurr:FindChild("VendorListItemCashWindow")
	if tPrice then
		wndCash:SetAmount(tPrice, true)
	elseif monPrice then
		wndCash:SetAmount(monPrice, true)
	else
		wndCash:SetMoneySystem(Money.CodeEnumCurrencyType.Credits)
		wndCash:SetAmount(0, true)
	end

	if self:HelperRecipeAlreadyKnown(tCurrItem) then
		wndCurr:FindChild("VendorListItemTitle"):SetText(String_GetWeaselString(Apollo.GetString("Vendor_KnownRecipe"), wndCurr:FindChild("VendorListItemTitle"):GetText()))
	end

	local strQualityColor = tCurrItem.itemData and tCurrItem.itemData:GetItemQuality() and karEvalColors[tCurrItem.itemData:GetItemQuality()] or "UI_TextHoloBody"
	wndCurr:FindChild("VendorListItemTitle"):SetTextColor(self:HelperPrereqBuyFailed(tCurrItem) and "xkcdReddish" or strQualityColor)
	wndCurr:FindChild("VendorListItemCashWindow"):SetTextColor(self:HelperIsTooExpensive(tCurrItem) and "xkcdReddish" or "white")
end

function Vendor:EnableBuyButton(tData)
	self:HideRestockingFee()
	self.wndVendor:FindChild("Buy"):Enable(true)
	self.wndVendor:FindChild("Buy"):SetData(tData)
	--BuyBack will apply to entire sold instance, and can't repair quantities.
	if not self.wndVendor:FindChild(kstrTabBuyback):IsChecked() and not self.wndVendor:FindChild(kstrTabRepair):IsChecked() then
		self:EnableAmountValue(tData)
	end
end

function Vendor:DisableBuyButton(bDontClear)
	self:HideRestockingFee()

	if self.wndVendor:FindChild(kstrTabRepair):IsChecked() then
		local nRepairAllCost = GameLib.GetRepairAllCost()
		self.wndVendor:FindChild("Buy"):Enable(nRepairAllCost > 0 and nRepairAllCost <= GameLib.GetPlayerCurrency():GetAmount())
	elseif bDontClear or self.tDefaultSelectedItem == nil then
		self.wndVendor:FindChild("Buy"):Enable(false)
	end

	if not bDontClear then
		self.wndVendor:FindChild("Buy"):SetData(nil)
	end

	self:SetBuyButtonText()
	self:DisableAmountValue()
end

function Vendor:DisableAmountValue()
	local wndAmountValue = self.wndVendor:FindChild("AmountValue")
	local wndAmountFrame = self.wndVendor:FindChild("AmountFrame")
	local wndAmountBlocker = self.wndVendor:FindChild("AmountBlocker")
	if wndAmountValue and wndAmountFrame and wndAmountBlocker then
		--Only  show disabled Amount if in the sell or buy tab.
		local bIsSellOrBuyTab = self.wndVendor:FindChild(kstrTabSell):IsChecked() or self.wndVendor:FindChild(kstrTabBuy):IsChecked()
		wndAmountValue:Show(bIsSellOrBuyTab)
		wndAmountFrame:Show(bIsSellOrBuyTab)
		wndAmountBlocker:Show(bIsSellOrBuyTab)
		wndAmountValue:Enable(false)
		wndAmountValue:SetMinMax(0, 0)
		wndAmountValue:SetValue(0)
	end
end

function Vendor:EnableAmountValue(tItemData)
	local wndAmountValue = self.wndVendor:FindChild("AmountValue")
	local wndAmountFrame= self.wndVendor:FindChild("AmountFrame")
	local wndAmountBlocker= self.wndVendor:FindChild("AmountBlocker")
	local bSelling = self.wndVendor:FindChild(kstrTabSell):IsChecked()

	if wndAmountValue and tItemData and wndAmountFrame and wndAmountBlocker then
		wndAmountValue:SetData(tItemData)
		--Only  show disabled Amount if in the sell or buy tab.
		local bIsSellOrBuyTab = self.wndVendor:FindChild(kstrTabSell):IsChecked() or self.wndVendor:FindChild(kstrTabBuy):IsChecked()
		wndAmountValue:Show(bIsSellOrBuyTab)
		wndAmountFrame:Show(bIsSellOrBuyTab)
		wndAmountBlocker:Show(false)
		wndAmountValue:Enable(true)
		
		local nSetAmount = bSelling and tItemData.nStackSize or 1
		wndAmountValue:SetMinMax(1 , self.nSpinnerMaxAmount)
		wndAmountValue:SetValue(nSetAmount)
	end
end

function Vendor:OnSpinnerChanged(wndHandler, wndControl)
	if wndHandler ~= wndControl then
		return
	end
	
	local wndSelectedItem = wndHandler:GetData()
	local tItemData  = wndSelectedItem and wndSelectedItem:GetData()
	self:DrawListItem(wndSelectedItem, tItemData)
end

function Vendor:OnVendorListItemCheck(wndHandler, wndControl) -- TODO REFACTOR
    if not wndHandler or not wndHandler:GetData() then
		return
	end

	local wndAmountValue = self.wndVendor:FindChild("AmountValue")
	if wndAmountValue then
		local wndPreviousSelected = wndAmountValue:GetData() 
		local tItemData = wndHandler:GetData()
		self.tDefaultSelectedItem = nil -- Erase the default selection now
		self:FocusOnVendorListItem(tItemData)
		
		--If the user has unchecked, then checked the same item without clicking a different item, remember the amount.
		--Necessary for processing the double click buy.
		if wndPreviousSelected == wndHandler and self.nPreviousValue then
			wndAmountValue:SetValue(self.nPreviousValue)
		else
			self.nPreviousValue = nil
		end
		wndAmountValue:SetData(wndHandler)--saving the listitem containing the item information.
	end
end

function Vendor:OnVendorListItemUncheck(wndHandler, wndControl) -- TODO REFACTOR
	if not wndHandler or not wndHandler:GetData() then
		return
	end

	self.tDefaultSelectedItem = nil -- Erase the default selection now
	self:DisableBuyButton()
	self:OnGuildChange()
	self:DisableAmountValue()
	
	local tItemData = wndHandler:GetData()
	self:DrawListItem(wndHandler:GetParent(), tItemData)
end

function Vendor:OnVendorListItemMouseDown(wndHandler, wndControl, eMouseButton, nPosX, nPosY, bDoubleClick)
	if Apollo.IsShiftKeyDown() or Apollo.IsControlKeyDown() or Apollo.IsAltKeyDown() then
		local tItemPreview = wndHandler:GetData()
		Event_FireGenericEvent("GenericEvent_ContextMenuItem", tItemPreview and tItemPreview.itemData)
		return true
	elseif (eMouseButton == GameLib.CodeEnumInputMouse.Left and bDoubleClick) or eMouseButton == GameLib.CodeEnumInputMouse.Right then -- left double click or right click
		self:OnVendorListItemCheck(wndHandler, wndControl)
		if self.wndVendor:FindChild("Buy"):IsEnabled() then
			self:OnBuy(self.wndVendor:FindChild("Buy"), self.wndVendor:FindChild("Buy")) -- hackish, simulate a buy button click
			self.tDefaultSelectedItem = nil
			--Currently, when buying with a double click, the item is deselected as desired by the designers. So make sure to disable amount value.
			if eMouseButton == GameLib.CodeEnumInputMouse.Left and bDoubleClick then
				self:DisableAmountValue()
			end
		end
		return true
	end
end

function Vendor:SelectNextItemInLine(tItem)
	--[[ No longer desired functionality, the entire stack sells on the click
	-- If there's more in the stack, use the same item still
	if tItem.stackSize > 1 then
		self.tDefaultSelectedItem = tItem
		return
	end
	]]--

	-- Look for the item's window in the list
	local wndPrev = nil
	for key, wndHeader in pairs(self.wndItemContainer:GetChildren()) do
		wndPrev = wndHeader:FindChild("VendorHeaderContainer"):FindChildByUserData(tItem)
		if wndPrev then
			break
		end
	end

	if not wndPrev then
		return
	end

	-- Now that we found the window, find the next sibling in the list
	local nNextItem = -1
	for nCurr, wndCurr in pairs(wndPrev:GetParent():GetChildren()) do -- TODO HACKish, though GetParent():GetChildren() might be safe
		if nNextItem == nCurr then
			self.tDefaultSelectedItem = wndCurr:GetData() -- We'll let the redraw re-select the item for us
		elseif wndCurr == wndPrev then
			nNextItem = nCurr + 1
		end
	end
end

function Vendor:FocusOnVendorListItem(tVendorItem)
	local nMostCanBuy = knMaxSpinnerValue
	if tVendorItem.nStockCount ~= 0 then
		nMostCanBuy = tVendorItem.nStockCount
	end
	local bDisableBuy = false

	-- TODO: Take second currency into account
	local nPrice = 0
	if tVendorItem.tPriceInfo then
		nPrice = tVendorItem.tPriceInfo.nAmount1
		if not self.wndVendor:FindChild(kstrTabBuyback):IsChecked() then
			nPrice = nPrice * tVendorItem.nStackSize
		end
	end
	
	if self.wndVendor:FindChild(kstrTabBuy):IsChecked() and nPrice > 0 then
		bDisableBuy = self:HelperIsTooExpensive(tVendorItem)
	end

	if self.wndVendor:FindChild(kstrTabBuyback):IsChecked() or self.wndVendor:FindChild(kstrTabRepair):IsChecked() then
		local nPlayerAmount = 0
		if tVendorItem.tPriceInfo.eCurrencyType1 ~= nil or tVendorItem.tPriceInfo.eAltType1 ~= nil then
			nPlayerAmount = GameLib.GetPlayerCurrency(tVendorItem.tPriceInfo.eCurrencyType1, tVendorItem.tPriceInfo.eAltType1):GetAmount()
		elseif tVendorItem.tPriceInfo.itemExchange1 ~= nil then
			nPlayerAmount = tVendorItem.tPriceInfo.itemExchange1:GetBackpackCount()
		end
		if nPrice > nPlayerAmount then
			bDisableBuy = true
		end
	elseif tVendorItem.bFutureStock or not tVendorItem.bMeetsPreq then
		bDisableBuy = true
	end
	
	if self.wndVendor:FindChild(kstrTabSell):IsChecked() then
		self.nSpinnerMaxAmount = tVendorItem.nStackSize
	end
	
	--EnableBuyButton calls EnableAmountValue, which needs information calculated for the min and max to buy/sell.
	if bDisableBuy then
		self:DisableBuyButton(true)
	else
		self:EnableBuyButton(tVendorItem)
	end	

	self:SetBuyButtonText()
end

---------------------------------------------------------------------------------------------------
-- Alert Message Handlers
---------------------------------------------------------------------------------------------------

function Vendor:OnItemAdded(itemBought, nCount, eReason)
	if self.wndVendor and self.wndVendor:IsShown() and ktVendorRespondEvent[eReason] then
		local strItem = nCount > 1 and String_GetWeaselString(Apollo.GetString("CombatLog_MultiItem"), nCount, itemBought:GetName()) or itemBought:GetName()
		self:ShowAlertMessageContainer(String_GetWeaselString(ktVendorRespondEvent[eReason] or Apollo.GetString("Vendor_Bought"), strItem), false)
		Sound.Play(Sound.PlayUIVendorBuy)
	end
end

function Vendor:OnItemRemoved(itemSold, nCount, eReason)
	if self.wndVendor and self.wndVendor:IsShown() and ktVendorRespondEvent[eReason] then
		local strMessage = nCount > 1 and String_GetWeaselString(Apollo.GetString("CombatLog_MultiItem"), nCount, itemSold:GetName()) or itemSold:GetName()
		self:ShowAlertMessageContainer(String_GetWeaselString(Apollo.GetString("Vendor_Sold"), strMessage), false)
		Sound.Play(Sound.PlayUIVendorSell)
	end
end

function Vendor:OnGenericError(eError, strMessage)

	local tPurchaseFailEvent =  -- index is enums to respond to, value is optional (UNLOCALIZED) replacement string (otherwise the passed string is used)
	{
		[GameLib.CodeEnumGenericError.DbFailure] 						= "",
		[GameLib.CodeEnumGenericError.Item_BadId] 						= "",
		[GameLib.CodeEnumGenericError.Vendor_StackSize] 				= "",
		[GameLib.CodeEnumGenericError.Vendor_SoldOut] 					= "",
		[GameLib.CodeEnumGenericError.Vendor_UnknownItem] 				= "",
		[GameLib.CodeEnumGenericError.Vendor_FailedPreReq] 				= "",
		[GameLib.CodeEnumGenericError.Vendor_NotAVendor]				= "",
		[GameLib.CodeEnumGenericError.Vendor_TooFar] 					= "",
		[GameLib.CodeEnumGenericError.Vendor_BadItemRec] 				= "",
		[GameLib.CodeEnumGenericError.Vendor_NotEnoughToFillQuantity] 	= "",
		[GameLib.CodeEnumGenericError.Vendor_NotEnoughCash] 			= "",
		[GameLib.CodeEnumGenericError.Vendor_UniqueConstraint] 			= "",
		[GameLib.CodeEnumGenericError.Vendor_ItemLocked] 				= "",
		[GameLib.CodeEnumGenericError.Vendor_IWontBuyThat] 				= "",
		[GameLib.CodeEnumGenericError.Vendor_NoQuantity] 				= "",
		[GameLib.CodeEnumGenericError.Vendor_BagIsNotEmpty] 			= "",
		[GameLib.CodeEnumGenericError.Vendor_CuratorOnlyBuysRelics] 	= "",
		[GameLib.CodeEnumGenericError.Vendor_CannotBuyRelics] 			= "",
		[GameLib.CodeEnumGenericError.Vendor_NoBuyer] 					= "",
		[GameLib.CodeEnumGenericError.Vendor_NoVendor] 					= "",
		[GameLib.CodeEnumGenericError.Vendor_Buyer_NoActionCC] 			= "",
		[GameLib.CodeEnumGenericError.Vendor_Vendor_NoActionCC] 		= "",
		[GameLib.CodeEnumGenericError.Vendor_Vendor_Disposition] 		= "",
		[GameLib.CodeEnumGenericError.Item_InventoryFull] 				= "",
		[GameLib.CodeEnumGenericError.Item_UnknownItem] 				= "",
		[GameLib.CodeEnumGenericError.Item_QuestViolation] 				= "",
		[GameLib.CodeEnumGenericError.Item_Unique] 						= "",
		[GameLib.CodeEnumGenericError.Faction_NotEnoughRep] 			= "",
		[GameLib.CodeEnumGenericError.Item_NeedsRepair]					= "",
	}

	if self.wndVendor and self.wndVendor:IsShown() and tPurchaseFailEvent[eError] then
		if tPurchaseFailEvent[eError] ~= "" then
			strMessage = tPurchaseFailEvent[eError]
		end
		self:ShowAlertMessageContainer(strMessage, true)
	end
end

function Vendor:OnItemDurabilityUpdate(itemCurr, nOldValue)
	if self.nCount ~= 0 then
		return
	end

	local nNewValue = itemCurr:GetDurability()
	if self.wndVendor and self.wndVendor:IsShown() and nNewValue > nOldValue then
		self:DisableBuyButton()
		self.tRepairableItems = nil
		self:Redraw()

		self:ShowAlertMessageContainer(Apollo.GetString("Vendor_RepairsComplete"), false)
		self.nCount = self.nCount + 1
	end
end

function Vendor:ShowAlertMessageContainer(strMessage, bFailed)
	self.wndVendor:FindChild("AlertMessageText"):SetText(strMessage)
	self.wndVendor:FindChild("AlertMessageTitleSucceed"):Show(not bFailed)
	self.wndVendor:FindChild("AlertMessageTitleFail"):Show(bFailed)
	Event_FireGenericEvent("GenericEvent_LootChannelMessage", strMessage)
	self.wndVendor:FindChild("VendorFlash"):SetSprite("CRB_WindowAnimationSprites:sprWinAnim_BirthLargeTemp")

	Apollo.StopTimer("AlertMessageTimer")
	Apollo.StartTimer("AlertMessageTimer")
end

function Vendor:HideRestockingFee()
	local strMessage = Apollo.GetString("Vendor_RestockAlert")

	if self.wndVendor:FindChild("AlertMessageText"):GetText() == strMessage then
		self.wndVendor:FindChild("AlertMessageContainer"):Show(false)
	end
end

function Vendor:ProcessingRestockingFee(tItemData)
	if not tItemData or not tItemData.itemData or not tItemData.itemData:HasRestockingFee() then
		return false
	end

	local wndAlertMessageContainer = self.wndVendor:FindChild("AlertMessageContainer")
	if not wndAlertMessageContainer then
		return false
	end

	local strMessage = Apollo.GetString("Vendor_RestockAlert")
	local wndAlertMessageText = wndAlertMessageContainer:FindChild("AlertMessageText")
	if wndAlertMessageText:GetText() == strMessage and wndAlertMessageText:IsVisible() then
		return false
	end

	local monSellInfo = tItemData.itemData:GetSellPrice()
	local wndAlertCost = wndAlertMessageContainer:FindChild("AlertCost")
	if monSellInfo and wndAlertCost then
		wndAlertCost:SetMoneySystem(monSellInfo:GetMoneyType())
		wndAlertCost:SetAmount(monSellInfo:GetAmount())
	end

	wndAlertMessageText:SetText(strMessage)
	wndAlertMessageContainer:FindChild("AlertMessageTitleSucceed"):Show(false)
	wndAlertMessageContainer:FindChild("AlertMessageTitleFail"):Show(false)
	wndAlertMessageContainer:Show(false, true)
	wndAlertMessageContainer:Show(true)
	return true
end

function Vendor:OnAlertMessageTimer()
	Apollo.StopTimer("AlertMessageTimer")
	self.wndVendor:FindChild("AlertMessageContainer"):Show(false)
end

function Vendor:RefreshBuyBackTab()
	local tNewBuybackItems = self.wndVendor:GetData():GetBuybackItems()

	local nCount = 0
	if tNewBuybackItems ~= nil then
		nCount = #tNewBuybackItems
	end
	if nCount == 0 then
		self.wndVendor:FindChild(kstrTabBuyback):SetText(Apollo.GetString("CRB_Buyback"))
	else
		self.wndVendor:FindChild(kstrTabBuyback):SetText(String_GetWeaselString(Apollo.GetString("Vendor_TabLabelMultiple"), Apollo.GetString("CRB_Buyback"), nCount))
	end
end

function Vendor:RefreshRepairTab()
	local tNewRepairableItems = {}
	if IsRepairVendor(self.wndVendor:GetData()) then
		tNewRepairableItems = self.wndVendor:GetData():GetRepairableItems()
		for idx, tItem in pairs(tNewRepairableItems or {}) do
			tItem.idUnique = tItem.idLocation
		end
	end
	
	self.wndVendor:FindChild("TotalRepairFeesCashWindow"):SetAmount(GameLib.GetRepairAllCost(), false)

	local nCount = tNewRepairableItems and #tNewRepairableItems or 0

	if nCount == 0 then
		self.wndVendor:FindChild(kstrTabRepair):SetText(Apollo.GetString("CRB_Repair"))
	else
		self.wndVendor:FindChild(kstrTabRepair):SetText(String_GetWeaselString(Apollo.GetString("Vendor_TabLabelMultiple"), Apollo.GetString("CRB_Repair"), nCount))
	end
end

---------------------------------------------------------------------------------------------------
-- Old Buy vs Sell vs Etc. Update Methods
-- TODO: Refactor this entire thing
---------------------------------------------------------------------------------------------------

function Vendor:UpdateVendorItems() -- TODO: Old code
	if not self.wndVendor:GetData() then -- Get Data should be the Vendor Unit
		return
	end

	local tVendorGroups = self.wndVendor:GetData():GetVendorGroups()
	local tNewVendorItems = self.wndVendor:GetData():GetVendorItems()
	local tNewVendorItemsByGroup = self:ArrangeGroups(tNewVendorItems, tVendorGroups)

	local bChanged = false
	local bItemCountChanged = false
	local bGroupCountChanged = false
	if self.tVendorItemsByGroup == nil or not self:TableEquals(tNewVendorItemsByGroup, self.tVendorItemsByGroup) then
		bChanged = true
		bItemCountChanged = #tNewVendorItems ~= (self.tVendorItems ~= nil and #self.tVendorItems or 0)
		bGroupCountChanged = #tNewVendorItemsByGroup ~= (self.tVendorItemsByGroup ~= nil and #self.tVendorItemsByGroup or 0)
		self.tVendorItems = tNewVendorItems
		self.tVendorItemsByGroup = tNewVendorItemsByGroup
	end

	local tReturn = {}
	tReturn.bChanged = bChanged
	tReturn.bItemCountChanged = bItemCountChanged
	tReturn.bGroupCountChanged = bGroupCountChanged
	tReturn.tUpdatedItems = self.tVendorItemsByGroup

	return tReturn
end

---------------------------------------------------------------------------------------------------
function Vendor:UpdateSellItems()
	local unitPlayer = GameLib.GetPlayerUnit()
	
	if not self.wndVendor:GetData() or not unitPlayer then -- Get Data should be the Vendor Unit
		return
	end

	local tInvItems = unitPlayer:GetInventoryItems()
	local tNewSellItems = {}
	for key, tItemData in ipairs(tInvItems) do
		local itemCurr = self:ItemToVendorSellItem(tItemData.itemInBag, 1)
		if itemCurr then
			table.insert(tNewSellItems, itemCurr)
		end
	end

	local tSellGroups = {{idGroup = 1, strName = "Backpack"}}
	local tNewSellItemsByGroup = self:ArrangeGroups(tNewSellItems, tSellGroups)

	local bChanged = false
	local bItemCountChanged = false
	local bGroupCountChanged = false
	if self.tSellItemsByGroup == nil or not self:TableEquals(tNewSellItemsByGroup, self.tSellItemsByGroup) then
		bChanged = true
		bItemCountChanged = #tNewSellItems ~= (self.tSellItems ~= nil and #self.tSellItems or 0)
		bGroupCountChanged = #tNewSellItemsByGroup ~= (self.tSellItemsByGroup ~= nil and #self.tSellItemsByGroup or 0)
		self.tSellItems = tNewSellItems
		self.tSellItemsByGroup = tNewSellItemsByGroup
	end

	if self.tSellItemsByGroup.tOther then
		self.tSellItemsByGroup.tOther.strName = Apollo.GetString("QuestLog_All")
	end

	local tReturn = {}
	tReturn.bChanged = bChanged
	tReturn.bItemCountChanged = bItemCountChanged
	tReturn.bGroupCountChanged = bGroupCountChanged
	tReturn.tUpdatedItems = self.tSellItemsByGroup

	return tReturn
end

---------------------------------------------------------------------------------------------------
function Vendor:UpdateBuybackItems()
	if not self.wndVendor:GetData() then -- Get Data should be the Vendor Unit
		return
	end

	local tNewBuybackItems = self.wndVendor:GetData():GetBuybackItems()
	local tNewBuybackItemsByGroup = self:ArrangeGroups(tNewBuybackItems)

	self:RefreshBuyBackTab()

	local bChanged = false
	local bItemCountChanged = false
	local bGroupCountChanged = false
	if self.tBuybackItemsByGroup == nil or not self:TableEquals(tNewBuybackItemsByGroup, self.tBuybackItemsByGroup) then
		bChanged = true
		bItemCountChanged = #tNewBuybackItems ~= (self.tBuybackItems ~= nil and #self.tBuybackItems or 0)
		bGroupCountChanged = #tNewBuybackItemsByGroup ~= (self.tBuybackItemsByGroup ~= nil and #self.tBuybackItemsByGroup or 0)
		self.tBuybackItems = tNewBuybackItems
		self.tBuybackItemsByGroup = tNewBuybackItemsByGroup
	end

	if self.tBuybackItemsByGroup.tOther then
		self.tBuybackItemsByGroup.tOther.strName = Apollo.GetString("QuestLog_All")
	end

	local tReturn = {}
	tReturn.bChanged = bChanged
	tReturn.bItemCountChanged = bItemCountChanged
	tReturn.bGroupCountChanged = bGroupCountChanged
	tReturn.tUpdatedItems = self.tBuybackItemsByGroup

	return tReturn
end

---------------------------------------------------------------------------------------------------
function Vendor:UpdateRepairableItems()
	if not self.wndVendor:GetData() then -- Get Data should be the Vendor Unit
		return
	end

	local tNewRepairableItems = {}
	if IsRepairVendor(self.wndVendor:GetData()) then
		tNewRepairableItems = self.wndVendor:GetData():GetRepairableItems()
		for idx, tItem in pairs(tNewRepairableItems or {}) do
			tItem.idUnique = tItem.idLocation
		end
	end

	local tNewRepairableItemsByGroup = self:ArrangeGroups(tNewRepairableItems)

	self:RefreshRepairTab()

	local bChanged = false
	local bItemCountChanged = false
	local bGroupCountChanged = false
	if self.tRepairableItemsByGroup == nil or not self:TableEquals(tNewRepairableItemsByGroup, self.tRepairableItemsByGroup) then
		bChanged = true
		bItemCountChanged = #tNewRepairableItems ~= (self.tRepairableItems ~= nil and #self.tRepairableItems or 0)
		bGroupCountChanged = #tNewRepairableItemsByGroup ~= (self.tRepairableItemsByGroup ~= nil and #self.tRepairableItemsByGroup or 0)
		self.tRepairableItems = tNewRepairableItems
		self.tRepairableItemsByGroup = tNewRepairableItemsByGroup
	end

	if self.tRepairableItemsByGroup.tOther then
		self.tRepairableItemsByGroup.tOther.strName = Apollo.GetString("QuestLog_All")
	end

	local tReturn = {}
	tReturn.bChanged = bChanged
	tReturn.bItemCountChanged = bItemCountChanged
	tReturn.bGroupCountChanged = bGroupCountChanged
	tReturn.tUpdatedItems = self.tRepairableItemsByGroup

	return tReturn
end

---------------------------------------------------------------------------------------------------
-- Simple UI Methods
---------------------------------------------------------------------------------------------------

function Vendor:OnWindowClosed()
	Event_CancelVending()
end

function Vendor:OnCloseBtn()
	self.wndVendor:Close()
end

function Vendor:OnCloseVendorWindow()
	self.wndVendor:Close()
end

-----------------------------------------------------------------------------------------------
-- Guild
-----------------------------------------------------------------------------------------------

function Vendor:OnGuildChange() -- Catch All method to validate Guild Repair
	if not self.wndVendor or not self.wndVendor:IsValid() or not self.wndVendor:IsVisible() then
		return
	end

	local tMyGuild = nil
	for idx, tGuild in pairs(GuildLib.GetGuilds()) do
		if tGuild:GetType() == GuildLib.GuildType_Guild then
			tMyGuild = tGuild
			break
		end
	end

	local bIsRepairing = self.wndVendor:FindChild(kstrTabRepair):IsChecked()

	-- The following code allows for tMyGuild to be nil
	local nLeft, nTop, nRight, nBottom = self.wndVendor:FindChild("LeftSideContainer"):GetAnchorOffsets()
	local nLeft2, nTop2, nRight2, nBottom2 = self.wndVendor:FindChild("BottomContainer"):GetAnchorOffsets()
	self.wndVendor:FindChild("LeftSideContainer"):SetAnchorOffsets(nLeft, nTop, nRight, (tMyGuild and bIsRepairing) and -138 or -88) -- TODO HACKY: Hardcoded formatting
	self.wndVendor:FindChild("VendorFlash"):SetAnchorOffsets(nLeft, nTop, nRight, (tMyGuild and bIsRepairing) and -138 or -88) -- TODO HACKY: Hardcoded formatting
	self.wndVendor:FindChild("BottomContainer"):SetAnchorOffsets(nLeft2, (tMyGuild and bIsRepairing) and -138 or -88, nRight2, nBottom2) -- TODO HACKY: Hardcoded formatting
	self.wndVendor:FindChild("GuildRepairContainer"):Show(tMyGuild and bIsRepairing)

	if tMyGuild then -- If not valid, it won't be shown anyways
		local tMyRankData = tMyGuild:GetRanks()[tMyGuild:GetMyRank()]

		local nAvailableFunds
		local nRepairRemainingToday = math.min(knMaxGuildLimit, tMyRankData.monBankRepairLimit:GetAmount()) - tMyGuild:GetBankMoneyRepairToday():GetAmount()
		if tMyGuild:GetMoney():GetAmount() <= nRepairRemainingToday then
			nAvailableFunds = tMyGuild:GetMoney():GetAmount()
		else
			nAvailableFunds = nRepairRemainingToday
		end

		self.wndVendor:FindChild("GuildRepairFundsCashWindow"):SetAmount(math.max(0, nAvailableFunds))

		local repairableItems = self.wndVendor:GetData():GetRepairableItems()
		local bHaveItemsToRepair = #repairableItems > 0

		-- Check if you have enough and text color accordingly
		local nRepairAllCost = 0
		for key, tCurrItem in pairs(repairableItems) do
			local tCurrPrice = math.max(tCurrItem.tPriceInfo.nAmount1, tCurrItem.tPriceInfo.nAmount2) * tCurrItem.nStackSize
			nRepairAllCost = nRepairAllCost + tCurrPrice
		end
		local bSufficientFunds = nRepairAllCost <= nAvailableFunds

		-- Enable / Disable button
		local tCurrItem = self.wndVendor:FindChild("Buy"):GetData()
		if tCurrItem and tCurrItem.tPriceInfo then
			local tCurrPrice = math.max(tCurrItem.tPriceInfo.nAmount1, tCurrItem.tPriceInfo.nAmount2) * tCurrItem.nStackSize
			bSufficientFunds = tCurrPrice <= nAvailableFunds
		end

		self.wndVendor:FindChild("GuildRepairBtn"):Enable(nRepairRemainingToday > 0 and bHaveItemsToRepair and bSufficientFunds)
		self.wndVendor:FindChild("GuildRepairFundsCashWindow"):SetTextColor(bSufficientFunds and ApolloColor.new("UI_TextMetalBodyHighlight") or ApolloColor.new("red"))

		self.wndVendor:FindChild("GuildRepairBtn"):SetData(tMyGuild)
	end
end

function Vendor:OnGuildRepairBtn(wndHandler, wndControl)
	local tMyGuild = wndHandler:GetData()
	local tItemData = self.wndVendor:FindChild("Buy"):GetData()

	if tMyGuild and tItemData and tItemData.idLocation then
		tMyGuild:RepairItemVendor(tItemData.idLocation)
		local eRepairCurrency = tItemData.tPriceInfo.eCurrencyType1
		local nRepairAmount = tItemData.tPriceInfo.nAmount1
		self.wndVendor:FindChild("AlertCost"):SetMoneySystem(eRepairCurrency)
		self.wndVendor:FindChild("AlertCost"):SetAmount(nRepairAmount)
	elseif tMyGuild then
		tMyGuild:RepairAllItemsVendor()
		local monRepairAllCost = GameLib.GetRepairAllCost()
		self.wndVendor:FindChild("AlertCost"):SetMoneySystem(Money.CodeEnumCurrencyType.Credits)
		self.wndVendor:FindChild("AlertCost"):SetAmount(monRepairAllCost)
	end
	Sound.Play(Sound.PlayUIVendorRepair)
end

function Vendor:OnBuy(wndHandler, wndControl)
	if not wndHandler or not self.wndVendor:GetData() then
		return
	end

	self.nCount = 0
	local tItemData = wndHandler:GetData()
	if not self:ProcessingRestockingFee(tItemData) then
		self:FinalizeBuy(tItemData)
	end
end

function Vendor:FinalizeBuy(tItemData)
	local nAmount = 0
	local wndAmountValue = self.wndVendor:FindChild("AmountValue")
	if wndAmountValue then
		nAmount = wndAmountValue:GetValue()
		wndAmountValue:SetValue(wndAmountValue:GetMin())
	end

	if tItemData then
		local idItem = tItemData.idUnique
		if self.wndVendor:FindChild(kstrTabBuy):IsChecked() then
			BuyItemFromVendor(idItem, nAmount)
			self.tDefaultSelectedItem = tItemData

			if tItemData.itemData then
				local monBuyPrice = tItemData.itemData:GetBuyPrice()
				self.wndVendor:FindChild("AlertCost"):SetAmount(monBuyPrice)
			end
		elseif self.wndVendor:FindChild(kstrTabSell):IsChecked() then
			SellItemToVendorById(idItem, nAmount)
			self:SelectNextItemInLine(tItemData)
			self:Redraw()

			if tItemData.itemData then
				local monSellPrice = tItemData.itemData:GetSellPrice():Multiply(tItemData.nStackSize)
				self.wndVendor:FindChild("AlertCost"):SetAmount(monSellPrice)
			end
		elseif self.wndVendor:FindChild(kstrTabBuyback):IsChecked() then
			BuybackItemFromVendor(idItem)
			self:SelectNextItemInLine(tItemData)

			if tItemData.itemData then
				local monBuyBackPrice = tItemData.itemData:GetSellPrice():Multiply(tItemData.nStackSize)
				self.wndVendor:FindChild("AlertCost"):SetAmount(monBuyBackPrice)
			end
		elseif self.wndVendor:FindChild(kstrTabRepair):IsChecked() then
			local idLocation = tItemData.idLocation or nil
			if idLocation then
				RepairItemVendor(idLocation)
				local eRepairCurrency = tItemData.tPriceInfo.eCurrencyType1
				local nRepairAmount = tItemData.tPriceInfo.nAmount1
				self.wndVendor:FindChild("AlertCost"):SetMoneySystem(eRepairCurrency)
				self.wndVendor:FindChild("AlertCost"):SetAmount(nRepairAmount)
			else
				self:RepairAllHelper()
			end
			Sound.Play(Sound.PlayUIVendorRepair)
		end
	elseif self.wndVendor:FindChild(kstrTabRepair):IsChecked() then
		self:RepairAllHelper()
		Sound.Play(Sound.PlayUIVendorRepair)
	else
		return
	end
end

function Vendor:RepairAllHelper()
	RepairAllItemsVendor()
	local monRepairAllCost = GameLib.GetRepairAllCost()
	self.wndVendor:FindChild("AlertCost"):SetMoneySystem(Money.CodeEnumCurrencyType.Credits)
	self.wndVendor:FindChild("AlertCost"):SetAmount(monRepairAllCost)
end

function Vendor:OnTabBtn(wndHandler, wndControl)
	if not wndHandler then return end
	self.wndItemContainer:DestroyChildren()
	self.tDefaultSelectedItem = nil
	self.idOpenedGroup = nil
	self:DisableBuyButton()

	if self.wndInteractBlocker:IsShown() then
		self.timerBlockInteract:Stop()
		self:OnBlockBuyTimer()
	end
	self:DisableAmountValue()
	self:Redraw()
end

function Vendor:SetBuyButtonText()
	local strCaption = ""
	if self.wndVendor:FindChild(kstrTabBuy):IsChecked() then
		strCaption = Apollo.GetString("Vendor_Purchase")
	elseif self.wndVendor:FindChild(kstrTabSell):IsChecked() then
		strCaption = Apollo.GetString("Vendor_Sell")
	elseif self.wndVendor:FindChild(kstrTabBuyback):IsChecked() then
		strCaption = Apollo.GetString("Vendor_Purchase")
	elseif self.wndVendor:FindChild(kstrTabRepair):IsChecked() then
		strCaption = Apollo.GetString(self.wndVendor:FindChild("Buy"):GetData() and "Vendor_Repair" or "Vendor_RepairAll")
	else
		strCaption = Apollo.GetString("Vendor_Purchase")
	end
	
	if self.wndVendor:FindChild(kstrTabRepair):IsChecked() then
		self.wndVendor:FindChild("BottomContainer:RepairTotalFees"):Show(true)
	else
		self.wndVendor:FindChild("BottomContainer:RepairTotalFees"):Show(false)
	end

	self.wndVendor:FindChild("Buy"):SetText(String_GetWeaselString(strCaption, ""))
	self.wndVendor:FindChild("GuildRepairBtn"):SetText(Apollo.GetString(self.wndVendor:FindChild("Buy"):GetData() and "Vendor_GuildRepair" or "Vendor_GuildRepairAll"))
end

---------------------------------------------------------------------------------------------------
-- Old code
---------------------------------------------------------------------------------------------------

function Vendor:ArrangeGroups(tItemList, tGroups)
	local tNewList = {
		tOther =
		{
			strName = Apollo.GetString("ChallengeTypeGeneral"),
			tItems = {}
		}
	} --, specials = {}, future = {} } }

	if not tGroups then
		tNewList.tOther.tItems = tItemList
		return tNewList
	end

	for idx, value in ipairs(tGroups) do
		if value.strName and string.len(value.strName) > 0 then
			tNewList[value.idGroup] = { strName = value.strName, tItems = {}, idGroup = value.idGroup } --, specials = {}, future = {} }
		end
	end

	for idx, value in ipairs(tItemList) do
		local tGroup = tNewList[value.idGroup] or tNewList.tOther
		table.insert(tGroup.tItems, value)
	end

	for key, value in pairs(tNewList) do
		if #value.tItems == 0 then -- + #v.specials + #v.future == 0 then
			tNewList[key] = nil
		end
	end
	return tNewList
end

function Vendor:ItemToVendorSellItem(itemCurr, nGroup)
	if not itemCurr then
		return nil
	end

	local nSellPrice = itemCurr:GetSellPrice()
	if not nSellPrice then
		return nil
	end

	if not nGroup then
		nGroup = 0
	end

	local tNewItem = {}
	tNewItem.idUnique = itemCurr:GetInventoryId()
	tNewItem.idItem = itemCurr:GetItemId()
	tNewItem.eType = itemCurr:GetItemType()
	tNewItem.nStackSize = itemCurr:GetStackCount()
	tNewItem.nStockCount = 0
	tNewItem.idGroupId = nGroup
	tNewItem.bMeetsPreq = true
	tNewItem.bIsSpecial = false
	tNewItem.bFutureStock = false
	--tNewItem.price = {amount1 = sellPrice.GetAmount(), currencyType1 = sellPrice:GetMoneyType(), amount2 = 0, currencyType2 = 1}
	tNewItem.itemData = itemCurr
	tNewItem.strIcon = itemCurr:GetIcon()
	tNewItem.strName = itemCurr:GetName()
	return tNewItem
end

function Vendor:OnVendorListItemGenerateTooltip(wndControl, wndHandler) -- wndHandler is VendorListItemIcon
	if wndHandler ~= wndControl then
		return
	end

	wndControl:SetTooltipDoc(nil)

	local tListItem = wndHandler:GetData()
	local itemData = tListItem.itemData

	if itemData then
		local tPrimaryTooltipOpts = {}

		if self.wndVendor:FindChild(kstrTabSell):IsChecked() then
			tPrimaryTooltipOpts.bSelling = true
		elseif self.wndVendor:FindChild(kstrTabBuy):IsChecked() then
			tPrimaryTooltipOpts.bBuying = true
			tPrimaryTooltipOpts.nPrereqVendorId = tListItem.idPrereq
			tPrimaryTooltipOpts.itemModData = tListItem.itemModData
			tPrimaryTooltipOpts.strMaker = tListItem.strMaker
			tPrimaryTooltipOpts.arGlyphIds = tListItem.arGlyphIds
			tPrimaryTooltipOpts.tGlyphData = tListItem.itemGlyphData
			tPrimaryTooltipOpts.nStackCount = tListItem.nStackSize
			tPrimaryTooltipOpts.idVendorUnique = tListItem.idUnique
		elseif self.wndVendor:FindChild(kstrTabBuyback):IsChecked() then
			tPrimaryTooltipOpts.bBuyback = true
			tPrimaryTooltipOpts.nPrereqVendorId = tListItem.idPrereq			
			tPrimaryTooltipOpts.itemModData = tListItem.itemModData
			tPrimaryTooltipOpts.strMaker = tListItem.strMaker
			tPrimaryTooltipOpts.arGlyphIds = tListItem.arGlyphIds
			tPrimaryTooltipOpts.tGlyphData = tListItem.itemGlyphData
			tPrimaryTooltipOpts.nStackCount = tListItem.nStackSize
			tPrimaryTooltipOpts.idVendorUnique = tListItem.idUnique
		end

		tPrimaryTooltipOpts.itemCompare = itemData:GetEquippedItemForItemType()

		if Tooltip ~= nil and Tooltip.GetSpellTooltipForm ~= nil then
			Tooltip.GetItemTooltipForm(self, wndControl, itemData, tPrimaryTooltipOpts)
		end
	else
		if Tooltip ~= nil and Tooltip.GetSpellTooltipForm ~= nil then
			Tooltip.GetSpellTooltipForm(self, wndControl, tListItem.splData)
		end
	end
end

function Vendor:OnItemPriceTooltip(wndHandler, wndControl, eToolTipType, monA, monB)
	if eToolTipType == Tooltip.TooltipGenerateType_Money then
		local xml = nil
		
		if monA:GetAmount() > 0 then
			if xml == nil then
				xml = XmlDoc.new()
			end
			xml:AddLine("<P>".. monA:GetMoneyString() .."</P>")
		end
		
		if monB:GetAmount() > 0 then
			if xml == nil then
				xml = XmlDoc.new()
			end
			xml:AddLine("<P>".. monB:GetMoneyString() .."</P>")
		end
		
		wndControl:SetTooltipDoc(xml)
	end
end

-- Deep table equality
function Vendor:TableEquals(tData1, tData2)
   if tData1 == tData2 then
       return true
   end
   local strType1 = type(tData1)
   local strType2 = type(tData2)
   if strType1 ~= strType2 then
	   return false
   end
   if strType1 ~= "table" or strType2 ~= "table" then
       return false
   end
   for key, value in pairs(tData1) do
       if value ~= tData2[key] and not self:TableEquals(value, tData2[key]) then
           return false
       end
   end
   for key in pairs(tData2) do
       if tData1[key] == nil then
           return false
       end
   end
   return true
end

---------------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------------

function Vendor:HelperRecipeAlreadyKnown(tCurrItem)
	local bAlreadyKnown = false

	if self.wndVendor:FindChild(kstrTabBuy):IsChecked() then
		if tCurrItem.itemData ~= nil then
			local tSpellOnItem = tCurrItem.itemData:GetActivateSpell()
			if tSpellOnItem then
				local tTradeskillReqs = tSpellOnItem:GetTradeskillRequirements()
				if tTradeskillReqs and tTradeskillReqs.bIsKnown then
					bAlreadyKnown = true
				end
			end
		end
	end
	return bAlreadyKnown
end

function Vendor:HelperIsTooExpensive(tCurrItem)
	if not tCurrItem.tPriceInfo then
		return false
	end

	local bTooExpensive = false
	local nPlayerAmount = 0
	if tCurrItem.tPriceInfo.eCurrencyType1 ~= nil or tCurrItem.tPriceInfo.eAltType1 ~= nil then
		nPlayerAmount = GameLib.GetPlayerCurrency(tCurrItem.tPriceInfo.eCurrencyType1, tCurrItem.tPriceInfo.eAltType1):GetAmount()
	elseif tCurrItem.tPriceInfo.itemExchange1 ~= nil then
		nPlayerAmount = tCurrItem.tPriceInfo.itemExchange1:GetBackpackCount()
	end
	
	local nAmount = tCurrItem.tPriceInfo.monPrice1 and tCurrItem.tPriceInfo.monPrice1:GetAmount() or tCurrItem.tPriceInfo.monPrice2 and tCurrItem.tPriceInfo.monPrice2:GetAmount()
	if not self.wndVendor:FindChild(kstrTabBuyback):IsChecked() then
		nAmount = nAmount * tCurrItem.nStackSize
	end
	nMostCanBuy = knMaxSpinnerValue
	nMostCanBuy = math.min(nMostCanBuy, math.floor(nPlayerAmount / nAmount))
	self.nSpinnerMaxAmount = nMostCanBuy
	if nMostCanBuy == 0 then
		bTooExpensive = true
	end

	return bTooExpensive
end

function Vendor:HelperPrereqFailed(tCurrItem)
	return tCurrItem.itemData and tCurrItem.itemData:IsEquippable() and not tCurrItem.itemData:CanEquip()
end

function Vendor:HelperPrereqBuyFailed(tCurrItem)
	local bPrereqFailed = false

	if not self.wndVendor:FindChild(kstrTabRepair):IsChecked() then
		bPrereqFailed = not tCurrItem.bMeetsPreq
	end

	return bPrereqFailed
end

function Vendor:FactoryCacheProduce(wndParent, strFormName, strKey)
	local wnd = self.tFactoryCache[strKey]
	if not wnd or not wnd:IsValid() then
		wnd = Apollo.LoadForm(self.xmlDoc, strFormName, wndParent, self)
		self.tFactoryCache[strKey] = wnd
	end

	for idx=1,#self.tFactoryCache do
		if not self.tFactoryCache[idx]:IsValid() then
			self.tFactoryCache[idx] = nil
		end
	end

	return wnd
end

---------------------------------------------------------------------------------------------------
-- VendorHeaderItem Functions
---------------------------------------------------------------------------------------------------

function Vendor:OnHeaderCheck(wndHandler, wndControl, eMouseButton)
	local wndParent = wndControl:GetParent()
	local tHeaderValue = wndParent:GetData()

	self.idOpenedGroup = tHeaderValue.idGroup

	if tHeaderValue.tItems then
		self:DrawListItems(wndParent:FindChild("VendorHeaderContainer"), tHeaderValue.tItems)
	end

	self:SizeHeader(wndParent)

	self.wndItemContainer:ArrangeChildrenVert(0)

	local nTop = ({wndParent:GetAnchorOffsets()})[2]
	self.wndItemContainer:SetVScrollPos(nTop)
end

function Vendor:OnHeaderUncheck(wndHandler, wndControl, eMouseButton)
	local wndParent = wndControl:GetParent()

	self.tDefaultSelectedItem = nil -- Erase the default selection now
	self:DisableBuyButton()
	self:OnGuildChange()

	wndParent:FindChild("VendorHeaderContainer"):DestroyChildren()

	self.idOpenedGroup = nil

	self:SizeHeader(wndParent)

	self.wndItemContainer:ArrangeChildrenVert(0)

	local nTop = ({wndParent:GetAnchorOffsets()})[2]
	self.wndItemContainer:SetVScrollPos(nTop)
end

function Vendor:HelperStringMoneyConvert(nInCopper)
	local strResult = ""
	if nInCopper >= 1000000 then -- 12345678 = 12p 34g 56s 78c
		strResult = String_GetWeaselString(Apollo.GetString("CRB_Platinum"), math.floor(nInCopper/1000000)) .. " "
	end
	if nInCopper >= 10000 then
		strResult = strResult .. String_GetWeaselString(Apollo.GetString("CRB_Gold"), math.floor(nInCopper % 1000000 / 10000)) .. " "
	end
	if nInCopper >= 100 then
		strResult = strResult .. String_GetWeaselString(Apollo.GetString("CRB_Silver"), math.floor(nInCopper % 10000 / 100)) .. " "
	end
	strResult = strResult .. String_GetWeaselString(Apollo.GetString("CRB_Copper"), math.floor(nInCopper % 100))
	return strResult
end

---------------------------------------------------------------------------
-- Vendor instance
---------------------------------------------------------------------------------------------------
local VendorInst = Vendor:new()
VendorInst:Init()
