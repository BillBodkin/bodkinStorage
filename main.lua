args = {...}

local itemsStored = {}--cache file for items stored
local emptySlots = {}--cache file for empty slots
local craftingRecipies = {}--defines crafting recipies / furnace recipies.

function PrintTable(t)
    if t == nil then
        print("Table is nil")
        return
    end
    textutils.slowPrint(textutils.serialize(t))
end

function TableLength(t)
    local toRet = 0
    for ktl, vtl in pairs(t) do
        toRet = toRet + 1
    end
    return toRet
end

function ReadToTable(file)
	local fileHandle = fs.open (file, 'r')
	local table = textutils.unserialize(fileHandle.readAll())
	fileHandle.close()
	return table
end

function WriteToFile(file, tab)
	local fileHandle = fs.open(file, "w")
	fileHandle.write(textutils.serialize(tab))
	fileHandle.close()
end

function SplitString(inputstr, sep)
	if sep == nil then
		sep = "%s"
	end
	local t={}
	for str in string.gmatch(inputstr, sep) do
		table.insert(t, str)
	end
	return t
end

local maxStackSizes = ReadToTable("maxStackSizes.lua")
local itemOresDict = ReadToTable("itemOres.lua")

function SaveCache()
    WriteToFile("itemsStored.lua", itemsStored)
    WriteToFile("emptySlots.lua", emptySlots)
    WriteToFile("maxStackSizes.lua", maxStackSizes)
    WriteToFile("itemOres.lua", itemOresDict)
end

local toSend = {}

function Send(m)
    toSend[tostring(math.random(0, 99999))] = m
end

function Msg(m, icon)
    if m ~= "idle" then
        print(m)
    end
    Send({
        ["type"] = "message",
        ["message"] = m,
        ["icon"] = icon,
    })
end

function MsgNow(m, icon)
    print(m)
    rednet.broadcast({--rednet is the ingame networking, most variables can be sent, including tables.
        ["type"] = "message",
        ["message"] = m,
        ["icon"] = icon,--icons can be added to messages, which will be displayed on the client with the message
    }, "bodkinStorage_1.0")-- "bodkinStorage_1.0" is the channel it is sent on
end

local modem = peripheral.wrap("front")--this is the block infront of the computer, essentially connecting it to the network giving it access to whats on it.
local modemNameLocal = modem.getNameLocal()--name of self on the network, used for moving items to and from self.
local chestBankPrefix = "minecraft:chest_"--items on the network have names / IDs, all the chests start with this string, followed by a number.
rednet.open("right")--turn on wireless modem
local workstations = {--table of workstations, like furnaces and other machines that could be added using other mods.
    ["furnace"] = {--supports multiple furnases.
        ["minecraft:furnace_0"] = true,--ID, avaliable - if currently being used to process something, will goto false.
    }
}
local inChest = peripheral.wrap("minecraft:shulker_box_0")--input box
local outChests = {
    ["main"] = peripheral.wrap("minecraft:shulker_box_1")--output box
}

local craftingChestPrefix = "minecraft:dropper_"--these are the items on the right of the image, used to hold crafts if needing to do another craft before doing this one.
local craftingChestCount = 3
local craftingChestIndex = 1
local craftingChestInUse = {}

local minItemIndex = 1
local minItems = ReadToTable("minItems.lua")--min items are items the system should always try to have x ammount of ready, as I might use them regually and want some crafted at all times.
local maxItems = ReadToTable("maxItems.lua")--if items are put into the system when there is already too much of it in the system (defined in this file), it will get thrown out.
local autoOutChests = ReadToTable("autoOutChests.lua")--used to define items that should always be in an output chest, possaibly to be used by another computer. (can be multiple output boxes / chests defined)

