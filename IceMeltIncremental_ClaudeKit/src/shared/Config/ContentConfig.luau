--!strict

return table.freeze({
	Tools = table.freeze({
		table.freeze({ Key = "Match", DisplayName = "Match", Cost = 0, Power = 1.0, Radius = 0 }),
		table.freeze({
			Key = "Candle",
			DisplayName = "Candle",
			Cost = 350,
			Power = 1.35,
			Radius = 0.25,
		}),
		table.freeze({
			Key = "Torch",
			DisplayName = "Torch",
			Cost = 2500,
			Power = 1.85,
			Radius = 0.50,
		}),
		table.freeze({
			Key = "Blowtorch",
			DisplayName = "Blowtorch",
			Cost = 18000,
			Power = 2.60,
			Radius = 0.75,
		}),
		table.freeze({
			Key = "Flamethrower",
			DisplayName = "Flamethrower",
			Cost = 125000,
			Power = 3.80,
			Radius = 1.25,
		}),
		table.freeze({
			Key = "HeatCannon",
			DisplayName = "Heat Cannon",
			Cost = 900000,
			Power = 5.80,
			Radius = 1.75,
		}),
		table.freeze({
			Key = "LavaCore",
			DisplayName = "Lava Core",
			Cost = 8000000,
			Power = 9.00,
			Radius = 2.50,
		}),
		table.freeze({
			Key = "MiniSun",
			DisplayName = "Mini Sun",
			Cost = 85000000,
			Power = 15.00,
			Radius = 4.00,
		}),
	}),
	Zones = table.freeze({
		Backyard = table.freeze({
			DisplayName = "Frozen Backyard",
			Cost = 0,
			Durability = 10,
			Heat = 1,
			RespawnSeconds = 5,
			Luck = 1.0,
		}),
		Cavern = table.freeze({
			DisplayName = "Ice Cavern",
			Cost = 25000,
			Durability = 250,
			Heat = 30,
			RespawnSeconds = 7,
			Luck = 1.5,
		}),
		City = table.freeze({
			DisplayName = "Frozen City",
			Cost = 5000000,
			Durability = 12000,
			Heat = 1800,
			RespawnSeconds = 9,
			Luck = 2.25,
		}),
	}),
})
