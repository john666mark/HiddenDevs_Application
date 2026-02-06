local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Item_Data_Folder = ReplicatedStorage.Shared.Data.Item_Data
local OreData = require(Item_Data_Folder.Ore_Data)
local MinerData = require(Item_Data_Folder.Miner_Data)
local DataManager = require(ServerScriptService.ProfileStoreFolder.Data.DataManager)
local Tool_Creation_Module = require(ServerScriptService.Server_Modules.Servises.Tool_Creation_Module)
local Pooling_Class = require(ReplicatedStorage.Shared.Pooling_Class)
local Number_Format = require(ReplicatedStorage.Shared.Number_Format)
local Rarity_ColorModule = require(ReplicatedStorage.Shared.Rarity_ColorModule)

local Station_BillboardGui_BluePrint = ReplicatedStorage.Assets.GUI_Folder.Gui_BluePrints.Station_BillboardGui

----------> [ Pooling Classes ] <----------

local function On_Free(Objekt: Instance)
	Objekt.Parent = nil
end
local Station_BillboardGui_POOL = Pooling_Class.new(
	Station_BillboardGui_BluePrint,
	1,
	function() end,
	function() end,
	On_Free
)

--------<--/=( Calculations )=\-->--------

local function Calculate_Ore_Bulk(Station_level: number): number?
	return math.floor(1.2 * (1.05 ^ Station_level))
end

local function Calculate_Upgrade_Price(Station_level: number): number?
	return math.floor(750 * (1.12 ^ Station_level))
end

local function CalculateMoney_From_Fragments(Fragment_amount: number, Price_Per_Fragment: number): number?
	if not Fragment_amount or not Price_Per_Fragment then
		return
	end

	return Fragment_amount * Price_Per_Fragment
end

local function Calculate_Max_Stach_amount(Station_level: number): number?
	return 300 + math.floor(150 * (Station_level ^ 1.08))
end

local function Calculate_Money_Per_Sec(
	Ore_Bulk_Amount: number,
	Price_Per_Fragment: number,
	Ore_bulk_Tick: number
): number?
	if not Ore_Bulk_Amount or not Price_Per_Fragment or not Ore_bulk_Tick then
		return
	end

	local Ore_Bulk_Value = CalculateMoney_From_Fragments(Ore_Bulk_Amount, Price_Per_Fragment)

	return Ore_Bulk_Value / Ore_bulk_Tick
end

----------> [ Helper Functions ] <----------

local function Get_SurfaceGui_Containers(Ui_Model: Model): (Frame?, Frame?)
	local UI_Part = Ui_Model:FindFirstChild("UI_Part")
	local UI_Part2 = Ui_Model:FindFirstChild("UI_Part2")

	if not UI_Part or not UI_Part2 then
		return
	end

	local Button_Sreen = UI_Part:FindFirstChild("SurfaceGui")
	local Stat_Sreen = UI_Part2:FindFirstChild("SurfaceGui")

	if not Button_Sreen or not Stat_Sreen then
		return
	end

	local Button_Container = Button_Sreen:FindFirstChild("Container")
	local Stat_Container = Stat_Sreen:FindFirstChild("Container")

	return Button_Container, Stat_Container
end

local function Get_Backpack_From_Player(Player: Player)
	if not Player then
		return
	end

	return Player.Backpack
end

local function Parent_Tool_To_Player(Player: Player, Tool: Tool)
	if not Player or not Tool then
		return
	end

	local BackPack = Get_Backpack_From_Player(Player)
	if not BackPack then
		return
	end

	local Character = Player.Character

	-- If no character, always put tool in backpack
	if not Character then
		Tool.Parent = BackPack
		return
	end

	-- Check if the player is currently holding a tool
	local EquippedTool = Character:FindFirstChildOfClass("Tool")

	if EquippedTool then
		-- Player is holding something → put new tool in backpack
		Tool.Parent = BackPack
	else
		-- Player is not holding anything → equip new tool
		Tool.Parent = Character
	end
end

local function Get_Ore_Model_Out_Of_Character(Character: Model): (Model?, string?)
	if not Character then
		return
	end

	local Tool = Character:FindFirstChildOfClass("Tool")
	if not Tool or Tool:GetAttribute("Item_Type") ~= "Ores" then
		warn("No Tool Or Wrong Item_type")
		return
	end

	warn("Tool Found")
	return Tool:FindFirstChildWhichIsA("Model"), Tool:GetAttribute("ID")