function SetItemsStoredSlot(itemMeta, chestID, slotNo)--updates cache file(s)
    chestID = tostring(chestID)
    slotNo = tostring(slotNo)
    if itemMeta == nil then--saying said slot is now empty
        if emptySlots[chestID] == nil then--if no empty slots table made for chest
            emptySlots[chestID] = {}--empty table for chest slots
        end
        emptySlots[chestID][slotNo] = true--set to empty
    else--if item in chest
        if itemsStored[itemMeta.name] == nil then--if no varients defined for item
            itemsStored[itemMeta.name] = {}--empty table for item varients
        end
        local addedToTable = false
        for varientID, varient in pairs(itemsStored[itemMeta.name]) do--will go through item
            if varient.damage == itemMeta.damage and varient.nbtHash == itemMeta.nbtHash then
                if varient.locations[chestID] == nil then
                    varient.locations[chestID] = {}
                end
                varient.locations[chestID][slotNo] = itemMeta.count
                addedToTable = true
                break
            end
        end
        if addedToTable == false then
            if itemMeta.ores == nil then
                itemMeta.ores = {}
            end
            if itemMeta.enchantments == nil then
                itemMeta.enchantments = {}
            end
            table.insert(itemsStored[itemMeta.name], {
                ores = itemMeta.ores,
                damage = itemMeta.damage,
                nbtHash = itemMeta.nbtHash,
                enchantments = itemMeta.enchantments,
                locations = {
                    [chestID] = {
                        [slotNo] = itemMeta.count
                    }
                }
            })
        end
    end
end

function UpdateItemsStored()
    MsgNow("Updating cache of items stored...")
    local pNames = peripheral.getNames()
    local chestPoolCount = TableLength(pNames)
    local chestPoolCounter = 0
    for _, pName in pairs(pNames) do
        if string.find(pName, chestBankPrefix) ~= nil then--if name includes the chest bank prefix, meaning its one of the chests for storage.
            local chestID = string.gsub(pName, chestBankPrefix, "")
            local chestPer = peripheral.wrap(pName)
            for slotNo = 1, 9 * 6 do
                local itemMeta = chestPer.getItemMeta(slotNo)
                SetItemsStoredSlot(itemMeta, chestID, slotNo)
            end
        end
        chestPoolCounter = chestPoolCounter + 1
        MsgNow("Cached " .. tostring(chestPoolCounter) .. " / " .. tostring(chestPoolCount))
    end
    --PrintTable(itemsStored)
    --PrintTable(emptySlots)
    SaveCache()
    MsgNow("Items cached.")
end

function GetItemLocations(itemType, itemOres, itemDamage, itemNbtHash, itemEnchantments)--any can be wildcards * and itemEnchantments can also be "none"
    local toReturn1 = {}--just locations

    function CheckItemType(itemType2)
        for varientID, varient in pairs(itemsStored[itemType2]) do
            if (tostring(varient.damage) == tostring(itemDamage) or itemDamage == "*") and (varient.nbtHash == itemNbtHash or itemNbtHash == "*") and (itemOres == "*" or varient.ores[itemOres] == true) then
                local canAdd = true
                for k, v in pairs(varient.enchantments) do
                    if itemEnchantments == "*" then
                        --do nothing, still can add
                    elseif (itemEnchantments ~= "none" and itemEnchantments[v.name] ~= nil) then
                        if v.level < itemEnchantments[v.name].minLevel or v.level > itemEnchantments[v.name].maxLevel then
                            canAdd = false
                        end
                    else
                        if itemEnchantments[v.name] == nil and itemEnchantments["other"] ~= "any" then
                            canAdd = false
                        end
                    end
                end

                if canAdd then
                    for k3, v3 in pairs(varient.locations) do
                        if toReturn1[k3] == nil then
                            toReturn1[k3] = {}
                        end
                        for k4, v4 in pairs(v3) do
                            toReturn1[k3][k4] = {
                                ["count"] = v4,
                                ["itemType"] = itemType2,
                                ["varientID"] = varientID
                            }
                        end
                    end
                end
            end
        end
    end

    if itemType == "*" then
        for k1, v1 in pairs(itemsStored) do--if the item type is a wildcard, go through all items and see if the other parameters match.
            CheckItemType(k1)
        end
    else
        if itemsStored[itemType] ~= nil then--if the item type is sepcified, only go through items of that type.
            CheckItemType(itemType)
        end
    end

    return toReturn1
end

function CountItems(itemType, itemOres, itemDamage, itemNbtHash, itemEnchantments)
    local itemLocations = GetItemLocations(itemType, itemOres, itemDamage, itemNbtHash, itemEnchantments)
    local toRet = 0
    for chest, chestSlots in pairs(itemLocations) do
        for chestSlot, chestSlotCount in pairs(chestSlots) do
            toRet = toRet + chestSlotCount["count"]
        end
    end
    return toRet
