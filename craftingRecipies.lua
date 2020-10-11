{
    ["minecraft:planks|0|"] = {
        {
            count = 4,--how many will 1 craft make
            materials = {--define the materials needed (count calculated by inputSlots)
                ["log"] = {
                    itemType = "minecraft:log",
                    itemOres = "*",
                    itemDamage = 0,
                    itemNbtHash = "*",
                    itemEnchantments = "none"
                },
            },
            workstation = "bench",
            inputSlots = {
                [1] = {
                    material = "log",
                    count = 1
                }
            },
            outputSlot = 1
        },
    },
    ["minecraft:stick|0|"] = {
        {
            count = 4,
            materials = {
                ["plank"] = {
                    itemType = "*",
                    itemOres = "plankWood",
                    itemDamage = 0,
                    itemNbtHash = "*",
                    itemEnchantments = "none"
                },
            },
            workstation = "bench",
            inputSlots = {
                [1] = {
                    material = "plank",
                    count = 1
                },
                [5] = {
                    material = "plank",
                    count = 1
                }
            },
            outputSlot = 1
        },
    },
}
