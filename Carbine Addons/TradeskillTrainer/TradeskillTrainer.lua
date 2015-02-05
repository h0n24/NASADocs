-----------------------------------------------------------------------------------------------
-- Client Lua Script for TradeskillTrainer
-- Copyright (c) NCsoft. All rights reserved
-----------------------------------------------------------------------------------------------

require "Window"
require "XmlDoc"
require "Apollo"
require "CraftingLib"


local TradeskillTrainer = {}

local knMaxTradeskills = 2 -- how many skills is the player allowed to learn

function TradeskillTrainer:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function TradeskillTrainer:Init()
    Apollo.RegisterAddon(self)
end

function TradeskillTrainer:OnLoad()
    self.xmlDoc = XmlDoc.CreateFromFile("TradeskillTrainer.xml")
    self.xmlDoc:RegisterCallback("OnDocumentReady", self)
end

function TradeskillTrainer:OnDocumentReady()
    if self.xmlDoc == nil then
        return
    end

	Apollo.RegisterEventHandler("InvokeTradeskillTrainerWindow", "OnInvokeTradeskillTrainer", self)
	Apollo.RegisterEventHandler("CloseTradeskillTrainerWindow", "OnClose", self)

	self.nActiveTradeskills = 0
end

function TradeskillTrainer:OnInvokeTradeskillTrainer(unitTrainer)
	if not self.wndMain or not self.wndMain:IsValid() then
		self.wndMain = Apollo.LoadForm(self.xmlDoc, "TradeskillTrainerForm", nil, self)
		Event_FireGenericEvent("WindowManagementAdd", {wnd = self.wndMain, strName = Apollo.GetString("DialogResponse_TradskillTraining")})

		if self.locSavedWindowLoc then
			self.wndMain:MoveToLocation(self.locSavedWindowLoc)
		end
	end

	self.nActiveTradeskills = 0
	self.wndMain:FindChild("ListContainer"):DestroyChildren()

	self.wndMain:FindChild("SwapTradeskillBtn1"):SetData(nil)
	self.wndMain:FindChild("SwapTradeskillBtn2"):SetData(nil)

	for idx, tTradeskill in ipairs(unitTrainer:GetTrainerTradeskills()) do
		local tInfo = CraftingLib.GetTradeskillInfo(tTradeskill.eTradeskillId)
		if not tInfo.bIsHobby then
			local wndCurr = Apollo.LoadForm(self.xmlDoc, "ProfListItem", self.wndMain:FindChild("ListContainer"), self)
			wndCurr:FindChild("ListItemBtn"):SetData(tTradeskill.eTradeskillId)
			wndCurr:FindChild("ListItemText"):SetText(tInfo.strName)
			wndCurr:FindChild("ListItemCheck"):Show(tInfo.bIsActive)

			if tInfo.bIsActive then
				self.nActiveTradeskills = self.nActiveTradeskills + 1

				if self.wndMain:FindChild("SwapTradeskillBtn1"):GetData() == nil then
					self.wndMain:FindChild("SwapTradeskillBtn1"):SetData(tTradeskill.eTradeskillId)
					self.wndMain:FindChild("SwapTradeskillBtn1"):SetText(String_GetWeaselString(Apollo.GetString("TradeskillTrainer_SwapWith"), tInfo.strName))
				else
					self.wndMain:FindChild("SwapTradeskillBtn2"):SetData(tTradeskill.eTradeskillId)
					self.wndMain:FindChild("SwapTradeskillBtn2"):SetText(String_GetWeaselString(Apollo.GetString("TradeskillTrainer_SwapWith"), tInfo.strName))
				end
			end
		end
	end

	for idx, tTradeskill in ipairs(CraftingLib.GetKnownTradeskills()) do
		local tInfo = CraftingLib.GetTradeskillInfo(tTradeskill.eId)
		if tInfo.bIsHobby and tTradeskill.eId ~= CraftingLib.CodeEnumTradeskill.Farmer then
			local wndCurr = Apollo.LoadForm(self.xmlDoc, "HobbyListItem", self.wndMain:FindChild("ListContainer"), self)
			wndCurr:FindChild("ListItemBtn"):SetData(tTradeskill.eId)
			wndCurr:FindChild("ListItemText"):SetText(tInfo.strName)
			wndCurr:FindChild("ListItemCheck"):Show(true)
		end
	end

	self.wndMain:FindChild("ListContainer"):ArrangeChildrenVert(0)