end

function GetMaxStackSize(itemType)--not all items can be stacked to 64, this will check against a file of known values to check. If the value is not known it will default to 64. Even if its not 64 the program will work, but might take slightly longer.
    if maxStackSizes[itemType] ~= nil then
        return maxStackSizes[itemType]
    end
    return 64
end

function StoreItem(from, slot)
    local meta = from.getItemMeta(slot)--gets metadata of item in slot "slot" from chest "from"
    if meta == nil then--no item in slot.
        return 0
    end
    maxStackSizes[meta.name] = meta.maxCount--update file with known max stack sizes.
    --prepare data
    if meta.ores == nil then
        meta.ores = {}
    end
    if meta.enchantments == nil then
        meta.enchantments = {}
    end
    local metaNbtHash2 = meta.nbtHash
    if metaNbtHash2 == nil then
        metaNbtHash2 = ""
    end
    for oreKey, ore in pairs(meta.ores) do--update the oreDict file with what ores this item has assigned to it.
        if itemOresDict[oreKey] == nil then
            itemOresDict[oreKey] = {}
        end
        itemOresDict[oreKey][meta.name .. "|" .. meta.damage .. "|" .. metaNbtHash2] = {
            itemName = meta.name,
            itemDamage = meta.damage,
            itemNbtHash = meta.nbtHash
        }
    end
    --PrintTable(meta)
    local toTransfer = meta.count
    local itemLocations = GetItemLocations(meta.name, "*", meta.damage, meta.nbtHash, "*")--get slots with items of same type that could mabye stack with.
    for chest, chestSlots in pairs(itemLocations) do
        for chestSlot, chestSlotCount in pairs(chestSlots) do
            if chestSlotCount["count"] < GetMaxStackSize(meta.name) then
                local transfered = from.pushItems(chestBankPrefix .. chest, slot, 64, tonumber(chestSlot))
                toTransfer = toTransfer - transfered
                itemsStored[meta.name][chestSlotCount["varientID"]].locations[chest][chestSlot] = chestSlotCount["count"] + transfered
                if toTransfer <= 0 then
                    SaveCache()
                    return 0
                end
            end
        end
    end

    for chest, chestSlots in pairs(emptySlots) do--then if there are any items left needed to store, put them in empty slots.
        for chestSlot, slotEmpty in pairs(chestSlots) do
            if slotEmpty then
                local transfered = from.pushItems(chestBankPrefix .. chest, slot, 64, tonumber(chestSlot))
                if transfered > 0 then
                    local itemMeta = {
                        name = meta.name,
                        count = transfered,
                        ores = meta.ores,
                        damage = meta.damage,
                        nbtHash = meta.nbtHash,
                        enchantments = meta.enchantments,
                    }
                    SetItemsStoredSlot(itemMeta, chest, chestSlot)
                    emptySlots[chest][chestSlot] = nil
                    toTransfer = toTransfer - transfered
                else
                    Msg("Was unable to transfer items to empty slot! " .. tostring(toTransfer) ..  " items remain.")
                end
                if toTransfer <= 0 then
                    SaveCache()
                    return 0
                end
            end
        end
    end

    SaveCache()
    return toTransfer
end

function CraftItems(itemType, itemCount, itemDamage, itemNbtHash, recurcive)
    Msg("Will try to craft items: " .. itemType, {itemType, itemDamage})
    local craftedTotal = 0
    while itemCount > 0 do
        local crafted, notCraftedReason, missingMat = CraftItem(itemType, itemDamage, itemNbtHash, recurcive)
        if crafted == 0 then
            return craftedTotal, notCraftedReason, missingMat
        else
            itemCount = itemCount - crafted
            craftedTotal = craftedTotal + crafted
        end
    end
    return craftedTotal, nil, nil
end

