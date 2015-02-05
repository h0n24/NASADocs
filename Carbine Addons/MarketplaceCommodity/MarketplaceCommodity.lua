-----------------------------------------------------------------------------------------------
-- Client Lua Script for MarketplaceCommodity
-- Copyright (c) NCsoft. All rights reserved
-----------------------------------------------------------------------------------------------

require "Window"
require "GameLib"
require "Money"
require "MarketplaceLib"
require "CommodityOrder"

local MarketplaceCommodity = {}

local knMinLevel = 1
local knMaxLevel = 50 -- TODO: Replace with a variable from code

local kCommodityAuctionRake = MarketplaceLib.kCommodityAuctionRake
local kAuctionSearchMaxResults = MarketplaceLib.kAuctionSearchMaxResults
local kMaxCommodityOrder = MarketplaceLib.kMaxCommodityOrder -- An order can only go up to 200 stock
local kMaxPlayerCommodityOrders = MarketplaceLib.kMaxPlayerCommodityOrders -- You can only have 25 postings active
local kstrAuctionOrderDuration = MarketplaceLib.kCommodityOrderListTimeDays

local karEvalStrings =
{
	[Item.CodeEnumItemQuality.Inferior] 		= Apollo.GetString("CRB_Inferior"),
	[Item.CodeEnumItemQuality.Average] 			= Apollo.GetString("CRB_Average"),
	[Item.CodeEnumItemQuality.Good] 			= Apollo.GetString("CRB_Good"),
	[Item.CodeEnumItemQuality.Excellent] 		= Apollo.GetString("CRB_Excellent"),
	[Item.CodeEnumItemQuality.Superb] 			= Apollo.GetString("CRB_Superb"),
	[Item.CodeEnumItemQuality.Legendary] 		= Apollo.GetString("CRB_Legendary"),
	[Item.CodeEnumItemQuality.Artifact] 		= Apollo.GetString("CRB_Artifact"),
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

function MarketplaceCommodity:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function MarketplaceCommodity:Init()
    Apollo.RegisterAddon(self)
end

function MarketplaceCommodity:OnLoad()
	self.xmlDoc = XmlDoc.CreateFromFile("MarketplaceCommodity.xml")
	self.xmlDoc:RegisterCallback("OnDocumentReady", self)
end

function MarketplaceCommodity:OnDocumentReady()
	if self.xmlDoc == nil then
		return
	end

	Apollo.RegisterEventHandler("ToggleMarketplaceWindow", 							"Initialize", self)
	Apollo.RegisterEventHandler("PostCommodityOrderResult", 						"OnPostCommodityOrderResult", self)
	Apollo.RegisterEventHandler("CommodityAuctionRemoved", 							"OnCommodityAuctionRemoved", self)
	Apollo.RegisterEventHandler("CommodityInfoResults", 							"OnCommodityInfoResults", self)
	Apollo.RegisterEventHandler("OwnedCommodityOrders", 							"OnCommodityDataReceived", self)
	Apollo.RegisterEventHandler("MarketplaceWindowClose", 							"OnDestroy", self)

	Apollo.RegisterTimerHandler("PostResultTimer", 									"OnPostResultTimer", self)
end

function MarketplaceCommodity:OnDestroy()
	if self.wndMain and self.wndMain:IsValid() then
		self:OnSearchClearBtn()
		self.wndMain:Destroy()
		self.wndMain = nil
	end
	Event_CancelCommodities()
end

function MarketplaceCommodity:Initialize()
	if self.wndMain and self.wndMain:IsValid() then
		self.wndMain:Destroy()
	end

	self.wndMain = Apollo.LoadForm(self.xmlDoc, "MarketplaceCommodityForm", nil, self)
	Event_FireGenericEvent("WindowManagementAdd", {wnd = self.wndMain, strName = Apollo.GetString("MarketplaceCommodity_CommoditiesExchange")})

	self.wndOrderLimitText = self.wndMain:FindChild("OpenMarketListingsBtn")

	self.wndMain:SetSizingMinimum(790, 600)
	self.wndMain:SetSizingMaximum(790, 1600)

	self.wndMain:FindChild("FilterOptionsBtn"):AttachWindow(self.wndMain:FindChild("FilterOptionsContainer"))
	self.wndMain:FindChild("FilterOptionsLevelMaxContainer"):FindChild("FilterOptionsLevelUpBtn"):SetData(self.wndMain:FindChild("FilterOptionsLevelMaxContainer"))
	self.wndMain:FindChild("FilterOptionsLevelMaxContainer"):FindChild("FilterOptionsLevelDownBtn"):SetData(self.wndMain:FindChild("FilterOptionsLevelMaxContainer"))
	self.wndMain:FindChild("FilterOptionsLevelMaxContainer"):FindChild("FilterOptionsLevelEditBox"):SetText(knMaxLevel)
	self.wndMain:FindChild("FilterOptionsLevelMaxContainer"):FindChild("FilterOptionsLevelUpBtn"):Enable(false)

	self.wndMain:FindChild("FilterOptionsLevelMinContainer"):FindChild("FilterOptionsLevelUpBtn"):SetData(self.wndMain:FindChild("FilterOptionsLevelMinContainer"))
	self.wndMain:FindChild("FilterOptionsLevelMinContainer"):FindChild("FilterOptionsLevelDownBtn"):SetData(self.wndMain:FindChild("FilterOptionsLevelMinContainer"))
	self.wndMain:FindChild("FilterOptionsLevelMinContainer"):FindChild("FilterOptionsLevelEditBox"):SetText(knMinLevel)
	self.wndMain:FindChild("FilterOptionsLevelMinContainer"):FindChild("FilterOptionsLevelDownBtn"):Enable(false)

	self.wndMain:FindChild("PostResultNotification"):Show(false, true)
	self.wndMain:FindChild("WaitingScreen"):Show(false, true)
	self.wndMain:FindChild("HeaderBuyNowBtn"):SetCheck(true)

	-- Item Filtering (Rarity)
	self.tFilteredRarity =
	{
		[Item.CodeEnumItemQuality.Inferior] 	= true,
		[Item.CodeEnumItemQuality.Average] 		= true,
		[Item.CodeEnumItemQuality.Good] 		= true,
		[Item.CodeEnumItemQuality.Excellent]	= true,
		[Item.CodeEnumItemQuality.Superb] 		= true,
		[Item.CodeEnumItemQuality.Legendary]	= true,
		[Item.CodeEnumItemQuality.Artifact]		= true,
	}

	local tItemQualities = {}
	for strKey, nQuality in pairs(Item.CodeEnumItemQuality) do
		table.insert(tItemQualities, {strKey = strKey, nQuality = nQuality})
	end
	table.sort(tItemQualities, function(a,b) return a.nQuality < b.nQuality end)

	local wndFilterParent = self.wndMain:FindChild("FilterContainer"):FindChild("FilterOptionsRarityList")
	for idx, tQuality in ipairs(tItemQualities) do
		local wndFilter = Apollo.LoadForm(self.xmlDoc, "FilterOptionsRarityItem", wndFilterParent, self)
		wndFilter:FindChild("FilterOptionsRarityItemBtn"):SetCheck(true)
		wndFilter:FindChild("FilterOptionsRarityItemBtn"):SetData(tQuality.nQuality)
		wndFilter:FindChild("FilterOptionsRarityItemBtn"):SetText(karEvalStrings[tQuality.nQuality])
		wndFilter:FindChild("FilterOptionsRarityItemBtn"):SetTooltip(karEvalStrings[tQuality.nQuality])
		wndFilter:FindChild("FilterOptionsRarityItemColor"):SetBGColor(karEvalColors[tQuality.nQuality])
	end
	wndFilterParent:ArrangeChildrenVert(0)

	self:InitializeCategories()
	self:OnResizeCategories()
	self:OnHeaderBtnToggle()
	MarketplaceLib.RequestOwnedCommodityOrders()

	Sound.Play(Sound.PlayUIWindowCommoditiesExchangeOpen)
end

function MarketplaceCommodity:InitializeCategories()
	-- GOTCHA: Code uses three category levels. UI uses two levels artificially. "TopItem" UI will use data from MidCategory.
	local tFlattenedList = {}
	for idx, tTopCategory in ipairs(MarketplaceLib.GetCommodityFamilies()) do
		for idx2, tMidCategory in ipairs(MarketplaceLib.GetCommodityCategories(tTopCategory.nId)) do
			table.insert(tFlattenedList, { tTopCategory = tTopCategory, tMidCategory = tMidCategory })
		end
	end
	table.sort(tFlattenedList, function(a,b) return a.tMidCategory.strName < b.tMidCategory.strName end)

	for idx, tData in pairs(tFlattenedList) do
		local tTopCategory = tData.tTopCategory
		local tMidCategory = tData.tMidCategory
		local wndTop = self:LoadByName("CategoryTopItem", self.wndMain:FindChild("MainCategoryContainer"), tMidCategory.strName)
		wndTop:FindChild("CategoryTopBtn"):SetText(tMidCategory.strName)
		wndTop:FindChild("CategoryTopBtn"):SetData(wndTop)

		-- Add an "All" button
		local wndAllBtn = Apollo.LoadForm(self.xmlDoc, "CategoryMidItem", wndTop:FindChild("CategoryTopList"), self)
		wndAllBtn:FindChild("CategoryMidBtn"):SetData({ nTopCategory = tTopCategory.nId, nMidCategory = tMidCategory.nId, nBotCategory = 0 })
		wndAllBtn:FindChild("CategoryMidBtn"):SetText(Apollo.GetString("CRB_All"))
		wndAllBtn:SetName("CategoryMidItem_All")

		-- Add the rest of the middle buttons
		for idx3, tBotCategory in pairs(MarketplaceLib.GetCommodityTypes(tMidCategory.nId)) do
			local wndMid = Apollo.LoadForm(self.xmlDoc, "CategoryMidItem", wndTop:FindChild("CategoryTopList"), self)
			wndMid:FindChild("CategoryMidBtn"):SetData({ nTopCategory = tTopCategory.nId, nMidCategory = tMidCategory.nId, nBotCategory = tBotCategory.nId })
			wndMid:FindChild("CategoryMidBtn"):SetText(tBotCategory.strName)
		end
	end

	self.wndMain:FindChild("MainCategoryContainer"):SetData({ nTopCategory = 0, nMidCategory = 0, nBotCategory = 0 })
end

function MarketplaceCommodity:OnResizeCategories() -- Can come from XML
	for idx, wndTop in pairs(self.wndMain:FindChild("MainCategoryContainer"):GetChildren()) do
		local nListHeight = wndTop:FindChild("CategoryTopBtn"):IsChecked() and (wndTop:FindChild("CategoryTopList"):ArrangeChildrenVert(0) + 12) or 0
		local nLeft, nTop, nRight, nBottom = wndTop:GetAnchorOffsets()
		wndTop:SetAnchorOffsets(nLeft, nTop, nRight, nTop + nListHeight + 44)
	end
	self.wndMain:FindChild("MainCategoryContainer"):RecalculateContentExtents()
	self.wndMain:FindChild("MainCategoryContainer"):ArrangeChildrenVert(0)
end

-----------------------------------------------------------------------------------------------
-- Main Set Up
-----------------------------------------------------------------------------------------------

function MarketplaceCommodity:OnHeaderBtnToggle()
	-- Filters
	local wndFilter = self.wndMain:FindChild("FilterContainer")
	local bFilterActive = wndFilter:FindChild("FilterClearBtn"):GetData() or false
	wndFilter:FindChild("FilterOptionsContainer"):Show(false)
	wndFilter:FindChild("FilterClearBtn"):Show(bFilterActive) -- GOTCHA: Visibility update is delayed until a manual reset

	-- Main Build
	self.wndMain:FindChild("MainScrollContainer"):DestroyChildren() -- TODO refactor
	if self.wndMain:FindChild("HeaderSellNowBtn"):IsChecked() or self.wndMain:FindChild("HeaderSellOrderBtn"):IsChecked() then
		self:InitializeSell()
	elseif self.wndMain:FindChild("HeaderBuyNowBtn"):IsChecked() or self.wndMain:FindChild("HeaderBuyOrderBtn"):IsChecked() then
		self:InitializeBuy()
	end

	-- Empty message (if applicable)
	local strMessage = ""
	local bNoResults = #self.wndMain:FindChild("MainScrollContainer"):GetChildren() == 0
	if bNoResults and string.len(self.wndMain:FindChild("SearchEditBox"):GetText()) > 0 then
		strMessage = Apollo.GetString("MarketplaceCommodity_NoResults")
	elseif bNoResults then -- If it's a buy tab, and they haven't clicked a category, do a custom message
		local bAnyCategoryChecked = false
		if self.wndMain:FindChild("HeaderSellNowBtn"):IsChecked() or self.wndMain:FindChild("HeaderSellOrderBtn"):IsChecked() then
			bAnyCategoryChecked = true
		else
			for idx, wndCurr in pairs(self.wndMain:FindChild("MainCategoryContainer"):GetChildren()) do
				if wndCurr:FindChild("CategoryTopBtn") and wndCurr:FindChild("CategoryTopBtn"):IsChecked() then
					bAnyCategoryChecked = true
					break
				end
			end
		end
		strMessage = bAnyCategoryChecked and Apollo.GetString("MarketplaceCommodity_NoResults") or Apollo.GetString("MarketplaceCommodity_PickACategory")
	end
	self.wndMain:FindChild("MainScrollContainer"):SetText(strMessage)
	self.wndMain:FindChild("MainScrollContainer"):ArrangeChildrenVert(0)
	self.wndMain:FindChild("MainScrollContainer"):SetVScrollPos(0)
	self:OnResizeCategories()
end

function MarketplaceCommodity:InitializeSell()
	local tBothItemTables = {}
	local tAllCategoryNames = {}
	local unitPlayer = GameLib.GetPlayerUnit()

	-- Helper method
	local tCategoryFilterDataIds = self.wndMain:FindChild("MainCategoryContainer"):GetData() or { nTopCategory = 0, nMidCategory = 0, nBotCategory = 0 }
	local function HelperValidateCategory(tCategoryFilterDataIds, itemCurr)
		if tCategoryFilterDataIds.nBotCategory ~= 0 then
			return tCategoryFilterDataIds.nBotCategory == itemCurr:GetItemType()
		elseif tCategoryFilterDataIds.nMidCategory ~= 0 or tCategoryFilterDataIds.nTopCategory ~= 0 then -- Mid and top get merged
			return tCategoryFilterDataIds.nMidCategory == itemCurr:GetItemFamily() or tCategoryFilterDataIds.nMidCategory == itemCurr:GetItemCategory()
		else
			return true -- No filter set
		end
	end

	-- Build Table
	for key, tCurrData in pairs(unitPlayer:GetInventoryItems()) do
		if HelperValidateCategory(tCategoryFilterDataIds, tCurrData.itemInBag) then
			table.insert(tBothItemTables, { tCurrItem = tCurrData.itemInBag, strName = tCurrData.itemInBag:GetName() })
		end
		
		if not tCurrData.itemInBag:IsSoulbound() then
			tAllCategoryNames[tCurrData.itemInBag:GetItemCategoryName()] = true
		end
	end
	for key, tSatchelItemCategory in pairs(unitPlayer:GetSupplySatchelItems(1)) do
		for key2, tCurrData in pairs(tSatchelItemCategory) do
			if HelperValidateCategory(tCategoryFilterDataIds, tCurrData.itemMaterial) then
				table.insert(tBothItemTables, { tCurrItem = tCurrData.itemMaterial, strName = tCurrData.itemMaterial:GetName() })
			end
			tAllCategoryNames[tCurrData.itemMaterial:GetItemCategoryName()] = true
		end
	end
	table.sort(tBothItemTables, function(a,b) return a.strName < b.strName end)

	-- Show only the relevant categories
	self.wndMain:FindChild("FilterContainer"):Show(false)
	for idx, wndCurr in pairs(self.wndMain:FindChild("MainCategoryContainer"):GetChildren()) do
		wndCurr:Show(tAllCategoryNames[wndCurr:GetName()]) -- Compare name against window name
	end

	-- Now build the window and do another layer of filtering
	local strSearchFilter = Apollo.StringToLower(self.wndMain:FindChild("SearchEditBox"):GetText() or "")
	local bSkipSearchFilter = string.len(strSearchFilter) == 0
	
	for key, tCurrData in pairs(tBothItemTables) do
		local tCurrItem = tCurrData.tCurrItem
		if tCurrItem and tCurrItem:IsCommodity() and (bSkipSearchFilter or string.find(Apollo.StringToLower(tCurrData.strName), strSearchFilter)) then
			local bSellNow = self.wndMain:FindChild("HeaderSellNowBtn"):IsChecked()
			local strWindow = bSellNow and "SimpleListItem" or "AdvancedListItem"
			local strButtonText = bSellNow and Apollo.GetString("MarketplaceCommodity_SellNow") or Apollo.GetString("MarketplaceCommodity_CreateSellOrder")
			self:BuildListItem(tCurrItem, strWindow, strButtonText)

			MarketplaceLib.RequestCommodityInfo(tCurrItem:GetItemId()) -- Leads to OnCommodityInfoResults
		end
	end
end

function MarketplaceCommodity:InitializeBuy()
	-- Category showing / hiding
	local bAnyCategoryChecked = false
	self.wndMain:FindChild("FilterContainer"):Show(true)
	for idx, wndCurr in pairs(self.wndMain:FindChild("MainCategoryContainer"):GetChildren()) do
		wndCurr:Show(true) -- Sell may hide the irrelevant categories
		if not bAnyCategoryChecked and wndCurr:FindChild("CategoryTopBtn") and wndCurr:FindChild("CategoryTopBtn"):IsChecked() then
			bAnyCategoryChecked = true
		end
	end

	-- Early exit if no search or category (completely blank UI)
	local strSearchFilter = self.wndMain:FindChild("SearchEditBox"):GetText()
	if not bAnyCategoryChecked and string.len(strSearchFilter) == 0 then
		return
	end

	local bBuyNow = self.wndMain:FindChild("HeaderBuyNowBtn"):IsChecked()
	local strWindow = bBuyNow and "SimpleListItem" or "AdvancedListItem"
	local strBtnText = bBuyNow and Apollo.GetString("MarketplaceCommodity_BuyNow") or Apollo.GetString("MarketplaceCommodity_CreateBuyOrder")

	-- Level Filtering
	local wndFilter = self.wndMain:FindChild("FilterContainer")
	local nLevelMin = tonumber(wndFilter:FindChild("FilterOptionsLevelMinContainer"):FindChild("FilterOptionsLevelEditBox"):GetText()) or knMinLevel
	local nLevelMax = tonumber(wndFilter:FindChild("FilterOptionsLevelMaxContainer"):FindChild("FilterOptionsLevelEditBox"):GetText()) or knMaxLevel
	if nLevelMin == knMinLevel then
		wndFilter:FindChild("FilterOptionsLevelMinContainer"):FindChild("FilterOptionsLevelDownBtn"):Enable(false)
		wndFilter:FindChild("FilterOptionsLevelMinContainer"):FindChild("FilterOptionsLevelEditBox"):SetText(nLevelMin)
	end
	if nLevelMax == knMaxLevel then
		wndFilter:FindChild("FilterOptionsLevelMaxContainer"):FindChild("FilterOptionsLevelUpBtn"):Enable(false)
		wndFilter:FindChild("FilterOptionsLevelMaxContainer"):FindChild("FilterOptionsLevelEditBox"):SetText(nLevelMax)
	end

	local bExtraFilter = nLevelMin ~= knMinLevel or nLevelMax ~= knMaxLevel
	for nItemQuality, bAllowed in pairs(self.tFilteredRarity) do
		if not bAllowed then
			bExtraFilter = true
			break
		end
	end

	local fnFilter = nil
	if bExtraFilter then
		fnFilter = function (tFilterItem)
			local nItemPowerLevel = tFilterItem:GetPowerLevel()
			return self.tFilteredRarity[tFilterItem:GetItemQuality()] and nItemPowerLevel >= nLevelMin and nItemPowerLevel <= nLevelMax
		end
	end

	local tCategoryFilter = self.wndMain:FindChild("MainCategoryContainer"):GetData() or { nTopCategory = 0, nMidCategory = 0, nBotCategory = 0 }
	local tSearchResults, bHitMax = MarketplaceLib.SearchCommodityItems(strSearchFilter, tCategoryFilter.nTopCategory, tCategoryFilter.nMidCategory, tCategoryFilter.nBotCategory, fnFilter)

	-- Draw results then request info for each result
	for idx, tCurrData in pairs(tSearchResults) do
		self:BuildListItem(Item.GetDataFromId(tCurrData.nId), strWindow, strBtnText)
		MarketplaceLib.RequestCommodityInfo(tCurrData.nId) -- Leads to OnCommodityInfoResults
		-- TODO: Count the number of request and load spinner until they all come back
	end

	-- If too many results, show a message
	if bHitMax then
		local wndSearchFail = self:LoadByName("TooManySearchResultsText", self.wndMain:FindChild("MainScrollContainer"), "TooManySearchResultsText")
		local strFilterOrNot = ""
		if wndFilter:FindChild("FilterClearBtn"):GetData() then
			strFilterOrNot = "MarketplaceCommodity_TooManyResultsFilter"
		else
			strFilterOrNot = "MarketplaceCommodity_TooManyResults"
		end
		wndSearchFail:SetText(String_GetWeaselString(Apollo.GetString(strFilterOrNot), tonumber(kAuctionSearchMaxResults)))
	end
end

function MarketplaceCommodity:OnSearchEditBoxChanged(wndHandler, wndControl) -- SearchEditBox
	self.wndMain:FindChild("SearchClearBtn"):Show(string.len(wndHandler:GetText() or "") > 0)
end

function MarketplaceCommodity:OnSearchClearBtn(wndHandler, wndControl)
	self.wndMain:FindChild("SearchEditBox"):SetText("")
	self.wndMain:FindChild("SearchClearBtn"):Show(false)
	self:OnSearchCommitBtn()
end

function MarketplaceCommodity:OnSearchCommitBtn(wndHandler, wndControl) -- ALso SearchEditBox's WindowKeyReturn
	self.wndMain:FindChild("SearchClearBtn"):SetFocus()
	self.wndMain:FindChild("RefreshAnimation"):SetSprite("CRB_WindowAnimationSprites:sprWinAnim_BirthSmallTemp")
	self:OnHeaderBtnToggle()
end

function MarketplaceCommodity:OnRefreshBtn(wndHandler, wndControl) -- Also from lua and multiple XML buttons
	self.wndMain:FindChild("RefreshAnimation"):SetSprite("CRB_WindowAnimationSprites:sprWinAnim_BirthSmallTemp")
	self:OnHeaderBtnToggle()
end

-----------------------------------------------------------------------------------------------
-- Main Draw
-----------------------------------------------------------------------------------------------

function MarketplaceCommodity:BuildListItem(tCurrItem, strWindowName, strBtnText)
	local nItemId = tCurrItem:GetItemId()
	local bSellNowOrSellOrder = self.wndMain:FindChild("HeaderSellNowBtn"):IsChecked() or self.wndMain:FindChild("HeaderSellOrderBtn"):IsChecked()
	local nIconBackpackCount = bSellNowOrSellOrder and tCurrItem:GetBackpackCount() or ""
	local wndCurr = self:LoadByName(strWindowName, self.wndMain:FindChild("MainScrollContainer"), nItemId)
	wndCurr:FindChild("ListInputPrice"):SetData(wndCurr)
	wndCurr:FindChild("ListSubmitBtn"):SetData({tCurrItem, wndCurr})
	wndCurr:FindChild("ListSubmitBtn"):Enable(false)
	wndCurr:FindChild("ListSubmitBtn"):SetText(strBtnText)
	wndCurr:FindChild("ListName"):SetText(tCurrItem:GetName())
	wndCurr:FindChild("ListIcon"):SetData(tCurrItem)
	wndCurr:FindChild("ListIcon"):SetSprite(tCurrItem:GetIcon())
	wndCurr:FindChild("ListCount"):SetData(nIconBackpackCount)
	wndCurr:FindChild("ListCount"):SetText(nIconBackpackCount)
	wndCurr:FindChild("ListInputNumberUpBtn"):SetData(wndCurr)
	wndCurr:FindChild("ListInputNumberDownBtn"):SetData(wndCurr)
	wndCurr:FindChild("ListInputNumberUpBtn"):Enable(nIconBackpackCount ~= 1)
	wndCurr:FindChild("ListInputNumberDownBtn"):Enable(false)
	wndCurr:FindChild("ListInputNumber"):SetData(wndCurr)
	wndCurr:Show(false) -- Invisible until OnCommodityInfoResults fills in the remaining data (so it doesn't flash if invalid)
end

function MarketplaceCommodity:OnListInputNumberChanged(wndHandler, wndControl, strText)
	local wndParent = wndHandler:GetData()
	local nCount = tonumber(strText)
	if nCount then
		if nCount > MarketplaceLib.kMaxCommodityOrder then
			wndParent:FindChild("ListInputNumber"):SetText(MarketplaceLib.kMaxCommodityOrder)
		elseif nCount < 1 then
			wndParent:FindChild("ListInputNumber"):SetText(1)
		end
	else
		nCount = 1
		wndParent:FindChild("ListInputNumber"):SetText(1)
	end
	self:OnListInputNumberHelper(wndParent, nCount)
end

function MarketplaceCommodity:OnListInputNumberUpBtn(wndHandler, wndControl)
	local wndParent = wndHandler:GetData()
	local nNewValue = math.min(MarketplaceLib.kMaxCommodityOrder, tonumber(wndParent:FindChild("ListInputNumber"):GetText() + 1) or 1)
	wndParent:FindChild("ListInputNumber"):SetText(nNewValue)
	self:OnListInputNumberHelper(wndParent, nNewValue)

	wndHandler:SetFocus()
end

function MarketplaceCommodity:OnListInputNumberDownBtn(wndHandler, wndControl)
	local wndParent = wndHandler:GetData()
	local nNewValue = math.max(1, tonumber(wndParent:FindChild("ListInputNumber"):GetText() - 1) or 1)
	wndParent:FindChild("ListInputNumber"):SetText(nNewValue)
	self:OnListInputNumberHelper(wndParent, nNewValue)

	wndHandler:SetFocus()
end

function MarketplaceCommodity:OnListInputNumberHelper(wndParent, nNewValue)
	local nMax = MarketplaceLib.kMaxCommodityOrder
	if self.wndMain:FindChild("HeaderSellNowBtn"):IsChecked() or self.wndMain:FindChild("HeaderSellOrderBtn"):IsChecked() then
		nMax = math.min(nMax, tonumber(wndParent:FindChild("ListCount"):GetData()))
	end

	wndParent:FindChild("ListInputNumberUpBtn"):Enable(nNewValue < nMax)
	wndParent:FindChild("ListInputNumberDownBtn"):Enable(nNewValue > 1)
	self:HelperValidateListInputForSubmit(wndParent)
end

function MarketplaceCommodity:OnListInputPriceAmountChanged(wndHandler, wndControl) -- ListInputPrice, data is parent
	local nNumDisplay = math.max(0, tonumber(wndHandler:GetAmount() or 0))
	wndHandler:SetText(nNumDisplay)

	-- Allow order posting
	local wndParent = wndHandler:GetData()
	self:HelperValidateListInputForSubmit(wndParent)
end

function MarketplaceCommodity:OnListInputPriceMouseDown(wndHandler, wndControl)
	wndHandler:SetStyleEx("SkipZeroes", false)
	self:HelperValidateListInputForSubmit(wndHandler:GetData())
end

function MarketplaceCommodity:OnListInputPriceLoseFocus(wndHandler, wndControl)
	wndHandler:SetStyleEx("SkipZeroes", true)
	self:HelperValidateListInputForSubmit(wndHandler:GetData())
end

function MarketplaceCommodity:HelperValidateListInputForSubmit(wndParent)
	local nAvailable = 0
	local nQuantity = 0
	local nPrice = 0

	local wndCount = wndParent:FindChild("ListCount")
	if wndCount then
		-- If tonumber() fails then this is the Create Buy Order tab
		--    and we want to be able to perform the action so assume '1'.
		nAvailable = tonumber(wndCount:GetData()) or 1
	end

	local wndListInputPrice = wndParent:FindChild("ListInputPrice")
	if wndListInputPrice and wndParent:FindChild("ListInputNumber") and wndParent:FindChild("ListInputNumber"):IsValid() then
		nPrice = math.max(0, tonumber(wndListInputPrice:GetAmount() or 0)) * tonumber(wndParent:FindChild("ListInputNumber"):GetText())
		nPrice = nPrice + math.max(nPrice * MarketplaceLib.kfCommodityBuyOrderTaxMultiplier, MarketplaceLib.knCommodityBuyOrderTaxMinimum)
	end

	local bCanAfford = true
	if self.wndMain:FindChild("HeaderBuyNowBtn"):IsChecked() or self.wndMain:FindChild("HeaderBuyOrderBtn"):IsChecked() then
		bCanAfford = GameLib.GetPlayerCurrency():GetAmount() > nPrice
	end

	if wndListInputPrice then
		wndListInputPrice:SetTextColor(bCanAfford and "white" or "xkcdReddish")
	end

	local wndQuantity = wndParent:FindChild("ListInputNumber")
	if wndQuantity then
		local strListInputNumber = tonumber(wndQuantity:GetText() or "")
		if strListInputNumber then
			nQuantity = strListInputNumber
		end
	end

	local wndListSubmitBtn = wndParent:FindChild("ListSubmitBtn")
	if wndListSubmitBtn then
		local bEnable = nPrice > 0 and nQuantity > 0 and nQuantity <= kMaxCommodityOrder and nAvailable > 0 and bCanAfford
		wndListSubmitBtn:Enable(bEnable)
		if bEnable then
			local tCurrItem = wndListSubmitBtn:GetData()[1]
			local wndParent = wndListSubmitBtn:GetData()[2]
			local monPricePerUnit = wndParent:FindChild("ListInputPrice"):GetCurrency() -- not an integer
			local nOrderCount = tonumber(wndParent:FindChild("ListInputNumber"):GetText())
			local bBuyTab = self.wndMain:FindChild("HeaderBuyNowBtn"):IsChecked() or self.wndMain:FindChild("HeaderBuyOrderBtn"):IsChecked()

			if wndParent:FindChild("ListLowerThanVendor") then
				local nItemPrice = 0
			
				if tCurrItem:GetSellPrice() ~= nil then
					nItemPrice = tCurrItem:GetSellPrice():GetAmount()
				end
			
				local nVendorPriceAfterFees = nItemPrice * (1 + (kCommodityAuctionRake / 100))
				wndParent:FindChild("ListLowerThanVendor"):Show(monPricePerUnit:GetAmount() > 0 and nVendorPriceAfterFees > monPricePerUnit:GetAmount())
			end

			local orderNew = bBuyTab and CommodityOrder.newBuyOrder(tCurrItem:GetItemId()) or CommodityOrder.newSellOrder(tCurrItem:GetItemId())
			if nOrderCount and monPricePerUnit:GetAmount() > 0 then
				orderNew:SetCount(nOrderCount)
				orderNew:SetPrices(monPricePerUnit)
				orderNew:SetForceImmediate(self.wndMain:FindChild("HeaderBuyNowBtn"):IsChecked() or self.wndMain:FindChild("HeaderSellNowBtn"):IsChecked())
			end

			if not bCanAfford or not nOrderCount or not monPricePerUnit or monPricePerUnit:GetAmount() < 1 or not orderNew:CanPost() then
				wndListSubmitBtn:Enable(false)
			else
				wndListSubmitBtn:SetActionData(GameLib.CodeEnumConfirmButtonType.MarketplaceCommoditiesSubmit, orderNew)
			end
		end
	end
end

-----------------------------------------------------------------------------------------------
-- Filtering
-----------------------------------------------------------------------------------------------

function MarketplaceCommodity:OnFilterOptionsLevelUpBtn(wndHandler, wndControl)
	local wndEditBox = wndHandler:GetParent():FindChild("FilterOptionsLevelEditBox")
	local nOldValue = tonumber(wndEditBox:GetText())
	local nNewValue = nOldValue and nOldValue + 1
	wndEditBox:SetText(nNewValue)
	self:HelperCheckValidLevelValues(wndEditBox)
	self.wndMain:FindChild("FilterContainer:FilterClearBtn"):SetData(true)
end

function MarketplaceCommodity:OnFilterOptionsLevelDownBtn(wndHandler, wndControl)
	local wndEditBox = wndHandler:GetParent():FindChild("FilterOptionsLevelEditBox")
	local nOldValue = tonumber(wndEditBox:GetText())
	local nNewValue = nOldValue and nOldValue - 1
	wndEditBox:SetText(nNewValue)
	self:HelperCheckValidLevelValues(wndEditBox)
	self.wndMain:FindChild("FilterContainer:FilterClearBtn"):SetData(true)
end

function MarketplaceCommodity:OnFilterEditBoxChanged(wndHandler, wndControl)
	local wndEditBox = wndHandler:GetParent():FindChild("FilterOptionsLevelEditBox")
	self:HelperCheckValidLevelValues(wndEditBox)
	self.wndMain:FindChild("FilterContainer:FilterClearBtn"):SetData(true) -- GOTCHA: It will flag as dirty bit when the Refresh event gets called
end

function MarketplaceCommodity:OnFilterOptionsRarityItemToggle(wndHandler, wndControl) -- FilterOptionsRarityItemBtn
	self.tFilteredRarity[wndHandler:GetData()] = wndHandler:IsChecked()
	wndHandler:FindChild("FilterOptionsRarityItemCheck"):SetSprite(wndHandler:IsChecked() and "sprCharC_NameCheckYes" or "sprRaid_RedXClose_Centered")
	self.wndMain:FindChild("FilterContainer"):FindChild("FilterClearBtn"):SetData(true)
end

function MarketplaceCommodity:OnResetFilterBtn(wndHandler, wndControl)
	local wndFilter = self.wndMain:FindChild("FilterContainer")
	for idx, wndCurr in pairs(wndFilter:FindChild("FilterOptionsRarityList"):GetChildren()) do
		local wndCurrBtn = wndCurr:FindChild("FilterOptionsRarityItemBtn")
		if wndCurrBtn then
			self.tFilteredRarity[wndCurrBtn:GetData()] = true
			wndCurrBtn:SetCheck(true)
			wndCurrBtn:FindChild("FilterOptionsRarityItemCheck"):SetSprite("sprCharC_NameCheckYes")
		end
	end

	wndFilter:FindChild("FilterClearBtn"):SetData(false)
	wndFilter:FindChild("FilterOptionsLevelMinContainer"):FindChild("FilterOptionsLevelEditBox"):SetText(knMinLevel)
	wndFilter:FindChild("FilterOptionsLevelMaxContainer"):FindChild("FilterOptionsLevelEditBox"):SetText(knMaxLevel)
	self:OnRefreshBtn()
end

function MarketplaceCommodity:OnFilterOptionsWindowClosed(wndHandler, wndControl)
	if wndHandler == wndControl and self.wndMain and self.wndMain:IsValid() and self.wndMain:FindChild("FilterClearBtn"):GetData() then
		self:OnRefreshBtn()
	end
end

function MarketplaceCommodity:HelperCheckValidLevelValues(wndChanged)
	local wndFilterOptions = self.wndMain:FindChild("FilterContainer:FilterOptionsContainer")
	local wndMinLevelFilter = wndFilterOptions:FindChild("FilterOptionsLevelMinContainer:FilterOptionsLevelEditBox")
	local wndMaxLevelFilter = wndFilterOptions:FindChild("FilterOptionsLevelMaxContainer:FilterOptionsLevelEditBox")
	local nMinLevelValue = tonumber(wndMinLevelFilter:GetText()) or knMinLevel
	local nMaxLevelValue = tonumber(wndMaxLevelFilter:GetText()) or knMaxLevel
	local bMinChanged = false
	local bMaxChanged = false

	if wndChanged == wndMinLevelFilter then
		if nMinLevelValue < knMinLevel then
			nMinLevelValue = knMinLevel
			bMinChanged = true
		elseif nMinLevelValue > knMaxLevel then
			nMinLevelValue = knMaxLevel
			bMinChanged = true
		end

		if nMinLevelValue > nMaxLevelValue then
			nMinLevelValue = nMaxLevelValue
			bMinChanged = true
		end
	end

	if wndChanged == wndMaxLevelFilter then
		if nMaxLevelValue < knMinLevel then
			nMaxLevelValue = knMinLevel
			bMaxChanged = true
		elseif nMaxLevelValue > knMaxLevel then
			nMaxLevelValue = knMaxLevel
			bMaxChanged = true
		end

		if nMinLevelValue > nMaxLevelValue and nMinLevelValue > 10 and nMaxLevelValue > 10 then
			nMaxLevelValue = nMinLevelValue
			bMaxChanged = true
		end
	end

	-- In case the Max value is single digit and Min value isn't
	if nMaxLevelValue < nMinLevelValue then
		wndFilterOptions:FindChild("FilterOptionsRefreshBtn"):Enable(false)
	else
		wndFilterOptions:FindChild("FilterOptionsRefreshBtn"):Enable(true)
	end


	if bMinChanged then
		wndMinLevelFilter:SetText(nMinLevelValue)
	end
	if bMaxChanged then
		wndMaxLevelFilter:SetText(nMaxLevelValue)
	end

	wndFilterOptions:FindChild("FilterOptionsLevelMinContainer:FilterOptionsLevelUpBtn"):Enable(nMinLevelValue < knMaxLevel and nMinLevelValue < nMaxLevelValue)
	wndFilterOptions:FindChild("FilterOptionsLevelMinContainer:FilterOptionsLevelDownBtn"):Enable(nMinLevelValue > knMinLevel)
	wndFilterOptions:FindChild("FilterOptionsLevelMaxContainer:FilterOptionsLevelUpBtn"):Enable(nMaxLevelValue < knMaxLevel)
	wndFilterOptions:FindChild("FilterOptionsLevelMaxContainer:FilterOptionsLevelDownBtn"):Enable(nMaxLevelValue > knMinLevel and nMaxLevelValue > nMinLevelValue)
end

-----------------------------------------------------------------------------------------------
-- Category Btns
-----------------------------------------------------------------------------------------------

function MarketplaceCommodity:OnCategoryTopBtnToggle(wndHandler, wndControl)
	local wndParent = wndHandler:GetData()
	self.wndMain:SetGlobalRadioSel("MarketplaceCommodity_CategoryMidBtn_GlobalRadioGroup", -1)

	local tSearchData = { nTopCategory = 0, nMidCategory = 0, nBotCategory = 0 }
	if wndHandler:IsChecked() then
		local wndAllBtn = wndParent:FindChild("CategoryTopList") and wndParent:FindChild("CategoryTopList"):FindChild("CategoryMidItem_All") or nil
		if wndAllBtn then
			wndAllBtn:FindChild("CategoryMidBtn"):SetCheck(true)
			tSearchData = wndAllBtn:FindChild("CategoryMidBtn"):GetData()
		end
	end

	self.wndMain:FindChild("MainCategoryContainer"):SetData(tSearchData)
	self:OnRefreshBtn()
	self:OnResizeCategories()
end

function MarketplaceCommodity:OnCategoryMidBtnCheck(wndHandler, wndControl)
	self.wndMain:FindChild("MainCategoryContainer"):SetData(wndHandler:GetData()) -- { nTopCategory, nMidCategory, nBotCategory }
	self:OnRefreshBtn()
end

-----------------------------------------------------------------------------------------------
-- Custom Tooltips
-----------------------------------------------------------------------------------------------

function MarketplaceCommodity:OnGenerateSimpleConfirmTooltip(wndHandler, wndControl, eType, nX, nY) -- wndHandler is ListSubmitBtn, data is { tCurrItem and window "SimpleListItem" }
	local tCurrItem = wndHandler:GetData()[1]
	local wndParent = wndHandler:GetData()[2]
	local monPricePerUnit = wndParent:FindChild("ListInputPrice"):GetCurrency() -- not an integer
	local nOrderCount = tonumber(wndParent:FindChild("ListInputNumber"):GetText()) or -1
	if nOrderCount == -1 then
		return
	end

	-- TODO TEMP: This may be deleted soon
	-- TODO: This doesn't update as it's a tooltipform. But this is temp and may be deleted soon.
	local bBuyNow = self.wndMain:FindChild("HeaderBuyNowBtn"):IsChecked()
	local wndTooltip = wndHandler:LoadTooltipForm("MarketplaceCommodity.xml", "SimpleConfirmTooltip", self)
	wndTooltip:FindChild("SimpleConfirmTooltipPrice"):SetAmount(nOrderCount * monPricePerUnit:GetAmount())
	wndTooltip:FindChild("SimpleConfirmTooltipText"):SetText(String_GetWeaselString(Apollo.GetString("MarketplaceCommodity_MultiItem"), nOrderCount, tCurrItem:GetName()))
	wndTooltip:FindChild("SimpleConfirmTooltipTitle"):SetText(Apollo.GetString(bBuyNow and "MarketplaceCommodity_ClickToBuyNow" or "MarketplaceCommodity_ClickToSellNow"))
	-- TODO: Resize to fit text width
end

function MarketplaceCommodity:OnGenerateAdvancedConfirmTooltip(wndHandler, wndControl, eType, nX, nY)
	-- wndHandler is ListSubmitBtn, data is { tCurrItem and window "SimpleListItem" }
	local tCurrItem = wndHandler:GetData()[1]
	local wndParent = wndHandler:GetData()[2]
	local monPricePerUnit = wndParent:FindChild("ListInputPrice"):GetCurrency() -- not an integer
	local nOrderCount = tonumber(wndParent:FindChild("ListInputNumber"):GetText()) or -1
	if nOrderCount == -1 then
		return
	end

	local bBuyOrder = self.wndMain:FindChild("HeaderBuyOrderBtn"):IsChecked()
	local nSellCutMultipler = bBuyOrder and 1 or (1 - (kCommodityAuctionRake / 100))
	local strSellTextCut = bBuyOrder and "" or String_GetWeaselString(Apollo.GetString("MarketplaceCommodity_AuctionhouseTax"), (kCommodityAuctionRake * -1))
	local strTitle = bBuyOrder and Apollo.GetString("MarketplaceCommodity_ClickToBuyOrder") or Apollo.GetString("MarketplaceCommodity_ClickToSellOrder")
	local strMainBox = String_GetWeaselString(Apollo.GetString("MarketplaceCommodity_MultiItem"), nOrderCount, tCurrItem:GetName())
	local strDuration = String_GetWeaselString(Apollo.GetString("MarketplaceCommodity_DurationDays"), tostring(kstrAuctionOrderDuration))

	local wndTooltip = wndHandler:LoadTooltipForm("MarketplaceCommodity.xml", "AdvancedConfirmTooltip", self)
	wndTooltip:FindChild("AdvancedConfirmSellFeeContainer"):Show(not bBuyOrder)
	wndTooltip:FindChild("SimpleConfirmTooltipText"):SetText(strMainBox)
	wndTooltip:FindChild("SimpleConfirmTooltipTitle"):SetText(strTitle)
	wndTooltip:FindChild("AdvancedConfirmDurationText"):SetText(strDuration)
	wndTooltip:FindChild("AdvancedConfirmSellFeeText"):SetText(String_GetWeaselString(Apollo.GetString("Market_ListingFeePercent"), (kCommodityAuctionRake * -1)))
	wndTooltip:FindChild("SimpleConfirmTooltipPrice"):SetAmount(nOrderCount * monPricePerUnit:GetAmount() * nSellCutMultipler)
	-- TODO: Resize to fit text width
end

function MarketplaceCommodity:OnGenerateTooltipFullStats(wndHandler, wndControl, eType, nX, nY) -- GOTCHA: wndHandler is ListSubtitle
	local tStats = wndHandler:GetData()
	if not tStats then
		return
	end

	local nLastCount = 0
	local wndFullStats = wndHandler:LoadTooltipForm("MarketplaceCommodity.xml", "FullStatsFrame", self)
	for nRowIdx = 1, 3 do
		local strBuy = ""
		local nBuyPrice = tStats.arBuyOrderPrices[nRowIdx].monPrice:GetAmount()
		if nBuyPrice > 0 then
			strBuy = self.wndMain:FindChild("HiddenCashWindow"):GetAMLDocForAmount(nBuyPrice, true, "ff2f94ac", "CRB_InterfaceSmall", 0) -- 2nd is skip zeroes, 5th is align left
		else
			strBuy = "<P Font=\"CRB_InterfaceSmall\" TextColor=\"ff2f94ac\">" .. Apollo.GetString("CRB_NoData") .. "</P>"
		end

		local strSell = ""
		local nSellPrice = tStats.arSellOrderPrices[nRowIdx].monPrice:GetAmount()
		if nSellPrice > 0 then
			strSell = self.wndMain:FindChild("HiddenCashWindow"):GetAMLDocForAmount(nSellPrice, true, "ff2f94ac", "CRB_InterfaceSmall", 0) -- 2nd is skip zeroes, 5th is align left
		else
			strSell = "<P Font=\"CRB_InterfaceSmall\" TextColor=\"ff2f94ac\">" .. Apollo.GetString("CRB_NoData") .. "</P>"
		end

		local wndRow = wndFullStats:FindChild("FullStatsGrid"):AddRow("")
		local strCount = String_GetWeaselString(Apollo.GetString("MarketplaceCommodity_Top"), tStats.arBuyOrderPrices[nRowIdx].nCount)
		wndFullStats:FindChild("FullStatsGrid"):SetCellDoc(wndRow, 1, "<P Font=\"CRB_InterfaceSmall\" TextColor=\"ff2f94ac\">" .. strCount .. "</P>")
		wndFullStats:FindChild("FullStatsGrid"):SetCellDoc(wndRow, 2, strBuy)
		wndFullStats:FindChild("FullStatsGrid"):SetCellDoc(wndRow, 3, strSell)
	end
end

function MarketplaceCommodity:OnGenerateTooltipListIcon(wndHandler, wndControl, eType, nX, nY)
	local tCurrItem = wndHandler:GetData()
	Tooltip.GetItemTooltipForm(self, wndHandler, tCurrItem, {itemCompare = tCurrItem:GetEquippedItemForItemType()})
end

-----------------------------------------------------------------------------------------------
-- Messages
-----------------------------------------------------------------------------------------------

function MarketplaceCommodity:OnCommodityInfoResults(nItemId, tStats, tOrders)
	if not self.wndMain or not self.wndMain:IsValid() then
		return
	end

	local wndMatch = self.wndMain:FindChild("MainScrollContainer"):FindChild(nItemId)
	if not wndMatch or not wndMatch:IsValid() then
		return
	end

	wndMatch:Show(true)
	wndMatch:FindChild("ListItemStatsBubble"):SetData(tStats) -- For OnGenerateTooltipFullStats
	wndMatch:FindChild("ListItemStatsBubble"):Show(tStats.nSellOrderCount and tStats.nSellOrderCount > 0)
	if self.wndMain:FindChild("HeaderBuyNowBtn"):IsChecked() then -- Else it'll use inventory bag count
		wndMatch:FindChild("ListCount"):SetData(tStats.nSellOrderCount)
		wndMatch:FindChild("ListCount"):SetText(tStats.nSellOrderCount)
	end

	-- Average Small
	local nSmall = nil
	local nAverageSmall = nil
	for idx, tRow in ipairs(tStats.arBuyOrderPrices) do
		local nCurrPrice = tRow.monPrice:GetAmount()
		if nCurrPrice and nCurrPrice > 0 then
			if not nSmall then
				nSmall = nCurrPrice
			end
			nAverageSmall = nCurrPrice
		end
	end

	-- Average Big
	local nBig = nil
	local nAverageBig = nil
	for idx, tRow in ipairs(tStats.arSellOrderPrices) do
		local nCurrPrice = tRow.monPrice:GetAmount()
		if nCurrPrice and nCurrPrice > 0 then
			if not nBig then
				nBig = nCurrPrice
			end
			nAverageBig = nCurrPrice
		end
	end

	-- Fill in the second cash window with the first found
	local nValueForInput = 0
	local nValueForLeftPrice = 0
	local strNoData = Apollo.GetString("MarketplaceCommodity_AveragePriceNoData")
	if self.wndMain:FindChild("HeaderBuyNowBtn"):IsChecked() then
		nValueForInput = nAverageBig
		nValueForLeftPrice = nAverageBig
		wndMatch:FindChild("ListSubtitleLeft"):SetText(nAverageBig and Apollo.GetString("MarketplaceCommodity_AverageBuyPrice") or strNoData)
	elseif self.wndMain:FindChild("HeaderSellNowBtn"):IsChecked() then
		nValueForInput = nAverageSmall
		nValueForLeftPrice = nAverageSmall
		wndMatch:FindChild("ListSubtitleLeft"):SetText(nAverageSmall and Apollo.GetString("MarketplaceCommodity_AverageSellPrice") or strNoData)
	else
		nValueForLeftPrice = nSmall
		wndMatch:FindChild("ListSubtitlePriceRight"):Show(nBig)
		wndMatch:FindChild("ListSubtitlePriceRight"):SetAmount(nBig or 0)

		if self.wndMain:FindChild("HeaderBuyOrderBtn"):IsChecked() then
			nValueForInput = nAverageSmall
			wndMatch:FindChild("ListSubtitleLeft"):SetText(Apollo.GetString("MarketplaceCommodity_HighestOfferLabel") .. "\n" .. (nSmall and "" or strNoData))
			wndMatch:FindChild("ListSubtitleRight"):SetText(Apollo.GetString("MarketplaceCommodity_BuyNowLabel") .. "\n" .. (nBig and "" or strNoData))
		elseif self.wndMain:FindChild("HeaderSellOrderBtn"):IsChecked() then
			nValueForInput = nAverageBig
			wndMatch:FindChild("ListSubtitleLeft"):SetText(Apollo.GetString("MarketplaceCommodity_SellNowLabel") .. "\n" .. (nSmall and "" or strNoData))
			wndMatch:FindChild("ListSubtitleRight"):SetText(Apollo.GetString("MarketplaceCommodity_LowestOfferLabel") .. "\n" .. (nBig and "" or strNoData))
		end
	end

	local bCanAfford = true
	if self.wndMain:FindChild("HeaderBuyNowBtn"):IsChecked() or self.wndMain:FindChild("HeaderBuyOrderBtn"):IsChecked() then
		local nPrice = math.max(0, (nValueForInput or 0))
		nPrice = nPrice + math.max(nPrice * MarketplaceLib.kfCommodityBuyOrderTaxMultiplier, MarketplaceLib.knCommodityBuyOrderTaxMinimum)
		bCanAfford = GameLib.GetPlayerCurrency():GetAmount() >= nPrice
	end

	local wndListSubmitBtn = wndMatch:FindChild("ListSubmitBtn")
	local bEnable = nValueForInput and bCanAfford
	wndListSubmitBtn:Enable(bEnable)
	if bEnable then
		local tCurrItem = wndListSubmitBtn:GetData()[1]
		local wndParent = wndListSubmitBtn:GetData()[2]
		local monPricePerUnit = wndParent:FindChild("ListInputPrice"):GetCurrency() -- not an integer
		local nOrderCount = tonumber(wndParent:FindChild("ListInputNumber"):GetText())
		local bBuyTab = self.wndMain:FindChild("HeaderBuyNowBtn"):IsChecked() or self.wndMain:FindChild("HeaderBuyOrderBtn"):IsChecked()

		local orderNew = bBuyTab and CommodityOrder.newBuyOrder(tCurrItem:GetItemId()) or CommodityOrder.newSellOrder(tCurrItem:GetItemId())
		if nOrderCount and monPricePerUnit:GetAmount() > 0 then
			orderNew:SetCount(nOrderCount)
			orderNew:SetPrices(monPricePerUnit)
			orderNew:SetForceImmediate(self.wndMain:FindChild("HeaderBuyNowBtn"):IsChecked() or self.wndMain:FindChild("HeaderSellNowBtn"):IsChecked())
		end

		if not bCanAfford or not nOrderCount or not monPricePerUnit or monPricePerUnit:GetAmount() < 1 or not orderNew:CanPost() then
			wndListSubmitBtn:Enable(false)
		else
			wndListSubmitBtn:SetActionData(GameLib.CodeEnumConfirmButtonType.MarketplaceCommoditiesSubmit, orderNew)
		end
	end
	wndMatch:FindChild("ListInputPrice"):SetAmount(nValueForInput or 0)
	wndMatch:FindChild("ListInputPrice"):SetTextColor(bCanAfford and "white" or "xkcdReddish")
	wndMatch:FindChild("ListSubtitlePriceLeft"):Show(nValueForLeftPrice)
	wndMatch:FindChild("ListSubtitlePriceLeft"):SetAmount(nValueForLeftPrice or 0)

	self.wndMain:FindChild("MainScrollContainer"):ArrangeChildrenVert(0)
end

function MarketplaceCommodity:OnPostCommodityOrderResult(eAuctionPostResult, orderSource, nActualCost)
	local strOkStringFormat = orderSource:IsBuy() and Apollo.GetString("MarketplaceCommodities_BuyOk") or Apollo.GetString("MarketplaceCommodities_SellOk")
	local tAuctionPostResultToString =
	{
		[MarketplaceLib.AuctionPostResult.Ok] 						= String_GetWeaselString(strOkStringFormat, orderSource:GetCount(), orderSource:GetItem():GetName()),
		[MarketplaceLib.AuctionPostResult.DbFailure] 				= Apollo.GetString("MarketplaceAuction_TechnicalDifficulties"),
		[MarketplaceLib.AuctionPostResult.Item_BadId] 				= Apollo.GetString("MarketplaceAuction_CantPostInvalidItem"),
		[MarketplaceLib.AuctionPostResult.NotEnoughToFillQuantity]	= Apollo.GetString("GenericError_Vendor_NotEnoughToFillQuantity"),
		[MarketplaceLib.AuctionPostResult.NotEnoughCash]			= Apollo.GetString("GenericError_Vendor_NotEnoughCash"),
		[MarketplaceLib.AuctionPostResult.NotReady] 				= Apollo.GetString("MarketplaceAuction_TechnicalDifficulties"),
		[MarketplaceLib.AuctionPostResult.CannotFillOrder]		 	= Apollo.GetString("MarketplaceCommodities_NoOrdersFound"),
		[MarketplaceLib.AuctionPostResult.TooManyOrders] 			= Apollo.GetString("MarketplaceAuction_MaxOrders"),
		[MarketplaceLib.AuctionPostResult.OrderTooBig] 				= Apollo.GetString("MarketplaceAuction_OrderTooBig"),
	}

	local strResult = tAuctionPostResultToString[eAuctionPostResult]
	if self.wndMain and self.wndMain:IsValid() then

		if self.wndMain and self.wndMain:FindChild("HeaderBuyNowBtn"):IsChecked() and eAuctionPostResult == MarketplaceLib.AuctionPostResult.CannotFillOrder then
			strResult = Apollo.GetString("MarketplaceCommodity_CannotFillBuyOrder")
		elseif self.wndMain:FindChild("HeaderSellNowBtn"):IsChecked() and eAuctionPostResult == MarketplaceLib.AuctionPostResult.CannotFillOrder then
			strResult = Apollo.GetString("MarketplaceCommodity_CannotFillSellOrder")
		end

		local bResultOK = eAuctionPostResult == MarketplaceLib.AuctionPostResult.Ok
		if bResultOK then
			self:OnRefreshBtn()
		end

		self:OnPostCustomMessage(strResult, bResultOK, 4)

		-- Request up to date info (in case the price/amount has since been updated)
		local itemOrder = orderSource:GetItem()
		if itemOrder then
			MarketplaceLib.RequestCommodityInfo(itemOrder:GetItemId())
		end

		if orderSource:IsPosted() then
			self:UpdateOrderLimit(self.nOwnedOrderCount + 1)
		end
	end
end

function MarketplaceCommodity:OnPostCustomMessage(strMessage, bResultOK, nDuration)
	if not self.wndMain or not self.wndMain:IsValid() then
		return
	end

	local strTitle = bResultOK and Apollo.GetString("CRB_Success") or Apollo.GetString("MarketplaceAuction_ErrorLabel")
	self.wndMain:FindChild("PostResultNotification"):Show(true)
	self.wndMain:FindChild("PostResultNotification"):SetTooltip(strTitle)
	self.wndMain:FindChild("PostResultNotificationSubText"):SetText(strMessage)
	self.wndMain:FindChild("PostResultNotificationLabel"):SetTextColor(bResultOK and ApolloColor.new("UI_TextHoloTitle") or ApolloColor.new("xkcdLightOrange"))
	self.wndMain:FindChild("PostResultNotificationLabel"):SetText(strTitle)
	Apollo.CreateTimer("PostResultTimer", nDuration, false)
end

function MarketplaceCommodity:OnCommodityAuctionRemoved(eAuctionEventType, orderRemoved)
	-- TODO
	--if eAuctionEventType == MarketplaceLib.AuctionEventType.Fill then
	--elseif eAuctionEventType == MarketplaceLib.AuctionEventType.Expire then
	--elseif eAuctionEventType == MarketplaceLib.AuctionEventType.Cancel then
	--end

	if not self.wndMain or not self.wndMain:IsValid() then
		return
	end

	self:UpdateOrderLimit(self.nOwnedOrderCount - 1)
end

function MarketplaceCommodity:OnPostResultTimer()
	if self.wndMain and self.wndMain:IsValid() then
		Apollo.StopTimer("PostResultTimer")
		self.wndMain:FindChild("PostResultNotification"):Show(false)
	end
end

-----------------------------------------------------------------------------------------------
-- Order List
-----------------------------------------------------------------------------------------------

function MarketplaceCommodity:OnCommodityDataReceived(tOrders) -- From MarketplaceLib.RequestOwnedCommodityOrders()
	self:UpdateOrderLimit(#tOrders)
end

function MarketplaceCommodity:UpdateOrderLimit(nCount)
	if not self.wndMain or not self.wndMain:IsValid() then
		return
	end
	if nCount < 0 then
		self.nOwnedOrderCount = 0
	else
		self.nOwnedOrderCount = nCount
	end
	self.wndOrderLimitText:SetText(String_GetWeaselString(Apollo.GetString("MarketplaceCommodity_OrderLimitCount"), self.nOwnedOrderCount, kMaxPlayerCommodityOrders))
end

function MarketplaceCommodity:OnOpenMarketListingsBtn(wndHandler, wndControl)
	Event_FireGenericEvent("InterfaceMenu_ToggleMarketplaceListings")
end

-----------------------------------------------------------------------------------------------
-- Helpers
-----------------------------------------------------------------------------------------------

function MarketplaceCommodity:OnListIconMouseUp(wndHandler, wndControl, eMouseButton)
	if eMouseButton == GameLib.CodeEnumInputMouse.Right and wndHandler:GetData() then
		Event_FireGenericEvent("GenericEvent_ContextMenuItem", wndHandler:GetData())
	end
end

function MarketplaceCommodity:OnPostResultNotificationClick(wndHandler, wndControl)
	if wndHandler == wndControl then
		wndHandler:Show(false)
	end
end

function MarketplaceCommodity:LoadByName(strForm, wndParent, strCustomName)
	local wndNew = wndParent:FindChild(strCustomName)
	if not wndNew then
		wndNew = Apollo.LoadForm(self.xmlDoc, strForm, wndParent, self)
		wndNew:SetName(strCustomName)
	end
	return wndNew
end

local MarketplaceCommodityInst = MarketplaceCommodity:new()
MarketplaceCommodityInst:Init()
�D�	C�C.���L�2e�!V�ON�R���*U��}ڣ�O����^d�)��������_�� �鏘z�n��s�����p�J�d=叇���Èz�ئ+}���s���KC��˵���@#��D}�����2׻�e��Q�%nξ��x<c���'��u�.\��X��_@dK
�~8^������C�Z���x?e���tf�z�n�L�2e�ڰ�����+V٫+sh����*�S'���������>�~���$��6��s؟���'�������ߏ��s[�g�P���S�����_��K�[D=^�0���S0�{��P=ѳ�;�'�|pU�Y�b�����c>h%ʉ����#���C�ږϓ��{R���6���3���4�R�L���g�?͝x��Ɖ�S�� ���ʈ�����7;���ϟ���?�6�ޫ�ǥ�>���/ȵ��P��r~�%� �q����_������l�4<~��('"n���e������'�~�r�S�ϧ5gC�G�WMg�ʔ)S��έx���!�z*���>���Z�OZ�?�ވZ@G�����oiS0}�0�;`}���z�t�?�_U���*�?��G�~z&��3�����(�����I��O��y������>�;x�>����_�3��<����u.�ј�z|��70��W`���yssV�G����߅���1�1)�/R�L�r��2~��o��O���G�������a��x��f����/s�>e%���o�3�d�����_��/�G�|����2M����K��G�����P=Iد��Tm���b� �ȼ�����A��,��C�/���oym���������}�(G���,��7ʔ)S�U��G���(\_9��t|
{D���UQ����u~��8 T򀘟:��Vp���0C��Wk�}H/��];��~U�_xپW���{-�x�P��ҿ��`|��o&���GY�~Բ�h8E�r'^��p����+d��sC_7��7�ov~Q�[�v�ٵ��<~��9�f���?_�|���/���b��{��t8��L]�d�?��2e�#�#��%�/%���Z��(��s�_@�r"5?6�����-:��P�{׻�l��������?z�����Zʴ�ǫ*�ھWO�|T0N�����{)���k�}����m�p��4�.]磿~y�oG�GU�S-V�w13^�L���z����_B]���Dx~�!S�s�����Q<�SZ�����wױ݃]�"�L�W#:_�;h��������ځ~�to8��'��z=���*�X,���~I�om��/R�L�r�8�~r���T�{�Qq1�oR�,����T�j��
��������9�g��S�w�u����X���WQ=��S&4-D��[D}�?�V��WA}27c�gv=ϊ�o:�*־�o�����\?���<����=/c���p:fi�F��?��5�_���פ�V��Yއ���v}��=<��X�Q#�����|uu����K|���]�D��%�/w���5x{����۷֫}��d�����^t��n�v�<���v]�,�z�����	��KL��L�)c��Ν+��z=Uϧػy3�����O��]h~dF��H�2��ei=�X�pTOS�����x�����~��i�dn���S��0��P`I~�[��oj�q@�<k/�9��o���O� ]����z��'2����vmߚ��������l�r�j��] s���e��E㗸���V�>���u_o�WHF��l��b������G䞿_�OD�/���%����b�}ܣ��)1�I�qdL���U���K������.�ꓹC�c;�������9=���}G���|�:�"fX��dm��-�b��NB��l�D��G���'u����6�O�\��f�`�7��
���h�+�w�L�rvXiO�oH�)S��x���.���x��!,f{,�k2o෹֞w���4>y�������P��z~���0	�ێ(�~,s������B�}A�alY��E-����!��z�LI؈���ݜ�����V?���)�:���|��)�O��G��#1��!�-F��p�8�y����V���ҷ//��7����ك��_�~����w�j?�k�
�7���M�y��>�v�-�2��O��-d8_�"\�j����a^�ߤ�o�����8��-w���w���s�S�lޜ�~~i��&��G�2eM����w(Sm}�i�/�<_���0��H��<k��^07����2˼LԷӧ�ޏ	��A}��%�׉��7�x����v��,qvy�C�<s���h���ql���(^ ����Z��}!�)�^�#^�r�/�~�e<�]����}Ļ?��|� �Wr���B����?j=U���G5��)�ڟ�!�1�fO�_�d.��I��u���	{k?��=���Y�e�̕n�~�/�2�`0�x#�h���ޒ�5Z�P��ֿ�p�߁�<�C��F����KG��ў�܊��L�r�}ʔ)k�a����iu<0��;�C�pк��ʷ_�ױ�=�~%s��o�����u`щ���x��~�m����\�/�TO맽�"�L���4]�y���<ᑿ�k�eo_��N;yyR����?C�����H�ϒ�����э�����Eݿ����'W�T�/�PO�T�cp���y9�����=Ξ��.�;��.0������q��_W����t�3/���L.D�86��iW=(~��C����-��D��[.�H��׺�_��O��wP����/E�2���t�6�8���)�C�5�/��ϝ������f�@�O��V�;cq��T�
��x�%nN��;�>V;?ξ:x��@�[�ij��?���_�� [G���9sS��6<�ݵ�10��A|^��7�����R��o��*��`�l��v=��_��\�Zߛ��2������K�|�_=���� �G�U������B3�m4�y��W�B��ndR�O�����}�^�H��G���Q?��8��W��J��%��l4��2e�T��r�t�tʹ�َ玼?�Y� ���3��D