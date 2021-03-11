AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

function ENT:Setup()
	self.txchannels = {} -- tx data
	self.txwatts = 0 -- tx power
	if WireAddon then
		self.Inputs = Wire_CreateInputs(self, {"On", "BaseMHz", "TxEnable", "TxWatts", "Ch1", "Ch2", "Ch3", "Ch4", "PromiscuousMode"})
		self.Outputs = Wire_CreateOutputs(self, {"Ch1", "Ch1_HasSignal", "Ch1_dBm", "Ch2", "Ch2_HasSignal", "Ch2_dBm", "Ch3", "Ch3_HasSignal", "Ch3_dBm", "Ch4", "Ch4_HasSignal", "Ch4_dBm", "Promiscuous_Spectrum [ARRAY]"})
		-- transmitters consume energy. 1 energy unit = 1 watt per second, 4 channels = 4 energy units (4 watts) per second
		if CAF and CAF.GetAddon then CAF.GetAddon("Resource Distribution").AddResource(self, "energy", 0) end
	else
		print("Wire Directional Radio Kit requires the 'Wire' addon.\n")
	end
end

function ENT:OnDuplicated()
	self:Setup()
end

-- Returns the background noise at this location in decibels relative to one milliwatt
function ENT:GetBgNoise()
	local firenoise = 0
	for k, v in pairs(ents.FindInSphere(self:GetPos(), 1000)) do
		if v:IsOnFire() then
			firenoise = firenoise + 1000/self:GetPos():Distance(v:GetPos())
		end
	end
	return math.Rand(-1,1) + firenoise
end

-- this is called whenever a wire input changes value
function ENT:TriggerInput(iname, value)
	if iname == "TxWatts" then
		local m = GetConVarNumber("sv_wdrk_max_tx_power")
		if value > m then
			self.txwattsW = m
		elseif value <= 0 then
			self.txwattsW = 0
		else
			self.txwattsW = value
		end
	elseif iname == "On" and value == 0 then
		self.txwatts = 0
		Wire_TriggerOutput(self,"Promiscuous_Spectrum",{})
		for i=1,4 do
			Wire_TriggerOutput(self.Entity, "Ch" .. tostring(i), 0)
			Wire_TriggerOutput(self.Entity, "Ch" .. tostring(i) .. "_HasSignal", 0)
			Wire_TriggerOutput(self.Entity, "Ch" .. tostring(i) .. "_dBm", 0)
		end
	elseif iname == "TxEnable" then
		self.txwatts = 0
		Wire_TriggerOutput(self,"Promiscuous_Spectrum",{})
		for i=1,4 do
			Wire_TriggerOutput(self.Entity, "Ch" .. tostring(i), 0)
			Wire_TriggerOutput(self.Entity, "Ch" .. tostring(i) .. "_HasSignal", 0)
			Wire_TriggerOutput(self.Entity, "Ch" .. tostring(i) .. "_dBm", 0)
		end
	elseif iname == "PromiscuousMode" and value == 0 then
		Wire_TriggerOutput(self,"Promiscuous_Spectrum",{})
	elseif iname == "BaseMHz" then
		-- someone has changed the base frequency, update the frequencies
		-- of all the channels to be based on the new value
		self.txchannels = {}
		self.txchannels[self.Inputs.BaseMHz.Value + 2.5] = self.Inputs.Ch1.Value
		self.txchannels[self.Inputs.BaseMHz.Value + 7.5] = self.Inputs.Ch2.Value
		self.txchannels[self.Inputs.BaseMHz.Value + 12.5] = self.Inputs.Ch3.Value
		self.txchannels[self.Inputs.BaseMHz.Value + 17.5] = self.Inputs.Ch4.Value
	elseif iname == "Ch1" then
		self.txchannels[self.Inputs.BaseMHz.Value + 2.5] = value
	elseif iname == "Ch2" then
		self.txchannels[self.Inputs.BaseMHz.Value + 7.5] = value
	elseif iname == "Ch3" then
		self.txchannels[self.Inputs.BaseMHz.Value + 12.5] = value
	elseif iname == "Ch4" then
		self.txchannels[self.Inputs.BaseMHz.Value + 17.5] = value
	end