end

local function Ore_Positioning(Ore_Model: Model, Ore_SpawnPart: BasePart): ()
	if not Ore_Model or not Ore_SpawnPart then
		return
	end
	-- setup Model and delete tool
	local Tool = Ore_Model.Parent
	local PrimaryPart = Ore_Model.PrimaryPart :: BasePart?
	Ore_Model.Parent = Ore_SpawnPart
	PrimaryPart.Anchored = true
	Tool:Destroy()

	-- resetting the angels
	PrimaryPart.CFrame = CFrame.new(PrimaryPart.Position)

	-- change position to the Orestation
	local new_x = (PrimaryPart.Size.X / 2) - (Ore_SpawnPart.Size.X / 2)
	if new_x < 0 then
		new_x = 0
	end

	local TP_CFrame = Ore_SpawnPart.CFrame * CFrame.new(-new_x, -Ore_SpawnPart.Size.Y / 2, 0)
	Ore_Model:PivotTo(TP_CFrame)
end

----------> [Main_Script] <----------

local OreStation = {}

OreStation.__index = OreStation

function OreStation.new(Player: Player, Plot_Number: number, Station_Model: Model, Ore_Model: Model?, Ore_ID: string?)
	if not Player or not Plot_Number or not Station_Model then
		return nil
	end

	local self = setmetatable({}, OreStation)

	-- basic station variables
	self._Owner = Player
	self._Profile = DataManager:Profile(Player)
	self._Plot_Number = Plot_Number
	self._Station_Model = Station_Model
	self._Station_Level = 1
	self._Stach_Amount_Max = Calculate_Max_Stach_amount(self._Station_Level)
	self._Ore_Bulk = Calculate_Ore_Bulk(self._Station_Level)
	self._Upgrade_Price = Calculate_Upgrade_Price(self._Station_Level)

	-- collecting_touch_event
	self._Touch_Collection_event = nil :: RBXScriptConnection?
	self._Toucheble = true

	-- EZV connections
	self._Station_BillboardGui_Connections = {}
	self._Station_BillboardGui = nil

	-- Parts
	self._Ore_SpawnPart = nil :: BasePart?
	self._Miner_SpawnPart = nil :: BasePart?

	-- Ore data
	self._Ore_Name = Ore_Model and Ore_Model.Name or nil
	self._Ore_ID = Ore_ID or nil
	self._Ore_Model = Ore_Model or nil
	self._Ore_Mutations = {}
	self._Ore_Data = nil
	self._Ore_Rarity = nil
	self._Ore_fragment_Price = nil

	self._Ore_Fragments_Count = 0

	self:Get_SpawnParts_From_Station_Model()
	self:SetUp_ore(Ore_Model, Ore_ID)
	self:SetUp_Billboard_Gui()
	self:Update_SurfaceGuis()
	self:Create_Collecting_touch_event()

	return self
end

function OreStation:Collect_Ore_Fragments()
	if not self._Ore_ID then
		return
	end
	if not self._Ore_Fragments_Count then
		return
	end
	if not self._Station_Model then
		return
	end
	self:Update_Profile()
	DataManager:Transfer_OreFragments_To_Inventory(self._Profile, tonumber(self._Station_Model.Name), self._Ore_ID)

	self._Ore_Fragments_Count = 0
end

function OreStation:Create_Collecting_touch_event(): ()
	if not self._Ore_SpawnPart then
		return
	end
	if not self._Owner then
		return
	end

	self:Disconnect_Touch_Collection_event()

	self._Touch_Collection_event = self._Ore_SpawnPart.Touched:Connect(function(hit: BasePart)
		if not self._Toucheble then
			return
		end

		local Character = hit.Parent
		if not Character then
			return
		end

		local Player = game.Players:GetPlayerFromCharacter(Character)
		if not Player then
			return
		end

		if Player ~= self._Owner then
			return
		end
		self._Toucheble = false

		self:Collect_Ore_Fragments()
		self:Update_Billboard_Gui()

		task.wait(0.75)
		self._Toucheble = true
	end)
end

function OreStation:Disconnect_Touch_Collection_event(): ()
	if not self._Touch_Collection_event then
		return
	end
	self._Touch_Collection_event:Disconnect()
	self._Touch_Collection_event = nil
end

