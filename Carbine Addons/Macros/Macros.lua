require "Window"
require "MacrosLib"


---------------------------------------------------------------------------------------------------
-- Macros module definition

local Macros = {}

---------------------------------------------------------------------------------------------------
-- Macros initialization
---------------------------------------------------------------------------------------------------
function Macros:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	
	-- initialize our variables

	-- return our object
	return o
end

---------------------------------------------------------------------------------------------------
function Macros:Init()
	Apollo.RegisterAddon(self)
end

---------------------------------------------------------------------------------------------------
-- Macros EventHandlers
---------------------------------------------------------------------------------------------------

function Macros:OnLoad()
	self.xmlDoc = XmlDoc.CreateFromFile("Macros.xml")
	self.xmlDoc:RegisterCallback("OnDocumentReady", self) 
end

function Macros:OnDocumentReady()
	if  self.xmlDoc == nil then
		return
	end
	
	Apollo.RegisterEventHandler("InterfaceMenuListHasLoaded", "OnInterfaceMenuListHasLoaded", self)
	Apollo.RegisterEventHandler("WindowManagementReady", 	"OnWindowManagementReady", self)
	Apollo.RegisterEventHandler("InterfaceMenu_ToggleMacro", "OnInterfaceMenu_ToggleMacro", self)
	Apollo.RegisterSlashCommand("macros", "OnMacrosOn", self)
	Apollo.RegisterSlashCommand("reloadui", "OnRequestReloadUI", self)
	Apollo.RegisterTimerHandler("LoadIconTimer", "OnLoadIcons", self)

	-- load our forms
	self.wndMacros = Apollo.LoadForm(self.xmlDoc, "MacrosWindow", nil, self)
	self.wndMacroList = self.wndMacros:FindChild("List")
	self.wndEditMacro = self.wndMacros:FindChild("EditMacro")
	self.wndDeleteMacro = self.wndMacros:FindChild("DeleteMacro")
	self.wndMacros:Show(false)
	if self.locSavedWindowLoc then
		self.wndMacros:MoveToLocation(self.locSavedWindowLoc)
	end
		
	self.tItems = {}
	self.wndEdit = nil
	self.wndIcon = nil
	self.wndSelectedMacroItem = nil
	self.bIconTimerCreated = false
	
	self:EnableEditingButtons(false)
end

function Macros:OnInterfaceMenuListHasLoaded()
	Event_FireGenericEvent("InterfaceMenuList_NewAddOn", Apollo.GetString("InterfaceMenu_Macro"), {"InterfaceMenu_ToggleMacro", "", "Icon_Windows32_UI_CRB_InterfaceMenu_Macro"})
end

function Macros:OnWindowManagementReady()
	Event_FireGenericEvent("WindowManagementAdd", {wnd = self.wndMacros, strName = Apollo.GetString("InterfaceMenu_Macro")})
end
	
function Macros:OnInterfaceMenu_ToggleMacro()
	if self.wndMacros and self.wndMacros:IsValid() and self.wndMacros:IsVisible() then
		self.wndMacros:Close()
	else
		self:OnMacrosOn()
	end
end
---------------------------------------------------------------------------------------------------
-- Functions
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Main Dialog (wndMacros)
---------------------------------------------------------------------------------------------------

function Macros:OnMacrosOn()

	self.wndMacros:Show(true)
	self.wndMacros:ToFront()
	self:EnableEditingButtons(false)
	
	for idx, wnd in ipairs(self.tItems) do
		wnd:Destroy()
	end
	self.tItems = {}
	
	-- get list of macros 
	local tListMacros = MacrosLib.GetMacrosList()
	
	for idx = 1, #tListMacros do
        self:AddMacro(idx, tListMacros[idx].nId)
        self:UpdateMacroUIData(self.tItems[idx], tListMacros[idx]);
	end
	
	self.wndMacroList:ArrangeChildrenVert()
end

function Macros:OnRequestReloadUI()
	RequestReloadUI()
end

function Macros:OnOK()
	self.wndMacros:Show(false)