end

function ENT:Think()
	if not self.Inputs then self:Setup() end
	if (self.Inputs.On.Value == 0) then return end
	
	if (self.Inputs.TxEnable.Value != 0) then
		if CAF and CAF.GetAddon then
			local amt = CAF.GetAddon("Resource Distribution").GetResourceAmount(self, "energy")
			if amt < (self.txwattsW * 4) then
				CAF.GetAddon("Resource Distribution").ConsumeResource(self, "energy", amt)
				self.txwatts = (amt/(self.txwattsW * 4))
			else
				CAF.GetAddon("Resource Distribution").ConsumeResource(self, "energy", (self.txwatts * 4))
				self.txwatts = self.txwattsW
			end
		else
			self.txwatts = self.txwattsW
		end
		if GetConVarNumber("sv_wdrk_damage_enabled") and self.txwatts >= GetConVarNumber("sv_wdrk_damage_watt_threshold") then
			local e = ents.FindInCone(self:GetPos(), self:GetForward(), self.txwatts/5, self.beamWidth)	-- This will never work, as garry broke findincone long long ago...
			for _, v in ipairs(e) do
				if v:IsPlayer() then v:TakeDamage(self.txwatts / 500 + (100/self:GetPos():Distance(v:GetPos())), self) end
			end
		end
		self:NextThink( CurTime() + 1 )
		return true
	end
	-- Find all antennas on the map
	local ants = ents.FindByClass("ra_*")
	
	--spectrum
	local spectrum = {}

	local noise = self:GetBgNoise()

	local scale = GetConVarNumber("sv_wdrk_scale")
	scale = scale * scale

	local sense = GetConVarNumber("sv_wdrk_rx_sensitivity_threshold")

	-- If we found antennas
	if ants and #ants > 0 then		
		for _, v in ipairs(ants) do
			if v.txwatts <= 0 then continue end
			if self.Inputs.PromiscuousMode.Value == 0 then
				if (self.Inputs.BaseMHz.Value <= v.Inputs.BaseMHz.Value - 20) or (self.Inputs.BaseMHz.Value >= v.Inputs.BaseMHz.Value + 20) then continue end
			end

			-- Loss due to angle offset
			local angleloss = 0
			-- Loss due to polarity skew
			local skewloss = 0
		
			local dist = self:GetPos():DistToSqr(v:GetPos()) * scale
			local dBm = (math.log10((10^((self.gain + (math.log10(self.txwatts)*10))/10)) / (4 * math.pi * dist)) * 10) + 30
			
			-- Find the vector from the receiver to the transmitter and vice-versa
			local vecToTx = v:GetPos() - self:GetPos()
			local vecFromTx = self:GetPos() - v:GetPos()

			-- Normalize the above to obtain the direction both ways
			local normVectToTx = vecToTx:GetNormalized()
			local normVectFromTx = vecFromTx:GetNormalized()

			-- Find the direction of the receiver and transmitter
			local myAngle = self:GetForward()
			local txAngle = v:GetForward()

			-- Find the loss due to polarity skew
			-- If both antennas are not cross polarity, determine the loss due to skew
			if self.pol ~= 0 and v.pol ~= 0 then
				-- Both are the same polarity by default
				local skew = 0
				-- One vertical, one horizontal
				if self.pol ~= v.pol then skew = 1.5707963267949 end
				
				skewloss = math.abs(math.sin(math.rad(v:GetAngles().r) - math.rad(self:GetAngles().r) + skew) * 20)
			end
			
			local onedir = math.abs(math.acos(normVectToTx:DotProduct(myAngle)))
			local otherdir = math.abs(math.acos(txAngle:DotProduct(normVectFromTx)))
			
			-- If this transmitter is operational, within our field of vision, and we are within its beam
			if not (math.deg(onedir) <= (self.beamWidth/2.0) and math.deg(otherdir) <= (v.beamWidth/2.0)) then continue end
			
			if self.beamWidth ~= 360 and v.beamWidth == 360 then
				angleloss = (onedir) * 30
			elseif self.beamWidth == 360 and v.beamWidth ~= 360 then
				angleloss = (otherdir) * 30
			elseif self.beamWidth ~= 360 and v.beamWidth ~= 360 then
				angleloss = (onedir + otherdir) * 30
			end
			
			-- Calculate the received signal strength (strength + self.gain)
			dBm = dBm + self.gain - angleloss - skewloss
			
			for freq, signal in pairs(v.txchannels) do

				if self.Inputs.PromiscuousMode.Value == 0 then
					-- Allow for signal loss due to misaligned tuner frequency
					local driftloss = 0 -- dB
					local choffset = freq - self.Inputs.BaseMHz.Value
					if choffset >= 0 and choffset < 5 then
						driftloss = 10 * math.abs(2.5 - choffset)
					elseif choffset >= 5 and choffset < 10 then
						driftloss = 10 * math.abs(7.5 - choffset)
					elseif choffset >= 10 and choffset < 15 then
						driftloss = 10 * math.abs(12.5 - choffset)
					elseif choffset >= 15 and choffset < 20 then
						driftloss = 10 * math.abs(17.5 - choffset)
					end
					dBm = dBm - driftloss
				end
				
				dBm = math.Clamp(dBm,sense + noise,math.huge)

				if spectrum[freq] == nil then
					spectrum[freq] = {}
				else
					table.insert(spectrum[freq],{sig = signal, dbm = dBm, txmittr = v})
				end
			end
		end

		for freq,_ in pairs(spectrum) do
			table.SortByMember(spectrum[freq],"dbm")
		end

		if self.Inputs.PromiscuousMode.Value != 0 then
			Wire_TriggerOutput(self,"Promiscuous_Spectrum",spectrum)
			self:NextThink( CurTime() )
			return true
		end

		-- The set of channels that have detected a signal
		local setset = {false, false, false, false}
		for freq,arr in pairs(spectrum) do
			-- Initialize the signal and the strength
			local sig, dBm = dBm = arr[1].dbm, arr[1].sig

			local signalLock = 1
			if dBm <= sense + noise then signalLock = 0 end
			if signalLock == 0 then continue end

			-- If the received signal after noise is less than the receiver's sensitivity threshold, then the data received is just random noise
			--local modif = (dBm/(sense + noise))^10
			--sig = sig + math.Rand(0.49*modif,-0.49*modif)

			local receiveCh = 0

			if freq >= self.Inputs.BaseMHz.Value and freq < self.Inputs.BaseMHz.Value + 5 then
				receiveCh = 1
			elseif freq >= self.Inputs.BaseMHz.Value + 5 and freq < self.Inputs.BaseMHz.Value + 10 then
				receiveCh = 2
			elseif freq >= self.Inputs.BaseMHz.Value + 10 and freq < self.Inputs.BaseMHz.Value + 15 then
				receiveCh = 3
			elseif freq >= self.Inputs.BaseMHz.Value + 15 and freq < self.Inputs.BaseMHz.Value + 20 then
				receiveCh = 4
			end

			if receiveCh ~= 0 then
				local c = tostring(receiveCh)
				Wire_TriggerOutput(self, "Ch" .. c, sig)
				Wire_TriggerOutput(self, "Ch" .. c .. "_HasSignal", signalLock)
				Wire_TriggerOutput(self, "Ch" .. c .. "_dBm", dBm)
				setset[receiveCh] = true
			end
		end

		-- set the remaining channels randomly
		for i=1,4 do
			if not setset[i] then
				Wire_TriggerOutput(self, "Ch" .. tostring(i), 0)
				Wire_TriggerOutput(self, "Ch" .. tostring(i) .. "_HasSignal", 0)
				Wire_TriggerOutput(self, "Ch" .. tostring(i) .. "_dBm", sense + noise)
			end
		end
	end
	self:NextThink( CurTime() )
	return true
end