function CraftItem(itemType, itemDamage, itemNbtHash, recurcive)
    if itemNbtHash == nil then
        itemNbtHash = ""
    end
    if itemDamage == nil then
        itemDamage = 0
    end
    Msg("Will try to craft item: " .. itemType .. " " .. tostring(itemDamage) .. " " .. itemNbtHash, {itemType, itemDamage})
    local recipieName = itemType .. "|" .. tostring(itemDamage) .. "|" .. itemNbtHash
    --find recipe from string name if wildcards were used.
    if itemDamage == "*" or itemNbtHash == "*" then
        for rk, rv in pairs(craftingRecipies) do
            local rkParts = SplitString(rk, "([^|]+)")
            if rkParts[3] == nil then
                rkParts[3] = ""
            end
            if itemType == rkParts[1] and (tostring(itemDamage) == rkParts[2] or itemDamage == "*") and (itemNbtHash == rkParts[3] or itemNbtHash == "*") then
                recipieName = rk
            end
        end
    end
    if craftingRecipies[recipieName] == nil then
        Msg("Cannot craft " .. recipieName .. " as no recipie has been defined for it", {itemType, itemDamage})
        return 0, "noRecipie", nil
    end
    local itemsMissing = {}
    --try all avaliable recipies for making this item.
    for recipieIndex, recipie in pairs(craftingRecipies[recipieName]) do
        local crafted, notCraftedReason, missingMat = CraftItemFromRecipe(recipie, recurcive, recipieName)
        if crafted > 0 then
            return crafted, nil, nil
        elseif notCraftedReason == "craftingFailure" then
            return 0, "craftingFailure", nil
        else
            table.insert(itemsMissing, missingMat)
        end
    end
    if #itemsMissing == 0 then
        return 0, "noWorkstationAvaliable", nil
    else
        return 0, "notEnoughMaterials", itemsMissing
    end
end

