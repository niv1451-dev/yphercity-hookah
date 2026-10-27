-- Eating / drinking animation, started only after the server confirmed that the
-- item is on this player's table (and removed one from it).

Consume = {
    active = false,
}

RegisterNetEvent('cyphercity-hookah:client:consume', function(productId, profileId)
    if Consume.active then return end
    local profile = Config.ConsumeProfiles[profileId]
    if not profile then return end
    Consume.active = true

    local ped = PlayerPedId()
    local prop
    if profile.prop then
        local hash = ClientUtil.LoadModel(profile.prop)
        if hash then
            local coords = GetEntityCoords(ped)
            prop = CreateObject(hash, coords.x, coords.y, coords.z + 0.2, true, true, false)
            SetModelAsNoLongerNeeded(hash)
            local offset = profile.offset or vec3(0.0, 0.0, 0.0)
            local rotation = profile.rotation or vec3(0.0, 0.0, 0.0)
            AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, profile.bone or 18905),
                offset.x, offset.y, offset.z, rotation.x, rotation.y, rotation.z,
                true, true, false, true, 1, true)
        end
    end

    local duration = profile.duration or 4000
    local played = ClientUtil.PlayAnim(ped, profile.dict, profile.clip, duration, profile.flag or 49)
    Wait(duration)
    if played then StopAnimTask(ped, profile.dict, profile.clip, 1.0) end
    if prop and DoesEntityExist(prop) then
        DetachEntity(prop, true, true)
        DeleteEntity(prop)
    end
    Consume.active = false
    if Seat.current and not IsPedUsingScenario(ped, 'PROP_HUMAN_SEAT_CHAIR_MP_PLAYER') then Seat.Resume() end
end)