end

function TradeskillTrainer:OnClose()
	if self.wndMain then
		self.locSavedWindowLoc = self.wndMain:GetLocation()
		self.wndMain:Destroy()
		self.wndMain = nil
	end
	Event_CancelTradeskillTraining()
end

function TradeskillTrainer:OnWindowClosed(wndHandler, wndControl)
	self:OnClose()
end

function TradeskillTrainer:OnProfListItemClick(wndHandler, wndControl) -- wndHandler is "ListItemBtn", data is tradeskill id
	for key, wndCurr in pairs(self.wndMain:FindChild("BGLeft:ListContainer"):GetChildren()) do
		if wndCurr:FindChild("ListItemBtn") then
			wndCurr:FindChild("ListItemBtn"):SetCheck(false)
			if wndCurr:GetName() == "HobbyListItem" then
				wndCurr:FindChild("ListItemBtn:ListItemText"):SetTextColor(ApolloColor.new("UI_BtnTextGoldListPressed"))
			else
				wndCurr:FindChild("ListItemBtn:ListItemText"):SetTextColor(ApolloColor.new("UI_BtnTextGoldListNormal"))
			end
		end
	end
	wndHandler:SetCheck(true)
	wndHandler:FindChild("ListItemText"):SetTextColor(ApolloColor.new("UI_BtnTextGoldListPressed"))

	-- Main's right panel formatting
	local idTradeskill = wndHandler:GetData()
	local bAtMax = self.nActiveTradeskills == knMaxTradeskills
	local tTradeskillInfo = CraftingLib.GetTradeskillInfo(idTradeskill)	
	local bAlreadyKnown = wndHandler:FindChild("ListItemCheck"):IsShown()

	self.wndMain:FindChild("RightContainer:BottomBG:AlreadyKnown"):Show(false)
	self.wndMain:FindChild("RightContainer:BottomBG:HobbyMessage"):Show(false)
	self.wndMain:FindChild("RightContainer:BottomBG:CooldownLocked"):Show(false)
	self.wndMain:FindChild("RightContainer:BottomBG:SwapContainer"):Show(false)
	self.wndMain:FindChild("RightContainer:BottomBG:LearnTradeskillBtn"):Show(false)
	self.wndMain:FindChild("RightContainer:BottomBG:LearnTradeskillBtn"):SetData(wndHandler:GetData()) -- Also used in Swap
	self.wndMain:FindChild("RightContainer:BottomBG:FullDescription"):SetText(tTradeskillInfo.strDescription)

	local nCooldownCurrent = CraftingLib.GetRelearnCooldown() or 0
	local nCooldownNew = tTradeskillInfo and tTradeskillInfo.nRelearnCooldownDays or 0
	if nCooldownCurrent > 0 then
		local strCooldownText = ""
		if nCooldownCurrent < 1 then
			strCooldownText = Apollo.GetString("TradeskillTrainer_SwapOnCooldownShort")
		else
			strCooldownText = String_GetWeaselString(Apollo.GetString("TradeskillTrainer_SwapOnCooldown"), tostring(math.floor(nCooldownCurrent + 0.5)))
		end
		self.wndMain:FindChild("RightContainer:BottomBG:CooldownLocked"):Show(true)
		self.wndMain:FindChild("RightContainer:BottomBG:CooldownLocked:CooldownLockedText"):SetText(strCooldownText)
	elseif bAlreadyKnown then
		self.wndMain:FindChild("RightContainer:BottomBG:AlreadyKnown"):Show(true)
	elseif bAtMax and not bAlreadyKnown then
		local nRelearnCost = CraftingLib.GetRelearnCost(idTradeskill):GetAmount()
		local strCooldown = String_GetWeaselString(Apollo.GetString("Tradeskill_Trainer_CooldownDynamic"), nCooldownNew)
		local strCooldownTooltip = String_GetWeaselString(Apollo.GetString("Tradeskill_Trainer_CooldownDynamicTooltip"), nCooldownNew)

		local wndSwapContainer = self.wndMain:FindChild("RightContainer:BottomBG:SwapContainer")
		wndSwapContainer:Show(true)
		wndSwapContainer:FindChild("CostWindow"):Show(nRelearnCost > 0 or nCooldownNew > 0)
		wndSwapContainer:FindChild("CostWindow:SwapCashWindow"):SetAmount(nRelearnCost)
		wndSwapContainer:FindChild("SwapTimeWarningContainer"):Show(nRelearnCost > 0 or nCooldownNew > 0)
		wndSwapContainer:FindChild("SwapTimeWarningContainer"):SetTooltip(strCooldownTooltip)
		wndSwapContainer:FindChild("SwapTimeWarningContainer:SwapTimeWarningLabel"):SetText(strCooldown)
	elseif not bAtMax and not bAlreadyKnown then
		self.wndMain:FindChild("LearnTradeskillBtn"):Show(true)
	end

	-- Current Craft Blocker
	local tCurrentCraft = CraftingLib.GetCurrentCraft()
	self.wndMain:FindChild("RightContainer:BottomBG:BotchCraftBlocker"):Show(tCurrentCraft and tCurrentCraft.nSchematicId)