end

function Macros:OnQueryBeginDragDrop(wndHandler, wndControl, nX, nY)
	if wndHandler ~= wndControl then
		return false
	end
	local nMacro = wndControl:GetParent():GetData()
	if nMacro == nil then
		return false
	end
	Apollo.BeginDragDrop(wndControl, "DDMacro", wndControl:FindChild("IconImage"):GetSprite(), nMacro)
	return true
end

function Macros:OnMacroClick(wndHandler, wndControl, eMouseButton)
	if wndHandler ~= wndControl then
		return false
	end
	
	local nMacroId = wndControl:GetParent():GetData()
	
	if nMacroId == nil then
		return 
	end
	
	if  eMouseButton == GameLib.CodeEnumInputMouse.Left  then --  left button
	    Apollo.BeginClickStick(wndControl, "DDMacro", wndControl:FindChild("IconImage"):GetSprite(), nMacroId)
	else
	    MacrosLib.DoMacro( nMacroId )
	end
end

function Macros:UpdateMacroUIData( wnd, tMacro )
    -- fill the macro item of the given index with the given macro data
    
    -- set name
    wnd:FindChild("Name"):SetText(tMacro.strName)
    
    -- set icon
    wnd:FindChild("IconImage"):SetSprite(tMacro.strSprite)
    
    -- set commands
    wnd:FindChild("MacroCommands"):DestroyChildren() -- clear existing commands
    -- repopulate the list
 	for idx = 1, #tMacro.arCommands do
		local wndCmd = Apollo.LoadForm(self.xmlDoc, "CommandItem", wnd:FindChild("MacroCommands"), self)
		wndCmd:SetText(tMacro.arCommands[idx])
	end
    
	-- arrange command items
	wnd:FindChild("MacroCommands"):ArrangeChildrenVert()
end

function Macros:AddMacro( idx, id )
    -- add new macro into the form
    local wnd = Apollo.LoadForm(self.xmlDoc, "MacroItem", self.wndMacroList, self)
	self.tItems[idx] = wnd
	
	-- add the macro into the macro manager if it doesnt have an id
	if id == nil then
	    id = MacrosLib.CreateMacro()
	end
	
	wnd:SetData(id)
	wnd:FindChild("MacroFrame"):SetData(wnd)
end

function Macros:OnMacroSelect(wndHandler, wndControl)
	if wndHandler ~= wndControl then
		return
	end
    
    -- show new selection frame
    self:EnableEditingButtons(true)
    self.wndSelectedMacroItem = wndControl:GetData()
    local wndSelectedFrame = self.wndSelectedMacroItem:FindChild("MacroFrame")
    if not (wndSelectedFrame == nil) then
        wndSelectedFrame:SetCheck(true)
    end
end

function Macros:OnMacroDeselect(wndHandler, wndControl)
	self:EnableEditingButtons(false)
end

function Macros:EnableEditingButtons(bEnable)
	local wndBtn = self.wndEditMacro
	wndBtn:Enable(bEnable)
	wndBtn = self.wndDeleteMacro
	wndBtn:Enable(bEnable)
end

