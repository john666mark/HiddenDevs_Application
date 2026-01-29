local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Pooling_Class = require(ReplicatedStorage.Shared.Pooling_Class)
local Number_Format = require(ReplicatedStorage.Shared.Number_Format)
local Ore_Data_Module = require(ReplicatedStorage.Shared.Data.Item_Data.Ore_Data)
local Rarity_ColorModule = require(ReplicatedStorage.Shared.Rarity_ColorModule)

local Replication_events = ReplicatedStorage.Remote_events.Replication_events
local Ore_Spawn_event = Replication_events.Ore_Spawn_event
local Ore_Hit_event = Replication_events.Ore_Hit_event
local Ore_Destroy_event = Replication_events.Ore_Destroy_event

local Asset_Ore_Folder = ReplicatedStorage.Assets.Ore_Folder
local Ore_Information_BillboardGui = ReplicatedStorage.Assets.GUI_Folder.Gui_BluePrints.Ore_Information_BillboardGui
local Cart = ReplicatedStorage.Assets.Objekts.Cart
local Plots = workspace.Plots

local Ore = {}

Ore.__index = Ore
Ore.Item_pooling_Table = {} -- Pool for every OreModel
Ore.Ore_Plot_Class_Saving_Table = {
	[1] = {},
	[2] = {},
	[3] = {},
	[4] = {},
	[5] = {},
}

----------> [ Create Polling Dictionary ] <----------

local function Free_CallBack_Function(Objekt: Instance)
	Objekt.Parent = nil
end

local Ore_BillboardGui_Pool = Pooling_Class.new(
	Ore_Information_BillboardGui,
	15,
	function() end,
	function() end,
	Free_CallBack_Function
) -- Gui_Pool

local Cart_Pool = Pooling_Class.new(Cart, 5, function() end, function(objekt) end, Free_CallBack_Function) -- Cart_Pool

for Key in pairs(Ore_Data_Module) do
	local Ore_Model = Asset_Ore_Folder[Key]
	if not Ore_Model then
		return
	end

	local ItemPool = Pooling_Class.new(Ore_Model, 5, function() end, function() end, Free_CallBack_Function)  -- creates a pool for every Ore_Model, "5" is the number of clones that will be created at the start
	Ore.Item_pooling_Table[Key] = ItemPool
end

----------> [Helper_Functions] <----------

local function check_for_emptyTbale<T>(Table: { [any]: T }): boolean
	local isEmpty = true
	for _ in pairs(Table) do
		isEmpty = false
		break
	end

	return isEmpty
end

--- return the color from red to orange to green
local function Set_ProgressBar_ColorSeq(Helth_Perc: number): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHSV(math.clamp(Helth_Perc / 3, 0, 0.333), 0.25, 1)),
		ColorSequenceKeypoint.new(1, Color3.fromHSV(math.clamp(Helth_Perc / 3, 0, 0.333), 1, 1)),
	})
end

local function Position_Tween(Model: Model, Target: Vector3, TweenTime: number, EasingStyle: Enum.EasingStyle)
	if not Model or not Model.PrimaryPart then
		return
	end

	local PrimaryPart = Model.PrimaryPart
	local tweeninfo1 = TweenInfo.new(TweenTime, EasingStyle)

	local Tween1 = TweenService:Create(
		PrimaryPart,
		tweeninfo1,
		{ CFrame = CFrame.new(Target.X, Target.Y + (PrimaryPart.Size.Y / 2), Target.Z) }
	) :: Tween
	Tween1:Play()
	Tween1.Completed:Wait()
end

----------> [Main_Script] <----------