function CraftItemFromRecipe(recipie, recurcive, recipieName)
    while craftingChestInUse[craftingChestIndex] == true do
        craftingChestIndex = craftingChestIndex + 1
        if craftingChestIndex > craftingChestCount then
            craftingChestIndex = 1
        end
        os.sleep(0.01)
    end
    local craftingChestIndexUsing = craftingChestIndex
    craftingChestInUse[craftingChestIndexUsing] = true
    local craftingChest = peripheral.wrap(craftingChestPrefix .. tostring(craftingChestIndexUsing))--the crafting chest is used to hold all the items that will be used for this craft.
    local recipieParts = SplitString(recipieName, "([^|]+)")
    Msg("Will try to craft item from recipie : " .. tostring(recipie), recipieParts)
    --PrintTable(recipie)
    function CheckHaveMaterials()--find out if any items required for the recipe are missing, and try to make those first (if recurcive is true).
        local returnCode = -1
        for materialKey, material in pairs(recipie.materials) do
            local requiredCount = 0
            for inputSlot, slotMaterial in pairs(recipie.inputSlots) do
                if slotMaterial.material == materialKey then
                    requiredCount = requiredCount + slotMaterial.count
                end
            end
            local materialCountInStorage = CountItems(material.itemType, material.itemOres, material.itemDamage, material.itemNbtHash, material.itemEnchantments)
            Msg("Need " .. tostring(requiredCount) .. " have " .. tostring(materialCountInStorage) .. " of " .. material.itemType .. " " .. material.itemOres .. " " .. tostring(material.itemDamage))
            if recurcive then
                local notGot = RetriveItemOrCraft(craftingChest, "*", material.itemType, requiredCount, material.itemOres, material.itemDamage, material.itemNbtHash, material.itemEnchantments, "rc")
                StoreAllInChest(inChest)--not for crafting, just to stop it overflowing as new items are put into the in chest during this process
                if notGot ~= nil and notGot > 0 then
                    return 0, "notEnoughMaterials", material
                end
            end
            --[[
            if materialCountInStorage < requiredCount then
                if recurcive and (material.itemEnchantments == "*" or material.itemEnchantments == "none") then
                    local toPreCraft = requiredCount - materialCountInStorage
                    if material.itemType == "*" and material.itemOres ~= "*" then
                        if itemOresDict[material.itemOres] == nil then
                            Msg("notEnoughMaterials (1) " .. material.itemOres, {material.itemType, material.itemDamage, material.itemNbtHash, material.itemOres})
                            return 0, "notEnoughMaterials", material
                        end
                        for itemOresDictLookupKey, itemOresDictLookupValue in pairs(itemOresDict[material.itemOres]) do
                            if (itemOresDictLookupValue.itemDamage == material.itemDamage or material.itemDamage == "*") and (itemOresDictLookupValue.itemNbtHash == material.itemNbtHash or material.itemNbtHash == "*") then
                                local craftedMat, notCraftedReason, missingMat = CraftItems(itemOresDictLookupValue.itemName, toPreCraft, itemOresDictLookupValue.itemDamage, itemOresDictLookupValue.itemNbtHash, true)
                                if craftedMat == 0 and notCraftedReason == "craftingFailure" then
                                    Msg("Crafting failure! (1)", recipieParts)
                                    return 0, "craftingFailure", nil
                                else
                                    toPreCraft = toPreCraft - craftedMat
                                end
                                StoreAllInChest(inChest)
                                returnCode = -2
                                if toPreCraft <= 0 then
                                    break
                                end
                            end
                        end
                        if toPreCraft > 0 then
                            Msg("notEnoughMaterials (2)", {material.itemType, material.itemDamage, material.itemNbtHash, material.itemOres})
                            return 0, "notEnoughMaterials", material
                        end
                    else
                        local craftedMat, notCraftedReason, missingMat = CraftItems(material.itemType, toPreCraft, material.itemDamage, material.itemNbtHash, true)
                        if craftedMat == 0 then
                            Msg("Coudn't craft material (8)", {material.itemType, material.itemDamage, material.itemNbtHash, material.itemOres})
                            return 0, notCraftedReason, missingMat
                        end
                        StoreAllInChest(inChest)
                        returnCode = -2
                    end
                    --if gets to here, material has been crafted
                else
                    Msg("notEnoughMaterials (3)", {material.itemType, material.itemDamage, material.itemNbtHash, material.itemOres})
                    return 0, "notEnoughMaterials", material
                end
            end
            ]]--
        end

        return returnCode, "", nil
    end

    --local cc1 = -2
    --while cc1 == -2 do
        local cc, ncr, ncm = CheckHaveMaterials()
        if cc == 0 then
            craftingChestInUse[craftingChestIndexUsing] = false
            return cc, ncr, ncm
        end
    --    cc1 = cc
    --end

    craftingChestInUse[craftingChestIndexUsing] = false
    StoreAllInChest(craftingChest)

    --if gets to here, all materials that are required are avaliable
    local workstation = nil
    if recipie.workstation == "bench" then
        workstation = {
            name = "turtle_0",--craft items in self, using interal storage / crafting grid
            inUse = false
        }
    else
        for wk, wv in pairs(workstations[recipie.workstation]) do
            if wv then
                workstations[recipie.workstation][wk] = false
                workstation = {
                    name = wk,
                    peripheral = peripheral.wrap(wk)
                }
                break
            end
        end
        if workstation == nil then
            return 0, "noWorkstationAvaliable", nil
        end
    end
    for inputSlot, slotMaterial in pairs(recipie.inputSlots) do
        local itemsNotRetrived = RetriveItem(
            workstation.name,
            inputSlot,
            recipie.materials[slotMaterial.material].itemType,
            slotMaterial.count,
            recipie.materials[slotMaterial.material].itemOres,
            recipie.materials[slotMaterial.material].itemDamage,
            recipie.materials[slotMaterial.material].itemNbtHash,
            recipie.materials[slotMaterial.material].itemEnchantments
        )
        if itemsNotRetrived > 0 then
            return 0, "craftingFailure"
        end
    end

    if recipie.workstation == "bench" then
        turtle.craft()
        for i = 1, 16 do--move items from computer to in chest.
            if slot == "*" then
                if inChest.pullItems(modemNameLocal, i, 64) ~= recipie.count then
                    --Msg("Crafting failure! (2)")
                end
            else
                if inChest.pullItems(modemNameLocal, i, 64, slot) ~= recipie.count then
                    --Msg("Crafting failure! (2.1)")
                end
            end
        end
    else
        Msg("Waiting for item to craft...", recipieParts)
        while true do
            local itemMeta = workstation.peripheral.getItemMeta(recipie.outputSlot)
            if itemMeta ~= nil and itemMeta.count >= recipie.count then
                break
            end
            --Msg("Waiting for item to craft...")
            --TaskQueueLoopCycle()--for now, till added more workbenches
            os.sleep(0.1)
        end
        for i = 1, workstation.peripheral.size() do
            inChest.pullItems(workstation.name, i, 64)
        end
        workstations[recipie.workstation][workstation.name] = true
    end

    return recipie.count, nil, nil