end

function TradeskillTrainer:OnHobbyListItemClick(wndHandler, wndControl)
	for key, wndCurr in pairs(self.wndMain:FindChild("ListContainer"):GetChildren()) do
		if wndCurr:FindChild("ListItemBtn") then
			wndCurr:FindChild("ListItemBtn"):SetCheck(false)
			if wndCurr:GetName() == "HobbyListItem" then
				wndCurr:FindChild("ListItemText"):SetTextColor(ApolloColor.new("UI_BtnTextGoldListPressed"))
			else
				wndCurr:FindChild("ListItemText"):SetTextColor(ApolloColor.new("UI_BtnTextGoldListNormal"))
			end
		end
	end
	wndHandler:SetCheck(true)
	wndHandler:FindChild("ListItemText"):SetTextColor(ApolloColor.new("UI_BtnTextGoldListPressed"))

	-- Main's right panel formatting
	self.wndMain:FindChild("AlreadyKnown"):Show(false)
	self.wndMain:FindChild("CooldownLocked"):Show(false)
	self.wndMain:FindChild("SwapContainer"):Show(false)
	self.wndMain:FindChild("LearnTradeskillBtn"):Show(false)
	self.wndMain:FindChild("FullDescription"):SetText(CraftingLib.GetTradeskillInfo(wndHandler:GetData()).strDescription)

	self.wndMain:FindChild("HobbyMessage"):Show(true)
end

function TradeskillTrainer:OnLearnTradeskillBtn(wndHandler, wndControl)
	if not wndHandler or not wndHandler:GetData() then
		return
	end

	local nCurrentTradeskill = self.wndMain:FindChild("LearnTradeskillBtn"):GetData()
	local tCurrTradeskillInfo = CraftingLib.GetTradeskillInfo(nCurrentTradeskill)
		if not tCurrTradeskillInfo.bIsHarvesting then
			Event_FireGenericEvent("TradeskillLearnedFromTHOR")
		else
	end
	CraftingLib.LearnTradeskill(nCurrentTradeskill)
	self:OnClose()
end

function TradeskillTrainer:OnSwapTradeskillBtn(wndHandler, wndControl) --SwapTradeskillBtn1 or SwapTradeskillBtn2, data is nTradeskillId
	if not wndHandler or not wndHandler:GetData() then
		return
	end

	local nCurrentTradeskill = self.wndMain:FindChild("LearnTradeskillBtn"):GetData()
	local tCurrTradeskillInfo = CraftingLib.GetTradeskillInfo(nCurrentTradeskill)
		if not tCurrTradeskillInfo.bIsHarvesting then
			Event_FireGenericEvent("TradeskillLearnedFromTHOR")
		else
	end

	CraftingLib.LearnTradeskill(nCurrentTradeskill, wndHandler:GetData())
	self:OnClose()
end