function Ore.new(
	ID: string,
	Name: string,
	Plot_Number: number,
	Lane_number: number,
	First_Tween_Time: number, -- this is randomised from the server
	Mutations: { [number]: string }
)
	local self = setmetatable({
		_ID = ID,
		_Name = Name or "Stone Ore1",
		_Plot_Number = Plot_Number,
		_Lane_number = Lane_number,
		_First_Tween_Time = First_Tween_Time,
		_Mutations = Mutations or {},
	}, Ore)

	self._Item_pool = self.Item_pooling_Table[self._Name]
	local oreData = Ore_Data_Module[self._Name]
	self._Rarity = oreData.Rarity
	self._OreModel = self._Item_pool:Get() :: Model

	self._Max_Hp = oreData.Hp
	self._Current_HP = oreData.Hp
	self._Speed = oreData.Speed
	self._Ore_BillboardGui = Ore_BillboardGui_Pool:Get() :: BillboardGui?
	self._EZV_Table = {}
	self._Ore_Cart = Cart_Pool:Get() :: Model

	-- setup --
	if self._Ore_BillboardGui then
		self:Setup_Ore_BillboardGui()
	end

	-- Rarity attribute for coloring
	if self._OreModel and self._Rarity then
		self._OreModel:SetAttribute("Rarity", self._Rarity)
	end

	-- Refrence to Plot_Table
	self.Ore_Plot_Class_Saving_Table[self._Plot_Number][self._ID] = self

	return self
end

--- Sets the right values up for the Ore_BillboardGui
function Ore:Setup_Ore_BillboardGui()
	if not self._Ore_BillboardGui or not self._OreModel then
		self._Ore_BillboardGui = Ore_BillboardGui_Pool:Get()
	end
	self._Ore_BillboardGui.Parent = self._OreModel.PrimaryPart

	local List_Container = self._Ore_BillboardGui.List_Container
	local ProgressBar = self._Ore_BillboardGui.HealthBar.ProgressBar :: Frame
	local ProgressBar_UIGr = ProgressBar:FindFirstChild("UIGradient") :: UIGradient
	ProgressBar.Size = UDim2.fromScale(1, 1)
	ProgressBar_UIGr.Color = Set_ProgressBar_ColorSeq(1)
	self._Ore_BillboardGui.StudsOffset = Vector3.new(0, self._OreModel.PrimaryPart.Size.Y + 1, 0)

	-- TextLabels --
	local Health_TextLabel = self._Ore_BillboardGui.Health_TextLabel
	local Name_TextLabel = List_Container.Name_TextLabel
	local Rarity_TextLabel = List_Container.Rarity_TextLabel
	local Mutation_TextLabel = List_Container.Mutation_TextLabel

	local formated_MaxHp = Number_Format:formatNumber(self._Max_Hp)

	Health_TextLabel.Text = tostring(formated_MaxHp .. " / " .. formated_MaxHp)
	Name_TextLabel.Text = self._Name
	Rarity_TextLabel.Text = self._Rarity

	if #self._Mutations ~= 0 then
		Mutation_TextLabel.Visible = true
		Mutation_TextLabel.Text = table.concat(self._Mutations, "-")
	else
		Mutation_TextLabel.Visible = false -- this textlabel is in a ui listlayout ... 
	end

	-- colloring
	local Rarity_ColorSeq = Rarity_ColorModule:Get_ColorSequence_By_Rarity(self._Rarity)
	local Mutation_ColorSeq = Rarity_ColorModule:Get_ColorSequence_By_Mutation(self._Mutations[1])

	local EZV_REF1 =
		Rarity_ColorModule:CreateApply_Gradient_Or_EZVeffect_With_Refrence(Rarity_TextLabel, Rarity_ColorSeq)
	local EZV_REF2 =
		Rarity_ColorModule:CreateApply_Gradient_Or_EZVeffect_With_Refrence(Mutation_TextLabel, Mutation_ColorSeq)

	table.insert(self._EZV_Table, EZV_REF1)
	table.insert(self._EZV_Table, EZV_REF2)
end