end

function RetriveItemOrCraft(to, slot, itemType, itemCount, itemOres, itemDamage, itemNbtHash, itemEnchantments, mode)
    if mode == nil or mode == "cr" then
        mode = "rc"
    end
    local itemsNotRetrived = itemCount
    if mode == "rc" or mode == "r" then
        itemsNotRetrived = RetriveItem(to, slot, itemType, itemCount, itemOres, itemDamage, itemNbtHash, itemEnchantments)
    end
    if itemsNotRetrived > 0 and (mode == "rc" or mode == "c") then
        if itemType == "*" and itemOres ~= "*" then
            if itemOresDict[itemOres] == nil then
                return itemsNotRetrived
            end
            local toCraft = itemsNotRetrived
            for itemOresDictLookupKey, itemOresDictLookupValue in pairs(itemOresDict[itemOres]) do
                if (itemOresDictLookupValue.itemDamage == itemDamage or itemDamage == "*") and (itemOresDictLookupValue.itemNbtHash == itemNbtHash or itemNbtHash == "*") then
                    local craftedItem, notCraftedReason, missingMat = CraftItems(itemOresDictLookupValue.itemName, toCraft, itemOresDictLookupValue.itemDamage, itemOresDictLookupValue.itemNbtHash, true)
                    if craftedItem == 0 and notCraftedReason == "craftingFailure" then
                        Msg("Crafting failure! (3)", {itemType, itemDamage, itemNbtHash, itemOres})
                        return toCraft
                    elseif craftedItem == 0 then
                        Msg(notCraftedReason)
                    else
                        toCraft = toCraft - craftedItem
                    end
                    StoreAllInChest(inChest)
                    if toCraft <= 0 then
                        break
                    end
                end
            end
            if toCraft > 0 then
                return
            end
        else
            Msg("Will try to craft: " .. itemType, {itemType, itemDamage, itemNbtHash, itemOres})
            local craftedMat, notCraftedReason, missingMat = CraftItems(itemType, itemsNotRetrived, itemDamage, itemNbtHash, true)
            StoreAllInChest(inChest)
        end
        RetriveItem(to, slot, itemType, itemsNotRetrived, itemOres, itemDamage, itemNbtHash, itemEnchantments)
    end
end

function RetriveItem(to, slot, itemType, itemCount, itemOres, itemDamage, itemNbtHash, itemEnchantments)--any (apart from count) can be wildcards * and itemEnchantments can also be "none"
    Msg("Retriving item: " .. itemType .. " " .. itemOres .. " " .. tostring(itemDamage), {itemType, itemDamage, itemNbtHash, itemOres})
    local toTransfer = itemCount
    local itemLocations = GetItemLocations(itemType, itemOres, itemDamage, itemNbtHash, itemEnchantments)

    for chest, chestSlots in pairs(itemLocations) do
        for chestSlot, chestSlotCount in pairs(chestSlots) do
            local transfered = nil
            if type(to) == "string" then
                if slot == "*" then
                    transfered = peripheral.wrap(chestBankPrefix .. chest).pushItems(to, tonumber(chestSlot), toTransfer)
                else
                    transfered = peripheral.wrap(chestBankPrefix .. chest).pushItems(to, tonumber(chestSlot), toTransfer, slot)
                end
            else
                if slot == "*" then
                    transfered = to.pullItems(chestBankPrefix .. chest, tonumber(chestSlot), toTransfer)
                else
                    transfered = to.pullItems(chestBankPrefix .. chest, tonumber(chestSlot), toTransfer, slot)
                end
            end
            toTransfer = toTransfer - transfered
            if transfered == 0 then
                --Msg("Cannot transfer anymore as target is full")
                --return toTransfer, "full"
            else
                itemsStored[chestSlotCount["itemType"]][tonumber(chestSlotCount["varientID"])].locations[chest][chestSlot] = chestSlotCount["count"] - transfered
                if itemsStored[chestSlotCount["itemType"]][tonumber(chestSlotCount["varientID"])].locations[chest][chestSlot] == 0 then
                    itemsStored[chestSlotCount["itemType"]][tonumber(chestSlotCount["varientID"])].locations[chest][chestSlot] = nil
                    if emptySlots[chest] == nil then
                        emptySlots[chest] = {}
                    end
                    emptySlots[chest][chestSlot] = true
                end
            end
            if toTransfer <= 0 then
                SaveCache()
                Msg("Items transfered: " .. itemType .. " " .. itemOres .. " " .. tostring(itemDamage), {itemType, itemDamage, itemNbtHash, itemOres})
                return 0
            end
        end
    end

    SaveCache()
    Msg("Cannot transfer anymore as run out: " .. itemType .. " " .. itemOres .. " " .. tostring(itemDamage), {itemType, itemDamage, itemNbtHash, itemOres})
    return toTransfer, "runOut"