function OreStation:Get_Fragments()
	-- Validate required fields
	if not self._Owner then
		return
	end
	if not self._Ore_Bulk then
		return
	end
	if not self._Ore_fragment_Price then
		return
	end
	if not self._Ore_ID then
		return
	end

	self:Update_Profile()

	local currentCount = self._Ore_Fragments_Count or 0
	local bulk = self._Ore_Bulk or 0
	local maxAmount = self._Stach_Amount_Max or 0

	local newStackAmount = currentCount + bulk
	local clampedAmount = math.clamp(newStackAmount, 0, maxAmount)

	self._Ore_Fragments_Count = clampedAmount

	DataManager:Update_Station_FragmentCount(self._Profile, tonumber(self._Station_Model.Name), clampedAmount)

	self:Update_Billboard_Gui()

	return self._Ore_Fragments_Count
end

function OreStation:Update_Profile()
	if not self._Owner then
		return
	end

	if not self._Profile then
		self._Profile = DataManager:Profile(self._Owner)
	end
end

function OreStation:Update_SurfaceGuis()
	if not self._Station_Model or not self._Station_Level then
		return
	end

	local Ui_Model = self._Station_Model:FindFirstChild("Ui_Model") :: Model
	if not Ui_Model then
		return
	end

	local Button_Container, Stat_Container = Get_SurfaceGui_Containers(Ui_Model)
	if not Button_Container or not Stat_Container then
		return
	end

	local TextLabel_Folder = Button_Container:FindFirstChild("Plot_Button")
		:FindFirstChild("Container")
		:FindFirstChild("TextLabel_Folder") :: TextLabel
	if not TextLabel_Folder then
		return
	end

	local Level_Textlabel = TextLabel_Folder:FindFirstChild("Level")
	local Upgrade_Cost_Textlabel = TextLabel_Folder:FindFirstChild("Money")
	local Ore_Bulk_Textlabel = Stat_Container:FindFirstChild("Fragments")
		:FindFirstChild("TextLabel_Folder")
		:FindFirstChild("TextLabel") :: TextLabel
	local Inventory_Space_Textlabel = Stat_Container:FindFirstChild("Inventory")
		:FindFirstChild("TextLabel_Folder")
		:FindFirstChild("TextLabel") :: TextLabel

	if not Ore_Bulk_Textlabel or not Inventory_Space_Textlabel or not Level_Textlabel or not Upgrade_Cost_Textlabel then
		return
	end

	-----< Update all Textes >-----

	local NEXT_Ore_Bulk = Calculate_Ore_Bulk(self._Station_Level + 1)
	local NEXT_Satch_max_amount = Calculate_Max_Stach_amount(self._Station_Level + 1)
	local Upgrade_price = Number_Format:formatNumber(self._Upgrade_Price)
	local Satch_max_amount = Number_Format:formatInteger(self._Stach_Amount_Max)
	local NEXT_Ore_Bulk_Text = Number_Format:formatInteger(NEXT_Ore_Bulk)
	local Ore_Bulk_Text = Number_Format:formatInteger(self._Ore_Bulk)
	local NEXT_Satch_max_amount_Text = Number_Format:formatInteger(NEXT_Satch_max_amount)

	Upgrade_Cost_Textlabel.Text = Upgrade_price .. " $"

	Level_Textlabel.Text = "Lvl " .. self._Station_Level .. " -> " .. "Lvl " .. self._Station_Level + 1

	Ore_Bulk_Textlabel.Text = Ore_Bulk_Text .. " -> " .. NEXT_Ore_Bulk_Text

	Inventory_Space_Textlabel.Text = Satch_max_amount .. " -> " .. NEXT_Satch_max_amount_Text
end

function OreStation:Upgrade_Station(Player)
	-- make sure the requested player is also the owner of the Plot
	if not Player or not self._Owner or Player ~= self._Owner then
		return
	end

	if not self._Station_Level then
		return
	end

	self:Update_Profile()

	-- if not station_Data then station is not bought
	local Station_Level = DataManager:Upgrade_Station(self._Profile, tonumber(self._Station_Model.Name))
	if not Station_Level then
		return
	end

	self._Station_Level = Station_Level
	self._Stach_Amount_Max = Calculate_Max_Stach_amount(self._Station_Level)
	self._Ore_Bulk = Calculate_Ore_Bulk(self._Station_Level)
	self._Upgrade_Price = Calculate_Upgrade_Price(self._Station_Level)

	self:Update_SurfaceGuis()
	self:Update_Billboard_Gui()
