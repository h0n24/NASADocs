-----------------------------------------------------------------------------------------------
-- Client Lua Script for Death
-- Copyright (c) NCsoft. All rights reserved
-----------------------------------------------------------------------------------------------
require "Window"
require "Tooltip"
require "XmlDoc"
require "GameLib"
require "MatchingGame"

---------------------------------------------------------------------------------------------------
-- Death module definition
---------------------------------------------------------------------------------------------------
local Death = {}

---------------------------------------------------------------------------------------------------
-- local constants
---------------------------------------------------------------------------------------------------
local RezType =
{
	Here = 1,
	Eldan = 2,
	SpellCasterLocation = 4,
	ExitInstance = 32
}

local kcrCanResurrectButtonColor = CColor.new(1, 1, 1, 1)
local kcrCannotResurrectButtonColor = CColor.new(.6, .6, .6, 1)
local kcrCanResurrectTextColor = ApolloColor.new("ff9aaea3")
local kcrCannotResurrectTextColor = CColor.new(.3, .3, .3, 1)

local knSaveVersion = 2

---------------------------------------------------------------------------------------------------
-- Death functions
---------------------------------------------------------------------------------------------------
function Death:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self

	o.wndResurrect = nil
	o.nGoldPenalty = 0
	o.bEnableRezHere = true
	o.bEnableCasterRez = false
	o.bHasCasterRezRequest = false
	o.nRezCost = 0
	o.fTimeBeforeRezable = 0
	o.fTimeBeforeWakeHere = 0

	return o
end

function Death:Init()
	Apollo.RegisterAddon(self)
end