end

if args[1] == "--skipcacheupdate" then
    Msg("Skipping cache update...")
    itemsStored = ReadToTable("itemsStored.lua")
    emptySlots = ReadToTable("emptySlots.lua")
else
    UpdateItemsStored()
end

craftingRecipies = ReadToTable("craftingRecipies.lua")
MsgNow("Loaded " .. tostring(TableLength(craftingRecipies)) .. " recipies")

--StoreItem(bench, 1)
--RetriveItem(bench, 1, "*", 5, "logWood", "*", "*", "*")

--Msg(textutils.serialize(GetItemLocations("*", "logWood", "*", "*", "*")))-- type, ores, damage, nbtHash, enchantments
--PrintTable(GetItemLocations("*", "logWood", "*", "*", "*"))
--print(CountItems("*", "cobblestone", "*", "*", "*"))

function StoreAllInChest(chest)
    for i = 1, chest:size() do
        local itemMeta = chest.getItemMeta(i)
        if itemMeta ~= nil then
            if (maxItems[itemMeta.name] == nil or CountItems(itemMeta.name, "*", "*", "*", "*") <= maxItems[itemMeta.name]) then
                StoreItem(chest, i)
            else
                chest.pushItems(modemNameLocal, i, 64, 1)--move from chest to self
                turtle.drop(64)--drop items on the floor if there is more than enough of that item in storage
            end
        end
    end
end

local taskQueue = {}

