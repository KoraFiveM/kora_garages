QBGaragesSchema = {
    {
        name = 'qbgarages_property_garages',
        columns = {
            { name = 'id', type = 'varchar(50)' },
            { name = 'provider', type = 'varchar(64)' },
            { name = 'definition', type = 'longtext' },
        },
        primary = { 'id' },
    },
}

---Whether any connected player's ped currently occupies `vehicle`, optionally
---ignoring `excludeSrc` (e.g. the player who is in the middle of storing it).
function isVehicleOccupied(vehicle, excludeSrc)
    for _, player in ipairs(GetPlayers()) do
        if tonumber(player) ~= excludeSrc and GetVehiclePedIsIn(GetPlayerPed(player), false) == vehicle then
            return true
        end
    end

    return false
end