function Ore:Update_Billboard_Gui()
	if not self._Ore_BillboardGui then
		return
	end

	local Health_TextLabel = self._Ore_BillboardGui.Health_TextLabel
	local ProgressBar = self._Ore_BillboardGui.HealthBar.ProgressBar :: Frame
	local ProgressBar_UIGr = ProgressBar:FindFirstChild("UIGradient") :: UIGradient

	if not Health_TextLabel or not ProgressBar or not ProgressBar_UIGr then
		return
	end

	local formated_Current_Health = Number_Format:formatNumber(self._Current_HP)
	Health_TextLabel.Text = tostring(formated_Current_Health .. " / " .. self._Max_Hp)

	local ratio = self._Current_HP / self._Max_Hp
	ProgressBar.Size = UDim2.fromScale(ratio, 1)
	ProgressBar_UIGr.Color = Set_ProgressBar_ColorSeq(ratio)
end

--- this will spawn the Ore on the Chosen Lane of the OwnersPlot
function Ore:spawn()
	local Plot = Plots[self._Plot_Number]
	local Lane_Paths = Plot.Lane_Paths
	local Spawned_Ores = Plot.Spawned_Ores
	local Lane_Objekt = Lane_Paths[self._Lane_number]

	if not Plot or not self._OreModel or not self._Ore_Cart then
		return
	end

	local OrePart = self._Ore_Cart:FindFirstChild("OrePart")
	local Cart_Ore_Connection = self._Ore_Cart:FindFirstChild("Cart_Ore_Connection") :: WeldConstraint

	if not OrePart or not Cart_Ore_Connection then
		return
	end

	local lane_Path1 = Lane_Objekt:WaitForChild("1")
	local lane_Path2 = Lane_Objekt:WaitForChild("2")
	local lane_Path3 = Lane_Objekt:WaitForChild("3")

	self._OreModel.Parent = self._Ore_Cart
	self._Ore_Cart.Parent = Spawned_Ores
	self._OreModel.PrimaryPart.Anchored = false
	self._Ore_Cart:PivotTo(lane_Path1.CFrame)
	self._OreModel:PivotTo(OrePart.CFrame)
	Cart_Ore_Connection.Part1 = self._OreModel.PrimaryPart

	Position_Tween(self._Ore_Cart, lane_Path2.CFrame, self._First_Tween_Time, Enum.EasingStyle.Cubic)

	if self._Ore_Cart then -- check for destoy when player leves
		self:FreeCartTo_ItemPool(Spawned_Ores)
	end

	Position_Tween(
		self._OreModel,
		lane_Path2.CFrame * CFrame.new(0, -lane_Path2.Size.Y / 2, 0),
		0.5,
		Enum.EasingStyle.Bounce
	)

	Position_Tween(
		self._OreModel,
		lane_Path3.CFrame * CFrame.new(0, -lane_Path2.Size.Y / 2, 0),
		self._Speed,
		Enum.EasingStyle.Linear
	)

	if check_for_emptyTbale(self) then
		return
	end

	self:Destroy()
end

--- Displays Damage to the Ore
function Ore:Dmage_Ore(Dmage: number): ()
	if not self._Ore_BillboardGui then
		return
	end

	local Health_TextLabel = self._Ore_BillboardGui.Health_TextLabel
	local ProgressBar = self._Ore_BillboardGui.HealthBar.ProgressBar :: Frame
	local ProgressBar_UIGr = ProgressBar:FindFirstChild("UIGradient") :: UIGradient

	if not Health_TextLabel or not ProgressBar or not ProgressBar_UIGr then
		return
	end

	self._Current_HP = math.clamp(self._Current_HP - Dmage, 0, self._Max_Hp)

	local formated_Current_Health = Number_Format:formatNumber(self._Current_HP)
	Health_TextLabel.Text = tostring(formated_Current_Health .. " / " .. self._Max_Hp)

	local ratio = self._Current_HP / self._Max_Hp
	ProgressBar.Size = UDim2.fromScale(ratio, 1)
	ProgressBar_UIGr.Color = Set_ProgressBar_ColorSeq(ratio)
end