---------------------------------------------------------------------------------------------------
-- EventHandlers
---------------------------------------------------------------------------------------------------
function Death:OnLoad()
	self.xmlDoc = XmlDoc.CreateFromFile("Death.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
end


function Death:OnDocLoaded()

	if self.xmlDoc ~= nil and self.xmlDoc:IsLoaded() then
		
		Apollo.RegisterEventHandler("ShowResurrectDialog", 		"OnShowResurrectDialog", self)
		Apollo.RegisterEventHandler("UpdateResurrectDialog", 	"OnUpdateResurrectDialog", self)
		Apollo.RegisterEventHandler("ShowIncapacitationBar", 	"ShowIncapacitationBar", self)
		Apollo.RegisterEventHandler("HideIncapacitationBar", 	"HideIncapacitationBar", self)
		Apollo.RegisterEventHandler("CasterResurrectedPlayer", 	"CasterResurrectedPlayer", self)
		Apollo.RegisterEventHandler("ForceResurrect", 			"OnForcedResurrection", self)
		Apollo.RegisterEventHandler("ScriptResurrect", 			"OnScriptResurrection", self)
		Apollo.RegisterEventHandler("MatchExited", 				"OnForcedResurrection", self)
		Apollo.RegisterEventHandler("PVPDeathmatchPoolUpdated", "OnPVPDeathmatchPoolUpdated", self)
		Apollo.RegisterEventHandler("CharacterCreated", 		"OnCharacterCreated", self)

		self.wndResurrect = Apollo.LoadForm(self.xmlDoc, "ResurrectDialog", nil, self)
		self.wndResurrect:Show(false)

		self.wndExitConfirm = Apollo.LoadForm(self.xmlDoc, "ExitInstanceDialog", nil, self)
		self.wndExitConfirm:Show(false)	
		
		if self.locSavedWindowLoc then
			self.wndResurrect:MoveToLocation(self.locSavedWindowLoc)
		end
		
		self.xmlDoc = nil
		
		self.nTimerProgress = nil
		self.bDead = false
		
		self.timerTenthSec = ApolloTimer.Create(0.10, true, "OnTenthSecTimer", self)
		self.timerTenthSec:Stop()

		if GameLib.GetPlayerUnit() then
			self:OnCharacterCreated()
		end
	end
end

function Death:OnSave(eType)
	if eType ~= GameLib.CodeEnumAddonSaveLevel.Account then
		return
	end
	
	local tSaveData = 
	{
		bCasterRezzed = self.bHasCasterRezRequest,
		tWindowLocation = self.wndResurrect and self.wndResurrect:GetLocation():ToTable() or self.locSavedWindowLoc:ToTable(),
		nSaveVersion = knSaveVersion,
	}
	return tSaveData
end

function Death:OnRestore(eType, tSavedData)
	self.tSavedData = tSavedData
	if tSavedData and tSavedData.nSaveVersion == knSaveVersion then
		self.bHasCasterRezRequest = tSavedData.bCasterRezzed
		
		if tSavedData.tWindowLocation then
			self.locSavedWindowLoc = WindowLocation.new(tSavedData.tWindowLocation)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Interface
---------------------------------------------------------------------------------------------------
function Death:OnCharacterCreated()
	local unitPlayer = GameLib.GetPlayerUnit()
	
	if unitPlayer:IsDead() == false then
		return
	end
	
	self.bDead = true
	self.fTimeBeforeRezable = GetDeathPenalty() 
	self.fTimeBeforeWakeHere = GetWakeHereTime() 
	self.fTimeBeforeForceRez = GetForceRezTime() 
	self.nRezCost = GetRezCost() 
	self.bEnableRezHere = GetRezOptionWakeHere() 
	self.bEnableRezHoloCrypt = GetRezOptionHolocrypt() 
	self.bEnableRezExitInstance = GetRezOptionExitInstance()
	self.bEnableCasterRez = GetRezOptionAcceptCasterRez()
	
	self:OnShowResurrectDialog(self.bDead, self.bEnableRezHere, self.bEnableRezHoloCrypt, self.bEnableRezExitInstance, self.bEnableCasterRez, self.bHasCasterRezRequest, self.nRezCost, self.fTimeBeforeRezable, self.fTimeBeforeWakeHere, self.fTimeBeforeForceRez)
end

function Death:OnShowResurrectDialog(bPlayerIsDead, bEnableRezHere, bEnableRezHoloCrypt, bEnableRezExitInstance, bEnableCasterRez, bHasCasterRezRequest, nRezCost, fTimeBeforeRezable, fTimeBeforeWakeHere, fTimeBeforeForceRez)
	self.timerTenthSec:Start()
	
	self.bDead = bPlayerIsDead
	
	self:OnUpdateResurrectDialog(bEnableRezHere, bEnableRezHoloCrypt, bEnableRezExitInstance, bEnableCasterRez, bHasCasterRezRequest, nRezCost, fTimeBeforeRezable, fTimeBeforeWakeHere, fTimeBeforeForceRez)
end

function Death:OnUpdateResurrectDialog(bEnableRezHere, bEnableRezHoloCrypt, bEnableRezExitInstance, bEnableCasterRez, bHasCasterRezRequest, nRezCost, fTimeBeforeRezable, fTimeBeforeWakeHere, fTimeBeforeForceRez)
	self.bEnableRezHere = bEnableRezHere
	self.bEnableRezHoloCrypt = bEnableRezHoloCrypt
	self.bEnableRezExitInstance = bEnableRezExitInstance
	self.bEnableCasterRez = bEnableCasterRez or false
	self.bHasCasterRezRequest = bHasCasterRezRequest
	self.nRezCost = nRezCost
	self.fTimeBeforeRezable = fTimeBeforeRezable
	self.fTimeBeforeWakeHere = fTimeBeforeWakeHere
	self.fTimeBeforeForceRez = fTimeBeforeForceRez
	
	if self.bDead == false then
		self.wndExitConfirm:Show(false)	
		self.wndResurrect:Show(false)
		self.nTimerProgress = nil
		return
	end
	
	--hide and format everything
	self.wndExitConfirm:Show(false)	
	self.wndResurrect:FindChild("ResurrectDialog.Caster"):Show(false)
	self.wndResurrect:FindChild("ResurrectDialog.Here"):Show(false)
	self.wndResurrect:FindChild("ResurrectDialog.Eldan"):Show(false)
	self.wndResurrect:FindChild("ResurrectDialog.ExitInstance"):Show(false)
	self.wndResurrect:FindChild("ResurrectDialog.EldanSmall"):Show(false)
	self.wndResurrect:FindChild("ResurrectDialog.ExitInstanceSmall"):Show(false)	
	self.wndResurrect:FindChild("ArtTimeToRezHere"):SetText(Apollo.GetString("CRB_Time_Remaining_2"))
	self.wndResurrect:FindChild("ArtTimeToRezHere"):Show(true)
	self.wndResurrect:FindChild("ForceRezText"):Show(false)
	
	if self.bDead and not self.wndResurrect:IsShown() then
		self.wndResurrect:Invoke()
	end
end


------------------------------------//------------------------------
function Death:OnTenthSecTimer() -- there's no reason we can't run the whole thing off of this
	if self.bDead ~= true or not self.wndResurrect:IsVisible() then
		self.bHasCasterRezRequest = false
		return
	end
	
	local nLeft, nTop, nRight, nBottom = self.wndResurrect:GetAnchorOffsets()
			
	-- update all of our timers
	self.fTimeBeforeWakeHere = self.fTimeBeforeWakeHere - 100
	self.fTimeBeforeForceRez = self.fTimeBeforeForceRez - 100
	self.fTimeBeforeRezable = self.fTimeBeforeRezable - 100
			
	if self.fTimeBeforeRezable > 0 then -- this timer takes precendence over everything. if it has a count, the player can't do anything
		local strTimeBeforeRezableFormatted = self:HelperCalcTimeSecondsMS(self.fTimeBeforeRezable)
		self.wndResurrect:FindChild("ResurrectDialog.Timer"):SetText(strTimeBeforeRezableFormatted .. Apollo.GetString("CRB__seconds"))
		self.wndResurrect:FindChild("ResurrectDialog.Timer"):Show(true)
		self.wndResurrect:SetAnchorOffsets(nLeft, nTop, nRight, nTop + 211)
	else
		local tMatchInfo = MatchingGame.GetPVPMatchState()
		if tMatchInfo ~= nil then
			if tMatchInfo.eRules == MatchingGame.Rules.DeathmatchPool then
				if (tMatchInfo.eMyTeam == MatchingGame.Team.Team1 and tMatchInfo.tLivesRemaining.nTeam1 == 0) or (tMatchInfo.eMyTeam == MatchingGame.Team.Team2 and tMatchInfo.tLivesRemaining.nTeam2 == 0) then
					self.wndResurrect:FindChild("ResurrectDialog.Timer"):SetText(Apollo.GetString("Death_NoLives"))
					self.wndResurrect:FindChild("ResurrectDialog.Timer"):Show(true)	
					self.wndResurrect:SetAnchorOffsets(nLeft, nTop, nRight, nTop + 211)
					self.wndResurrect:FindChild("ForceRezText"):Show(false)
					self.wndResurrect:FindChild("ResurrectDialog.Here"):Show(false)
					self.wndResurrect:FindChild("ResurrectDialog.Eldan"):Show(false)
					self.wndResurrect:FindChild("ResurrectDialog.EldanSmall"):Show(false)
					self.wndResurrect:FindChild("ResurrectDialog.ExitInstanceSmall"):Show(false)		
					self.wndResurrect:FindChild("ResurrectDialog.Caster"):Show(false)	
					return
				end
			elseif tMatchInfo.eRules == MatchingGame.Rules.WaveRespawn then
				self.wndResurrect:Close()
				return
			end
		end
	
		self.wndResurrect:FindChild("ArtTimeToRezHere"):Show(false)
		self.wndResurrect:FindChild("ResurrectDialog.Timer"):Show(false)
		self.wndResurrect:FindChild("ForceRezText"):Show(self.fTimeBeforeForceRez > 0)
		self.wndResurrect:FindChild("ResurrectDialog.Here"):Show(self.bEnableRezHere)
		self.wndResurrect:FindChild("ResurrectDialog.Eldan"):Show(self.bEnableRezHoloCrypt and not self.bEnableRezExitInstance)
		self.wndResurrect:FindChild("ResurrectDialog.ExitInstance"):Show(not self.bEnableRezHoloCrypt and self.bEnableRezExitInstance)
		self.wndResurrect:FindChild("ResurrectDialog.EldanSmall"):Show(self.bEnableRezHoloCrypt and self.bEnableRezExitInstance)
		self.wndResurrect:FindChild("ResurrectDialog.ExitInstanceSmall"):Show(self.bEnableRezHoloCrypt and self.bEnableRezExitInstance)		
		self.wndResurrect:FindChild("ResurrectDialog.Caster"):Show(self.bEnableCasterRez and self.bHasCasterRezRequest)	
		

		if self.wndResurrect:FindChild("ResurrectDialog.Caster"):IsShown() then
			self.wndResurrect:SetAnchorOffsets(nLeft, nTop, nRight, nTop + 320)
		elseif self.wndResurrect:FindChild("ResurrectDialog.Here"):IsShown() or self.wndResurrect:FindChild("ResurrectDialog.EldanSmall"):IsShown() then
			self.wndResurrect:SetAnchorOffsets(nLeft, nTop, nRight, nTop + 288)
		else
			self.wndResurrect:SetAnchorOffsets(nLeft, nTop, nRight, nTop + 220)
		end
		
		self.wndResurrect:FindChild("ResurrectDialogButtons"):ArrangeChildrenVert(0)
		-- set up rez here
		if self.wndResurrect:FindChild("ResurrectDialog.Here"):IsShown() then
			local wndBtn = self.wndResurrect:FindChild("ResurrectDialog.Here")
			wndBtn:FindChild("ResurrectDialog.Cash"):SetAmount(self.nRezCost)
						
			if self.fTimeBeforeWakeHere <= 0 then  -- ready to go
				local bCanAfford = self.nRezCost <= GameLib.GetPlayerCurrency():GetAmount()
				wndBtn:Enable(bCanAfford)
				wndBtn:FindChild("WakeHereText"):SetText(Apollo.GetString("Death_WakeHere"))
				wndBtn:FindChild("WakeHereCooldownText"):SetText("")
				wndBtn:FindChild("ResurrectDialog.Cash"):Show(true)
				wndBtn:FindChild("CostLabel"):Show(true)
				if bCanAfford then
					self.wndResurrect:FindChild("ResurrectDialog.Here"):SetBGColor(kcrCanResurrectButtonColor)
					wndBtn:FindChild("WakeHereText"):SetTextColor(kcrCanResurrectTextColor)
					wndBtn:FindChild("ResurrectDialog.Cash"):SetTextColor(ApolloColor.new("white"))
				else -- not enough money
					self.wndResurrect:FindChild("ResurrectDialog.Here"):SetBGColor(kcrCannotResurrectButtonColor)
					wndBtn:FindChild("WakeHereText"):SetTextColor(kcrCannotResurrectTextColor)	
					wndBtn:FindChild("ResurrectDialog.Cash"):SetTextColor(ApolloColor.new("red"))						
				end	
			else -- still cooling down
				wndBtn:Enable(false)
				local strCooldownFormatted = self:HelperCalcTimeMS(self.fTimeBeforeWakeHere)
				wndBtn:FindChild("WakeHereCooldownText"):SetText(String_GetWeaselString(Apollo.GetString("Death_CooldownTimer"), strCooldownFormatted))
				wndBtn:FindChild("ResurrectDialog.Cash"):Show(false)
				wndBtn:FindChild("CostLabel"):Show(false)
				self.wndResurrect:FindChild("ResurrectDialog.Here"):SetBGColor(kcrCannotResurrectButtonColor)
				wndBtn:FindChild("WakeHereText"):SetTextColor(kcrCannotResurrectTextColor)					
			end
		end	
	end
		
	if self.fTimeBeforeForceRez > 0 then
		local strTimeFormatted = self:HelperCalcTimeMS(self.fTimeBeforeForceRez)
		self.wndResurrect:FindChild("ForceRezText"):SetText(String_GetWeaselString(Apollo.GetString("Death_AutoRelease"), strTimeFormatted))
	end

end

------------------------------------//------------------------------

function Death:CasterResurrectedPlayer(strCasterName)
	self.bHasCasterRezRequest = true;
end

function Death:OnResurrectHere()
	if GameLib.GetPlayerUnit() ~= nil then
		GameLib.GetPlayerUnit():Resurrect(RezType.Here, 0)
	end
	
	self.wndResurrect:Close()
	self.bDead = false
	
	self.timerTenthSec:Stop()
	Event_FireGenericEvent("PlayerResurrected")
end
------------------------------------//------------------------------
function Death:OnResurrectCaster()
	if GameLib.GetPlayerUnit() ~= nil then
		GameLib.GetPlayerUnit():Resurrect(RezType.SpellCasterLocation, 0) -- WIP, this should send in the UnitId of the caster
	end
	
	self.wndResurrect:Close()
	self.bDead = false
	
	self.timerTenthSec:Stop()
	Event_FireGenericEvent("PlayerResurrected")
end
------------------------------------//------------------------------
function Death:OnResurrectEldan()
	if GameLib.GetPlayerUnit() ~= nil then
		GameLib.GetPlayerUnit():Resurrect(RezType.Eldan, 0)
	end

	self.wndResurrect:Show(false)
	self.bDead = false
	
	self.timerTenthSec:Stop()
	Event_FireGenericEvent("PlayerResurrected")
	
	if GameLib.GetPvpFlagInfo().nCooldown then
		ChatSystemLib.PostOnChannel( ChatSystemLib.ChatChannel_System, Apollo.GetString("Death_PvPFlagReset"), "" )
	end
end
------------------------------------//------------------------------
function Death:OnExitInstance()
	self.wndExitConfirm:Invoke()
	self.wndResurrect:Close()
end

function Death:OnConfirmExit()
	if GameLib.GetPlayerUnit() ~= nil then
		GameLib.GetPlayerUnit():Resurrect(RezType.ExitInstance, 0)
	end

	self.wndExitConfirm:Close()	
	self.wndResurrect:Close()
	self.bDead = false
	
	self.timerTenthSec:Stop()
	Event_FireGenericEvent("PlayerResurrected")
end

function Death:OnCancelExit()
	self.wndExitConfirm:Close()	
	self.wndResurrect:Invoke()
end

------------------------------------//------------------------------
function Death:OnForcedResurrection()
	self.wndExitConfirm:Show(false)	
	self.wndResurrect:Close()
	self.bDead = false

	self.timerTenthSec:Stop()
	Event_FireGenericEvent("PlayerResurrected")
end

------------------------------------//------------------------------
function Death:OnScriptResurrection()
	self.wndExitConfirm:Show(false)	
	self.wndResurrect:Close()
	self.bDead = false

	self.timerTenthSec:Stop()
	Event_FireGenericEvent("PlayerResurrected")
end

------------------------------------//------------------------------

function Death:HideIncapacitationBar()
	self.wndExitConfirm:Show(false)	
	self.wndResurrect:Show(false)
end

function Death:HelperCalcTimeSecondsMS(fTimeMS)
	local fTime = math.floor(fTimeMS / 1000)
	local fMillis = fTimeMS % 1000
	return string.format("%d.%d", fTime, math.floor(fMillis / 100))
end

function Death:HelperCalcTimeMS(fTimeMS)
	local fSeconds = fTimeMS / 1000
	local fMillis = fTimeMS % 1000
	local strOutputSeconds = "00"
	if math.floor(fSeconds % 60) >= 10 then
		strOutputSeconds = tostring(math.floor(fSeconds % 60))
	else
		strOutputSeconds = "0" .. math.floor(fSeconds % 60)
	end
	
	return String_GetWeaselString(Apollo.GetString("CRB_TimeMinsToMS"), math.floor(fSeconds / 60), strOutputSeconds, math.floor(fMillis / 100))
end

function Death:HelperCalcTime(fSeconds)
	local strOutputSeconds = "00"
	if math.floor(fSeconds % 60) >= 10 then
		strOutputSeconds = tostring(math.floor(fSeconds % 60))
	else
		strOutputSeconds = "0" .. math.floor(fSeconds % 60)
	end
	
	return String_GetWeaselString(Apollo.GetString("CRB_TimeMinsToMS"), math.floor(fSeconds / 60), strOutputSeconds)
end

---------------------------------------------------------------------------------------------------
-- Death instance
---------------------------------------------------------------------------------------------------
local DeathInst = Death:new()
DeathInst:Init()
��d6~�z?����~���p}�|��܃��9Ɔ�M�Wɓ�C��f�|*��Z�~E���u*��ϋ�K��p'�2�`���?�<ü����s����&�\U�殎�����+dP�"�H��;P/{�n��[v� W�3��~��h�POH�U����#������^�U��}���|f��M�~�!���B����+�y������b���t{�����o"�^��39�8��asd�%�zf��,�?K�������	���1��m]�p��w
����E��,,���t��#	��c���z��Q��܋�\=����'�O�+>�ur���P"ٴt����^�>B���+4��|�P�X��A�G$i��9�~�C��^z ��a����>���V���迱=�\/�/�|���ߴtU���*���}�-eM����Po�-��y���&�+2T�?�`�/�R����B��)��}�ي=��,\/.�_�����G4��\=Z&3:�?�����{����F�;Vm��3&�_���l��Fmv<�U���:�WN���zn>��:?R������$�/~�U�~
􊘐w{�)�I�-w��H�R����M��=t��$��J���ZdS��G�/*��Q�;4�~!�"�O�������0����X���Ƈzm�ԏ�a};G�U���N����1�9�ʩ�70�'�!Z¾��]><�Z�W%.8d�������7E����W�/�⿻��o����]YL�%/�ޟ� ~VrI���Jn��~V^�A�h�8:�\|�`��b��S��|��+ҟ~��\ft��Q�|^�	������!7�� �'�����"���H���qɠz=���r&��6�蜭�y���$#ٍ��<��WQ�nd~4�P��|G��貢
���6:��$�@��9��OyR�sB�B�G�ُewS}�),
��u(�������2�����^5���r�j�0�s������ˡ����K2?��a��T�?$k�N�6���k�E����wfs���L��Z_�Csw=c$�]�q��~A���vw�l�6�|�/�Ba��\���~^V��#!�u�`�J�~񇛏%����2�S}z�\T[ȯ�-vU�������Ozv���gޜ ����$ƶ��B$W�����m$!��?����y�S��)�/�Kp���wכ��>��s�G��
�2:��?
z����%[`>�����B���~��T�ڀa� faV�������ޝ��RdܥZ|�8a���¼QŪ�ǽ���/��ؿ���B��y���5��n=䖿��� �9��%��?��ƞ��*��1eQE�%��*�/_cr�/ܞ!b���؋,��������.��:�e�>~���u�W�>�c5#ɐ�=_��G]���P�Đ"����F��E.��\�G����=]���p�r*��< �/��s��3Iu�𽝞�l>O��Dz�-��*�������Z��[�]o�����^�6�ܨ<��~Ŀ16o����"�wj���KӠ�0rP}�i6��'�+��.�9�X8��"ԓP�r�^��w�z��%!o���=�~�z��^�@��,z�JٗŹ�/y�6Kq}Wz9͗�ʠ���T��Y�k��`����{�K�y�����h�������^��|t*ߵY��	"F]�K�~�<(o��o�$�vw�J,q̘~����w�����_�P߫��g����7B�aI�����E��r����Ȯ/���ɵ�s��i��σ�k���f�j��^��_��q��k?d��}qd��*5Q\T�l��؜�� ����#-"1�[�Ry�D�=��iS�8�>�~���̯����;���F�����G��J��6 S��E�y`Z��7^:<�E�(˵ڰN�}��~)��+���9��Q	�>_��/����/[TaM^���N�{qe��?4K��.�y����Db���e�ON��5�E�<�.� "�Q����-�	�{�_�`�^��o��o���&㣍���mt���
�>��K�od��������g�"?�����u�B��HQ�{�Ɔ����8=�	~��.��y_F�M W�^�z��'�_��=i���Y�<�ۡ>�EƊ�~�<A3�˔|]o"!�x������֛0d��[�=�_��c���ʵ���d��y&���5������\�I��n��Y:u������\;���[.�gX*��3ܼQ?�����/�O��q�<���y!�s,�z坆2e�W�.�tUT�]�����P����/�I���zEƬ��G~�S��W�_�f,��4�!?��=�8�U�+U��n���-��c�����.���?��sO�L����?��`�c�U����1rmV�m�����/��^����t������ޓ/�E��6� ��7���So�x6w�������#i��3���r��!�!���N_̾�tYM����
՗���_��Kn�0���Z���,��rOO��|���$�~ʺ�p�c��s�����¢�a4_��������~�����s�����z���������[UTP��2Wo���7�\3(C��Z*X���W�J���X5bGS��O40��d��?������[ޯ�FRJ���#�Toh���6l�3���Z�s�]d�Ga�� _�F{㛭��a���֭7���V}�����e�EǾD��tjS�yq�<2_pw�����qb�j"�w*�eI
�N�w������pR=i��E�٨��K��x]����A�c	������9�+&�/��ֽ���ˣ]�4���oA�`=�?�p�$��\��m��Ѣ����ca>�s�V=t���_�oR����ps*�Y��
�V_t.�z�x���p2�$'��/�ߛ��6$l����T�\=�\+�Owl���XSW��W��$��R�B *nhD��X��C[R�3��)��k!�e��1X(ZS�V���i':����~gJ���i�Rϙ�WD륚V�f�o�k'���L�Ut��<}~B����Z��z�we�ygx,�R2�?�$Ɖ�����6��