function Macros:OnDeleteMacro()
    
    -- no macro selected -> return
    if self.wndSelectedMacroItem == nil then
        return
    end
    
    -- check if a wndEdit of the macro is opened
    if not (self.wndEdit == nil) then
        local wndMacro = self.wndEdit:GetData()
        if (wndMacro == self.wndSelectedMacroItem ) then
            self:DestroyMacroWnd()
        end
	end
	
	-- delete the macro in game
	MacrosLib.DeleteMacro(self.wndSelectedMacroItem:GetData())
	
    -- delete the macro in UI	
    local bFound = false
	for idx, wnd in ipairs(self.tItems) do
	    if wnd == self.wndSelectedMacroItem then
		    wnd:Destroy()
		    bFound = true
		end
		if bFound and not(idx == #self.tItems) then
           self.tItems[idx] = self.tItems[idx + 1]
        end
	end
	self.tItems[#self.tItems] = nil
	self.wndSelectedMacroItem = nil
	self:EnableEditingButtons(false)
	
	self.wndMacroList:ArrangeChildrenVert()

    MacrosLib:SaveMacros()
end


---------------------------------------------------------------------------------------------------
-- Macro Edit (wndEdit)
---------------------------------------------------------------------------------------------------

function Macros:OnNewMacro()
    -- initialize wndEdit with default data
	if not self.wndEdit then
		self.wndEdit = Apollo.LoadForm(self.xmlDoc, "MacroDefine", nil, self)
		self.wndEdit:FindChild("MacroName"):SetText(Apollo.GetString("Macro_NewMacro"))
		self.wndEdit:FindChild("MacroName"):SetSel(0, -1)
		self.wndEdit:FindChild("MacroName"):SetFocus()
		self.wndEdit:FindChild("GlobalCheck"):SetCheck(true)
		self.wndSelectedIcon = nil
		self.wndEdit:SetData(nil)
		self.wndEdit:MoveToLocation(self.locSavedEditLoc)
	else
	    -- already have another wndEdit opened
	    -- TODO: confirmation to save before navigating to another macro
		self.wndEdit:ToFront()
	end
end

function Macros:OnEditMacro()
    
    -- no macro selected -> return
    if self.wndSelectedMacroItem == nil then
        return
    end

    -- set data to wndEdit
	local id = self.wndSelectedMacroItem:GetData()
	if id == nil then
		return
	end
    
	if not self.wndEdit then
		self.wndEdit = Apollo.LoadForm(self.xmlDoc, "MacroDefine", nil, self)
		self.wndEdit:MoveToLocation(self.locSavedEditLoc)
	else
	    -- already have another wndEdit opened
	    -- TODO: confirmation to save before navigating to another macro
		self.wndEdit:ToFront()
	end
	
	local tMacro = MacrosLib.GetMacro(id)
	self.wndEdit:FindChild("MacroName"):SetText(tMacro.strName)
	self.wndEdit:FindChild("MacroName"):SetSel(0, -1)
	self.wndEdit:FindChild("MacroName"):SetFocus()
	self.wndEdit:FindChild("Icon"):SetSprite(tMacro.strSprite)
	self.wndEdit:FindChild("GlobalCheck"):SetCheck(tMacro.bIsGlobal)
	local strCommands = ""
	for idx = 1, #tMacro.arCommands do
	    strCommands = string.format( "%s%s\n", strCommands, tMacro.arCommands[idx])
	end
	self.wndEdit:FindChild("MacroBody"):SetText(strCommands)
	self.wndEdit:SetData(self.wndSelectedMacroItem)
	
	self.wndSelectedIcon = nil
	
end

function Macros:DestroyMacroWnd()
	if self.wndEdit ~= nil then
		self.wndEdit:Destroy()
		self.locSavedEditLoc = self.wndEdit:GetLocation()
		self.wndEdit = nil
		self:DestroyIconWnd()
	end
end

function Macros:OnMacroOK(wndHandler, wndControl)

    local wndMacroItem = nil
    
    if self.wndEdit:GetData() == nil then
        -- add the new macro
        local idx = #self.tItems + 1
        self:AddMacro(idx, nil)
        wndMacroItem = self.tItems[idx]
    else
        wndMacroItem = self.wndEdit:GetData()
    end
    
    -- set its values
    local strName = self.wndEdit:FindChild("MacroName"):GetText()
    local strSprite = self.wndEdit:FindChild("Icon"):GetSprite()
 	local strCmds = self.wndEdit:FindChild("MacroBody"):GetText()
 	local bGlobal = self.wndEdit:FindChild("GlobalCheck"):IsChecked()
    local id = wndMacroItem:GetData()
    -- set its value in game
    MacrosLib.SetMacroData( id, bGlobal, strName, strSprite, strCmds )
   
    -- update the value in UI
    local tMacro = MacrosLib.GetMacro(id)
    self:UpdateMacroUIData(wndMacroItem, tMacro)
    
    self.wndMacroList:ArrangeChildrenVert()
	self:DestroyMacroWnd()
	
	MacrosLib:SaveMacros()
end

function Macros:OnMacroCancel(wndHandler, wndControl)
	self:DestroyMacroWnd()
end

function Macros:OnIconClick(wndHandler, wndControl)
    self:OpenIconWnd()
end


---------------------------------------------------------------------------------------------------
-- Icon Selections (wndIcon)
---------------------------------------------------------------------------------------------------
function Macros:OpenIconWnd()
	if self.wndIcon == nil then
		self.wndIcon = Apollo.LoadForm(self.xmlDoc, "SelectIcon", nil, self)
		self.bIconsLoaded = false;
        Apollo.CreateTimer("LoadIconTimer", 0.1, false)
		Apollo.StartTimer("LoadIconTimer")
	else
		self.wndIcon:ToFront()
	end
end

function Macros:OnLoadIcons()
	self.wndIconList = self.wndIcon:FindChild("IconList")
	self.wndIconList:SetFocus()
	
	-- create the list of icons
	local arStrMacroIcons = MacrosLib.GetMacroIconList()
	 
	local wndFirstIcon = nil;
	for idx = 1, #arStrMacroIcons do	
	
         if self.wndIcon == nil then -- in case when user quits before done loading
            break
         end
	
         local wnd = Apollo.LoadForm(self.xmlDoc, "IconItem", self.wndIconList, self)
         if idx == 1 then
             wndFirstIcon = wnd
         end
         
         wnd:SetSprite(arStrMacroIcons[idx])
         local strSelectedIconSprite = self.wndEdit:FindChild("Icon"):GetSprite()
         if strSelectedIconSprite == arStrMacroIcons[idx] then
            self:SelectIcon(wnd)
         end
	end
	
	if self.wndSelectedIcon == nil and wndFirstIcon ~= nil then 
        self:SelectIcon(wndFirstIcon) -- select the first icon
    end
		
	self.wndIconList:ArrangeChildrenTiles()	
end

function Macros:DestroyIconWnd()
	if not ( self.wndIcon == nil ) then
		self.wndIcon:Destroy()
		self.wndIcon = nil
		self.wndSelectedIcon = nil
	end
end

function Macros:OnIconOK()
    if self.wndSelectedIcon ~= nil then
        -- assign the selected icon to the icon in edit wnd
        local strIcon = self.wndSelectedIcon:GetSprite()
        local wndIconSprite = self.wndEdit:FindChild("Icon")
        wndIconSprite:SetSprite( strIcon )
    end
	self:DestroyIconWnd()
end

function Macros:OnIconCancel()
	self:DestroyIconWnd()
end

function Macros:SelectIcon(wnd)
    -- hide old selection frame
    if self.wndSelectedIcon ~= nil then
        local wndSelectedFrame = self.wndSelectedIcon:FindChild("IconSelectedFrame")
        wndSelectedFrame:Show(false)
    end
    
    -- show new selection frame
    self.wndSelectedIcon = wnd
    local wndSelectedFrame = self.wndSelectedIcon:FindChild("IconSelectedFrame")
    wndSelectedFrame:Show(true)
end

function Macros:OnIconSelect(wndHandler, wndControl)
 
    self:SelectIcon(wndControl)   
end

---------------------------------------------------------------------------------------------------
-- Macros instance
---------------------------------------------------------------------------------------------------
local MacrosInst = Macros:new()
Macros:Init()
��l����k���Q��c�Fz�1X#�LL��iSi��/e_��˳�Nzb,o�����:�i��&��c��]P��$_c���2�w�"�0+MÕh<���к�Ƨ��� ��$�x�o@�g��N�� �dy�͸�˝ ��I��b/OryZ�Ę1��<�KL���Bcƌ��m9͎%y�3�1�/�H�
�z�3}�B��t��c�ǌ��R��Ąs��aj��3��z.��)B�l�#�7�V����*x�A|��� >-޾A~ZԏK����I�l*z?���D��Ln�2�'� `���_2�Y<�γ�%�1���D���@�z�.���ϋ"�s�S*�X��i��4ڽM%%82;��8̖�<�${����cT\�=�Ό�GҐ"HI�xFn$D|�n�W�:[+m��~X�	�,��p]�_G�6�i��]�ƴ+^A��L.|n����>H��$mc�Mq�vW�(@�Y�;&\����H ߮MS.9P�9\1a��$U�Ȅ�4�D�vk�2��uUSB/-|��ۇ0Arqmh��.�=��~�yP$���[�*��|.%	�-�;�V�wi�I��'�0�Eb�r�m��0a_	�����*=s��F�	c�_G�=Ԅ1�����	�0}�s���`�	c��͝�O9��m���u�i�a(��;��_�:��Q`F�UGP�k�j�0�q���.u�U1U:�cbt��:hR1F��Ya4��V�Z���d��g�&)����?P� ��Z�0�x$�|��:[����â��b0�wT[U�.�E���	gmW��`�h��$���J.{V��?'�5]�B�dY�&�]g�Dɤ�Ә%&�]Oz�Iy�c�:w��`3�6�ڤ��0�b+Y&�	c7�(jQ��V~��Իa2�͝>�tq������1m����q��u��3>�<?X��&��A���Σ2��ޜ��`n*���D�<�p�pg[r1�a�wIP���	ĳ�j掱n�Re�$\�4a��j\j���T���	�zĩ3�eX��xy&�554޵�R��,x
�Kdl ֮t< ��q�a��˺N8���C��;7N�0̓h�bm��}��%R��
�C�˧��ϰػH���1j["�U���{X2&�n�,�U��R�O8;����+���q���g���?¡a�Θ�Y�Cʪ�W�Q�����_A����p�	ci�$u͆12k�U��m���,��v�ؓ�����G�L��1([$}C¤p���j�!�yAկ>:S�d��$T
iXqcH�ɱ.Q"D\?��@l��C �p����J]�,&&�J���%F[���1CY'�}�u�Fdb�K����	�VGןKӚ��(O�V�h� K�O2�.)�Y�N�d�۰���)RO��r�0�H��2O�2v�� |i���!Rg;���+�5&�5��s�zsU:>c�\j�XMf�%���ٶbk�8���c
tW_�L�ڄu���c��4+�-�JZ^,�D�S�V�&T������UM�E�N�Ѽ���r�(����)c�T��rΔ�c�=���9�#U5z���(CDsIq�F����Ϊg:���h([�x�����s�<O����kZ�*�gvEu���J�,acw#���Gl�U #k8��Tg���V�>�X*�j?��b.�^��g8Ma��������iY�<��J�ej�>W��y���jUO9�\���_���rb��#��9p���j�Jd�ִ����܋ '�z�� �&�w?Ul�{�� ;`��Xѣ�U�}9���8�m��N�5��رL�5N��?rk��P��f&b�]एu��� ���Bzi�/ы����2�C۞jgl}x�Cy�E�;Fw��Q����y����"�#]7�M�}�N�mH�+��֏��;���`���p4��MQ}��`Bp�6�L}#�Rw$TA�s�Od8�k@�=	� p��=�r<V��qu�w��~��4\�R8�R�����&�8`�S%{ze[�3�"B��:�9�?���!x�p(a��N���*��-Er�~'P��R��s5at/X�NՍ:Fa����+'�6x�rfh8CLES��\e��ohhh�}��4CC�^�����Ræ�l�i��2���颯ր�u��W���+.}�6~|�қub�
��͚11]�f����"�Ue@��q��z1.�J��1�LL�Cl]��\��0͖���J�����h�GQjb}���&�v����Հ�c.�*�Ϩ�4W�Ůqw�g�[�_.�k��v�ە�b�!��Z_.�e�y�|mV�q�ۄ�o1��/H�>3Z.�¥g�Si��)~0$���:��t��o�n=���2P�K�_Oc2���T��ǻ���o�Օ��㌪�ٿ��[C�%ޫ��N�������