end

function OreStation:Update_Billboard_Gui(): (TextLabel?, TextLabel?)
	if not self._Ore_Model or not self._Ore_ID or not self._Station_BillboardGui then
		return
	end

	local Container = self._Station_BillboardGui:FindFirstChild("Container")
	if not Container then
		return
	end

	-- Get all TextLabes
	local Money_TextLabel = Container:FindFirstChild("Money_TextLabel") :: TextLabel
	local Mutation_TextLabel = Container:FindFirstChild("Mutation_TextLabel") :: TextLabel
	local Name_TextLabel = Container:FindFirstChild("Name_TextLabel") :: TextLabel
	local Stach_TextLabel = Container:FindFirstChild("Stach_TextLabel") :: TextLabel

	if not Money_TextLabel or not Mutation_TextLabel or not Name_TextLabel or not Stach_TextLabel then
		return
	end

	-----< Update all Textes >-----
	local Owned_Frgmnets = Number_Format:formatInteger(self._Ore_Fragments_Count)
	local Max_stach_amount = Number_Format:formatInteger(self._Stach_Amount_Max)

	Name_TextLabel.Text = self._Ore_Name
	Stach_TextLabel.Text = Owned_Frgmnets .. "/" .. Max_stach_amount

	-- "$" Current_Money_output "(" Money/second " " MoneyRebith Multiplier ")"

	--<--/=( Calculations )=\-->--
	local Current_Money_output = CalculateMoney_From_Fragments(self._Ore_Fragments_Count, self._Ore_fragment_Price)
	local MoneyPsec = Calculate_Money_Per_Sec(self._Ore_Bulk, self._Ore_fragment_Price, 5)

	local Text_Current_Money_output = Number_Format:formatNumber(Current_Money_output)
	local Text_MoneyPsec = Number_Format:formatNumber(MoneyPsec)

	Money_TextLabel.Text = "$" .. Text_Current_Money_output .. " ($" .. Text_MoneyPsec .. "/s " .. "x1" .. ")"

	if #self._Ore_Mutations ~= 0 then
		Mutation_TextLabel.Text = table.concat(self._Ore_Mutations, "-")
		Mutation_TextLabel.Visible = true
	else
		Mutation_TextLabel.Visible = false
	end

	return Name_TextLabel, Mutation_TextLabel
end

function OreStation:SetUp_Billboard_Gui(): ()
	if not self._Ore_Model or not self._Ore_ID then
		return
	end

	-- Get a the billboardgui
	if not self._Station_BillboardGui then
		self._Station_BillboardGui = Station_BillboardGui_POOL:Get()
	end

	-- Update_Textes and give textlabes back that needs to be colored
	local Name_TextLabel, Mutation_TextLabel = self:Update_Billboard_Gui()
	if not Name_TextLabel or not Mutation_TextLabel then
		return
	end

	-----< GUI Coloring >-----
	local Name_Collor_Connnection = Rarity_ColorModule:CreateApply_Gradient_Or_EZVeffect_With_Refrence(
		Name_TextLabel,
		Rarity_ColorModule:Get_ColorSequence_By_Rarity(self._Ore_Rarity)
	)

	local Mutation_Color_Connnection
	if #self._Ore_Mutations == 1 then
		Mutation_Color_Connnection = Rarity_ColorModule:CreateApply_Gradient_Or_EZVeffect_With_Refrence(
			Mutation_TextLabel,
			Rarity_ColorModule:Get_ColorSequence_By_Mutation(self._Ore_Mutations[1])
		)
	end

	if Mutation_Color_Connnection then
		self._Station_BillboardGui_Connections["Mutation_TextLabel_Color"] = Name_Collor_Connnection
	end

	if Name_Collor_Connnection then
		self._Station_BillboardGui_Connections["Name_TextLabel_Color"] = Name_Collor_Connnection
	end

	self._Station_BillboardGui.Parent = self._Ore_Model.PrimaryPart
end

function OreStation:Remove_BillboardGui()
	if not self._Station_BillboardGui then
		return
	end

	-- Remove EZV Connections
	for _, EZV_Ref in pairs(self._Station_BillboardGui_Connections) do
		EZV_Ref:Destroy()
	end
	self._Station_BillboardGui_Connections = {}

	-- Return BillboardGui to Pool
	Station_BillboardGui_POOL:free(self._Station_BillboardGui)
	self._Station_BillboardGui = nil
