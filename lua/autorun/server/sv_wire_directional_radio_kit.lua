WIRE_DIRECTIONAL_RADIO_KIT = true -- Use this in your own Lua code to check for the presence of the Wire Directional Radio Kit

CreateConVar("sv_wdrk_scale", 180,FCVAR_ARCHIVE ) -- Map Scale Adjustment factor
CreateConVar("sv_wdrk_max_tx_power", 1000,FCVAR_ARCHIVE ) -- Maximum transmit power in Watts
CreateConVar("sv_wdrk_rx_sensitivity_threshold", -90,FCVAR_ARCHIVE ) -- Receive sensitivity in dbm
CreateConVar("sv_wdrk_damage_enabled", 0,FCVAR_ARCHIVE ) -- damage players with high watts enabled?
CreateConVar("sv_wdrk_damage_watt_threshold", 200,FCVAR_ARCHIVE ) -- damage players watt threshold.