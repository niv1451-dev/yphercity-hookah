-- Display names, so garages, spawn menus and the vehicle HUD show "One Bike"
-- instead of NULL. The labels match gameName / vehicleMakeName in data/vehicles.meta.
CreateThread(function()
    AddTextEntry('ONEBIKE', 'One Bike')
    AddTextEntry('ONEBIKE_MK', 'One Bike')
end)