end

function OreStation:Get_SpawnParts_From_Station_Model(): (BasePart?, BasePart?)
	if not self._Station_Model then
		return
	end

	self._Ore_SpawnPart = self._Station_Model:FindFirstChild("Ore_Spawner").PrimaryPart
	self._Miner_SpawnPart = self._Station_Model:FindFirstChild("Miner_Spawner").PrimaryPart

	assert(self._Ore_SpawnPart, "No Ore_SpawnPart Found")
	assert(self._Miner_SpawnPart, "No Miner_SpawnPart Found")

	return self._Ore_SpawnPart, self._Miner_SpawnPart
end

function OreStation:SetUp_ore(Ore_Model: Model, Ore_ID: string): ()
	if not Ore_Model or not Ore_ID then
		return
	end

	local Ore_Player_Data = DataManager:Get_Miner_Or_Ore_Data(self._Profile, Ore_ID, "Ores")
	if not Ore_Player_Data then
		return
	end

	self._Ore_Model = Ore_Model
	self._Ore_ID = Ore_ID

	-- From Ore Data --
	self._Ore_Data = OreData[Ore_Model.Name]
	assert(self._Ore_Data, "NO OreData Found")
	self._Ore_Rarity = self._Ore_Data.Rarity
	self._Ore_fragment_Price = self._Ore_Data.fragment_Price

	-- From Player Data --
	self._Ore_Name = Ore_Player_Data.Class_Name or Ore_Model.Name
	self._Ore_Mutations = Ore_Player_Data.Mutations or {}
	self._Ore_Fragments_Count = Ore_Player_Data.Fragments_Count or 0

	Ore_Positioning(Ore_Model, self._Ore_SpawnPart)
	self:SetUp_Billboard_Gui()
end

function OreStation:TakeOreModel_From_Charackter(Player: Player): Model?
	-- check if there is allready a ore equiped
	if self._Ore_Model or self._Ore_ID then
		return
	end

	-- Validate owner and ensure the correct player is interacting
	if not self._Owner or self._Owner ~= Player then
		return
	end

	self:Update_Profile()

	-- Ensure the character exists
	local Character = self._Owner.Character
	if not Character then
		return
	end

	-- Try to extract the ore model from the Tool out of the character -- Validate Ore ID attribute
	local Ore_Model, Ore_ID = Get_Ore_Model_Out_Of_Character(Character)
	if not Ore_Model or not Ore_ID then
		return
	end

	-- Final setup for the ore
	self:SetUp_ore(Ore_Model, Ore_ID)
	DataManager:Add_PlaceOre_Data(self._Profile, self._Ore_ID, tonumber(self._Station_Model.Name))

	return Ore_Model
end

function OreStation:Remove_Ore_From_Station(Player)
	if not self._Ore_Model or not self._Ore_ID then
		return
	end

	-- Validate owner and ensure the correct player is interacting
	if not self._Owner or self._Owner ~= Player then
		return
	end

	-- make sure profile is loaded
	self:Update_Profile()

	-- Tool Attributes
	local Attributetable = {
		["ID"] = self._Ore_ID,
		["Rarity"] = self._Ore_Rarity,
		["Item_Type"] = "Ores",
		["Item_Name"] = self._Ore_Name,
		["Mutation"] = self._Ore_Mutations[1] or nil,
	}
	self:Remove_BillboardGui()

	local Tool =
		Tool_Creation_Module:Create_Tool_From_BluePrint(self._Ore_Model, self._Ore_Name, "Ores", Attributetable)
	if not Tool then
		return
	end
	Parent_Tool_To_Player(Player, Tool)

	-- update-Data
	self:Collect_Ore_Fragments()
	DataManager:Remove_Placed_Data(self._Profile, "Ores", self._Ore_ID)

	-- set to nil
	self._Ore_Name = nil
	self._Ore_ID = nil
	self._Ore_Model = nil
	self._Ore_Mutations = nil
	self._Ore_Data = nil
	self._Ore_Rarity = nil
	self._Ore_fragment_Price = nil
	self._Ore_Fragments_Count = 0
end

function OreStation:Destroy()
	-- additional Pooling and destroing functions
	self:Remove_BillboardGui()
	for key in pairs(self) do
		self[key] = nil
	end
	setmetatable(self, nil)
end

return OreStation