local TradeskillTrainerInst = TradeskillTrainer:new()
TradeskillTrainerInst:Init()
���n��N�\f~�%av!�p�[r���Ԃ���N\Xh��\m��KuRy A���8J~&�B�;�E��{�Y�P/6�Y�R�F�7��!6O
�У���ӝ�����)�6!�~J���Xn���o�э��Bb���{����O�ԏ�*.b�����h�9�V��͇Z��#�?� ��䌆]k��=\�rV�HMv���߇Z���G�U��V���L'�a����E�
(�㼨�܂����M)�����Ϧ/��NY�CM�a~9��+���?w�%��_$"�G}!̸�<\�#I��QF�F�u\��(D�����6XY��L�Ӭ�����>��SHE�7�r?D��O9����46wq0 �4�L�Z:�C.E�F���,�H�'�`���Ԓ��ÿ/9��[�,e ����I��xߏ��Y][��Z1T�=z8��(��mb�~X���UI2P������404.�rYV`@V��?y=���G��G�⩿v�R�e�q �W���0.������f���9\��	�e�y�8����,AsfS��R	d�pĘ\��������u��}!�QL#-��fNc?*'ެ��N�x����6��O6ž%��\{�;��)3o2��L��1������GJ�\�[�����Du�М��e�p�70p�#�r}. .9�H�0ѫ�G߮?]��i��lg)Y#�5�����o��D��E�Hȧź�p�F�g��J����hO�n�|J�g�X�~7m~7m~7m~7m~7m~�[^;���n��h�1r�6�{��ǟ��=9Y��J�e�j�bC�l���;��l�/wv8���=2S�����B!�~��>�c̔��<|t̓=c�peO�({���R�$�k3U�j��c��5�+pَ?qW�-F/]���Br�J�	��lS��<�c��MjL	��dm��^FQ�,��<�h�[F�4">���j�Y�䥌�v���T��.^q�����Y��f�m_4zm4�
��,�k�9�[�@�&�qd�Z��M#�a��"��e�.q@��-��͝ߔX5�^M��a�.,��"��M�;z�~�Z�Eh4����c��<
�уx.(	Ϧξ�������J��?f��H��z��K-�}�d���6N�	�m��?[����|v)6�����ΰoE���0&$�nf�6�S���yv�!����n�ݚж�$�eV��D���!|�M����x����x$�"�]$+�2���=\�w��J~<[WG��`%����߰Q&"� v�t�}�p�� �]ƻ�ލ��'��G��:û,@�>�������˝���ER�/2���L�KrϤ�R���p����S�X`����W Bf�����XHe�� �W�-�,���7��x�S�P�O�!�@�G����ځp��	~�������㾋��'�8#@[R�}�:U��/�r�M譈���b��t��G��MT���/>Y7���G��K_�>
�yw��[�(o�".�{l\CBU�ݴ��M)=��ʛ�
���ǈ)u��*��5_��}T<ڹ����<ӏ,(Si70C��%̀����(���ͳ����-'���'��]g3B?ͽ$���=腕�+�p[��mR�UE	���B,���v W��pLQ>\_goJҺ꺒�F眈�R�ܼ]u+�G�r�7�h��	��UK�~�AM���nD��C]祖'��\$�Ǖ�|[w�z�����1v��s�T����s���a��~R�w�^(��XQ!0z���T�������]���l����$�Х�$�}�ѕ��F˕���c�����gЦ������M�T���Od[[W}W�Nûڶ��Mc�e�A�|��eZ����=b�$�Z���\7���F�%ZwYN��B�-Y&�f�Ƃ�!.&��*�Lk�a�a~�i���5��nĸ���� t�@Hv��F*2��
�t��&!�J�h���쟔�5�t�q.�#�ww�7t'�������8�%�»d�i����49n �s�q"���rZ���Y]|k���4�F̶sw�ڸ��ry7R0l�L�F� ����P��N�u�kg�+j�UF���n䶃���w�k�\���Z�=|I�o3�z�P��w���:{�[8H���u^�,|�!<�>�������Nv�;y���lT����g*��)�|]@�^Q�p�+;zl=}dM�xOu�g�F�� ��|��hV�(��	t���-�f�Qfd^��$�<s�=���wV�o9s�L��@�����o�������wΤ�|���Ȟ�h
�67����Mk72��>A�֍�r��U�0 	����1�A��4�����+7�b��Ɏ��o�J9K�:Ui��BSo