function TaskQueueLoopCycle()
    if TableLength(taskQueue) == 0 then
        Msg("idle")
    end
    for taskKey, taskValue in pairs(taskQueue) do
        if taskValue["command"] == "retrive" then
            local outChest = "main"
            local outSlot = "*"
            local itemType = "*"
            local itemCount = 1
            local itemOres = "*"
            local itemDamage = "*"
            local itemNbtHash = "*"
            local itemEnchantments = "*"
            if taskValue["outChest"] ~= nil then
                outChest = taskValue["outChest"]
            end
            if taskValue["outSlot"] ~= nil then
                outSlot = taskValue["outSlot"]
            end
            if taskValue["itemType"] ~= nil then
                itemType = taskValue["itemType"]
            end
            if taskValue["itemCount"] ~= nil then
                itemCount = tonumber(taskValue["itemCount"])
            end
            if taskValue["itemOres"] ~= nil then
                itemOres = taskValue["itemOres"]
            end
            if taskValue["itemDamage"] ~= nil then
                itemDamage = taskValue["itemDamage"]
            end
            if taskValue["itemNbtHash"] ~= nil then
                itemNbtHash = taskValue["itemNbtHash"]
            end
            if taskValue["itemEnchantments"] ~= nil then
                itemEnchantments = taskValue["itemEnchantments"]
            end
            taskQueue[taskKey] = nil
            RetriveItemOrCraft(outChests[outChest], outSlot, itemType, itemCount, itemOres, itemDamage, itemNbtHash, itemEnchantments)
            taskValue["command"] = nil
            taskValue["type"] = "retrived"
            Send(taskValue)
        elseif taskValue["command"] == "count" then
            local itemType = "*"
            local itemOres = "*"
            local itemDamage = "*"
            local itemNbtHash = "*"
            local itemEnchantments = "*"
            if taskValue["itemType"] ~= nil then
                itemType = taskValue["itemType"]
            end
            if taskValue["itemOres"] ~= nil then
                itemOres = taskValue["itemOres"]
            end
            if taskValue["itemDamage"] ~= nil then
                itemDamage = taskValue["itemDamage"]
            end
            if taskValue["itemNbtHash"] ~= nil then
                itemNbtHash = taskValue["itemNbtHash"]
            end
            if taskValue["itemEnchantments"] ~= nil then
                itemEnchantments = taskValue["itemEnchantments"]
            end
            taskQueue[taskKey] = nil
            local count = CountItems(itemType, itemOres, itemDamage, itemNbtHash, itemEnchantments)
            Msg("Count of " .. itemType .. " " .. itemOres .. " " .. tostring(itemDamage) .. ": " .. tostring(count), {itemType, itemDamage, itemNbtHash, itemOres})
            taskValue["command"] = nil
            taskValue["type"] = "count"
            taskValue["count"] = count
            Send(taskValue)
        elseif taskValue["command"] == "dump" then
            local outChest = "main"
            if taskValue["outChest"] ~= nil then
                outChest = taskValue["outChest"]
            end
            taskQueue[taskKey] = nil
            StoreAllInChest(outChests[outChest])
            taskValue["command"] = nil
            taskValue["type"] = "dumped"
            Send(taskValue)
        elseif taskValue["command"] == "end" then
            Msg("Recived end command, will stop")
            return
        elseif taskValue["command"] == "reboot" then
            Msg("Recived reboot command, will reboot")
            SaveCache()
            rednet.close("right")
            os.reboot()
            return
        end
        break
    end
    StoreAllInChest(inChest)

    for chestName, chestSlots in pairs(autoOutChests) do
        local chest = outChests[chestName]
        for chestSlot, chestItemWanted in pairs(chestSlots) do
            local itemMeta = chest.getItemMeta(chestSlot)
            if itemMeta == nil then
                RetriveItemOrCraft(chest, chestSlot, chestItemWanted.itemType, chestItemWanted.count, chestItemWanted.itemOres, chestItemWanted.itemDamage, chestItemWanted.itemNbtHash, chestItemWanted.itemEnchantments)
            else
                --todo
            end
        end
    end

    if TableLength(minItems) > 0 then
        if CountItems(minItems[minItemIndex].itemType, minItems[minItemIndex].itemOres, minItems[minItemIndex].itemDamage, minItems[minItemIndex].itemNbtHash, minItems[minItemIndex].itemEnchantments) < minItems[minItemIndex].itemCount then
            RetriveItemOrCraft(inChest, "*", minItems[minItemIndex].itemType, 1, minItems[minItemIndex].itemOres, minItems[minItemIndex].itemDamage, minItems[minItemIndex].itemNbtHash, minItems[minItemIndex].itemEnchantments, "c")
        end

        minItemIndex = minItemIndex + 1
        if minItemIndex > TableLength(minItems) then
            minItemIndex = 1
        end
    end
end

function TaskQueueLoop()
    while true do
        os.sleep(0.1)
        TaskQueueLoopCycle()
    end
end

function NetworkLoop()
    os.sleep(0.1)
    Msg("Waiting for network requests, ID is " .. tostring(os.getComputerID()))
    while true do
        os.sleep(0)
        local senderID, message, distance = rednet.receive("bodkinStorage_1.0")
        if message["command"] ~= nil then
            taskQueue[tostring(math.random(0, 99999))] = message
        end
    end
end

function NetworkLoop2()
    os.sleep(0.1)
    while true do
        for toSendKey, toSendValue in pairs(toSend) do
            rednet.broadcast(toSendValue, "bodkinStorage_1.0")
            toSend[toSendKey] = nil
            break
        end
        os.sleep(0.05)
    end
end

--for i = 1, craftingChestCount do
--    StoreAllInChest(peripheral.wrap(craftingChestPrefix .. tostring(i)))
--end

parallel.waitForAny(TaskQueueLoop, NetworkLoop, NetworkLoop2)


SaveCache()
rednet.close("right")