function Ore:Clear_EZV_table()
	if not self._EZV_Table then
		return
	end

	for _, Connection in pairs(self._EZV_Table) do
		if Connection:Destroy() then
			Connection:Destroy()
		end
	end
	table.clear(self._EZV_Table)
end

--- Send the Ore Back to its ItemPool
function Ore:FreeOreTo_ItemPool()
	if not self._OreModel then
		return
	end

	self._OreModel.PrimaryPart.Anchored = true
	self._OreModel.Parent = nil
	self._OreModel = nil

	if self._Ore_BillboardGui then
		self:FreeBillboardGuiTo_ItemPool()
	end

	self._Item_pool:free(self._OreModel)
end

--- send The _BillboardGui Back to Its Pool
function Ore:FreeBillboardGuiTo_ItemPool()
	if not self._Ore_BillboardGui then
		return
	end

	self:Clear_EZV_table()

	self._Ore_BillboardGui.Parent = nil
	self._Ore_BillboardGui = nil
	Ore_BillboardGui_Pool:free(self._Ore_BillboardGui)
end

--- send The OreCart Back to Its Pool
function Ore:FreeCartTo_ItemPool(OreModel_Parent: Instance)
	if not self._Ore_Cart then
		return
	end

	if self._OreModel then
		self._OreModel.Parent = OreModel_Parent
		self._OreModel.PrimaryPart.Anchored = true
	end

	local Cart_Ore_Connection = self._Ore_Cart:FindFirstChild("Cart_Ore_Connection") :: WeldConstraint
	Cart_Ore_Connection.Part1 = nil

	Cart_Pool:free(self._Ore_Cart)
	self._Ore_Cart = nil
end

function Ore:Remove_Ore_Index_From_PlotTable()
	self.Ore_Plot_Class_Saving_Table[self._Plot_Number][self._ID] = nil
end

function Ore:Get_Ore_Index_From_PlotTable(Plot_Number: number, Ore_ID: string)
	return self.Ore_Plot_Class_Saving_Table[Plot_Number][Ore_ID]
end

function Ore:Destroy()
	self:Remove_Ore_Index_From_PlotTable()
	self:FreeBillboardGuiTo_ItemPool()
	self:FreeOreTo_ItemPool()
	self:FreeCartTo_ItemPool()

	for key in pairs(self) do
		self[key] = nil
	end

	setmetatable(self, nil)
end

--/=( Types )=\--		-->       will be moved later

type Event_OreSpawnData = {
	ID: string,
	Name: string,
	Plot: number,
	Lane: number,
	First_Tween_Time: number,
	Mutations: { [number]: string },
}

type Event_OreHitData = { ID: string, Plot: number, HP: number }
type Event_OreDestroyData = { ID: string, Plot: number }

-- RemoteEvents --

Ore_Spawn_event.OnClientEvent:Connect(function(OreSpawn_Data: Event_OreSpawnData)
	local new_Ore = Ore.new(
		OreSpawn_Data.ID,
		OreSpawn_Data.Name,
		OreSpawn_Data.Plot,
		OreSpawn_Data.Lane,
		OreSpawn_Data.First_Tween_Time,
		OreSpawn_Data.Mutations
	)
	new_Ore:spawn()
end)

Ore_Hit_event.OnClientEvent:Connect(function(OreHit_Data: Event_OreHitData)
	local Hited_Ore = Ore:Get_Ore_Index_From_PlotTable(OreHit_Data.Plot, OreHit_Data.ID)
	if not Hited_Ore then
		return
	end

	Hited_Ore._Current_HP = OreHit_Data.HP

	Hited_Ore:Update_Billboard_Gui()
end)

Ore_Destroy_event.OnClientEvent:Connect(function(OreDestroy_Data: Event_OreDestroyData)
	local Hited_Ore = Ore:Get_Ore_Index_From_PlotTable(OreDestroy_Data.Plot, OreDestroy_Data.ID)
	if not Hited_Ore then
		return
	end

	Hited_Ore:Destroy()
end)

return Ore
