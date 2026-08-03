--!strict

--[[
	RarityConfig

	How each rarity is presented. Contains no weight, no probability and no reward — those live
	in BalanceConfig, and keeping them apart means a designer can restyle a tier without
	touching a number that changes what the game pays out.

	docs/06 requires "color-independent rarity labels and icons" and docs/07 says not to rely on
	colour alone. Rarity is therefore carried on four redundant channels:

	    1. Word    -- the label, spelled out
	    2. Glyph   -- a distinct shape per tier
	    3. Pips    -- a count, drawn as frames rather than text
	    4. Colour  -- last, and never the only signal

	The pips are drawn as `Frame`s rather than repeated characters on purpose. The higher tiers
	use dingbat glyphs whose font fallback is unreliable on Android, so rendering the count as
	text too would put two of the four channels on one point of failure.

	Lives in shared/Config rather than with the client so ConfigAudit can validate it at server
	startup: a rarity added without a presentation entry would otherwise render as a blank chip
	on every client, and nothing would report it.
]]

export type RarityPresentation = {
	Order: number,
	Label: string,
	Glyph: string,
	Pips: number,
	Color: Color3,
	-- How long the reveal card holds for this tier. Rarer means longer, because a Secret is
	-- worth stopping for and a Common is not.
	RevealSeconds: number,
}

--[[
	Constructor rather than a table literal, for the same reason ContentConfig has one: a bare
	string key would widen and lose the Rarity union, and a typo like "Mythic" would then sit
	in the table silently until something failed to find it.
]]
local function presentation(
	order: number,
	label: string,
	glyph: string,
	pips: number,
	color: Color3,
	revealSeconds: number
): RarityPresentation
	return table.freeze({
		Order = order,
		Label = label,
		Glyph = glyph,
		Pips = pips,
		Color = color,
		RevealSeconds = revealSeconds,
	})
end

local BY_RARITY: { [string]: RarityPresentation } = table.freeze({
	Common = presentation(1, "Common", "•", 1, Color3.fromRGB(176, 190, 208), 1.6),
	Uncommon = presentation(2, "Uncommon", "◆", 2, Color3.fromRGB(104, 198, 128), 1.8),
	Rare = presentation(3, "Rare", "▲", 3, Color3.fromRGB(88, 158, 246), 2.2),
	Epic = presentation(4, "Epic", "★", 4, Color3.fromRGB(176, 122, 240), 2.6),
	Legendary = presentation(5, "Legendary", "✦", 5, Color3.fromRGB(255, 176, 64), 3.2),
	Secret = presentation(6, "Secret", "❖", 6, Color3.fromRGB(255, 96, 128), 4.0),
})

local FALLBACK: RarityPresentation =
	presentation(0, "Unknown", "?", 0, Color3.fromRGB(140, 140, 140), 1.5)

return table.freeze({
	ByRarity = BY_RARITY,
	Fallback = FALLBACK,

	get = function(rarity: string): RarityPresentation
		return BY_RARITY[rarity] or FALLBACK
	end,

	Reveal = table.freeze({
		--[[
			Duplicates below this rarity order do not open a card. Common is 55% of the
			baseline, so once both Backyard Commons are owned a card per duplicate would be
			constant noise against docs/01's "limited simultaneous popups".

			Suppression is presentation only. The award, its Heat and its save all still
			happen — this decides whether a card is drawn, nothing else.
		]]
		DuplicateCardMinOrder = 3,
		-- Cards waiting behind the one on screen. Beyond this, overflow collapses into a
		-- single summary line rather than a queue the player has to sit through.
		QueueDepth = 3,
	}),

	Silhouette = table.freeze({
		-- Undiscovered entries are drawn as a flat shape in this colour, with the name hidden.
		Color = Color3.fromRGB(58, 68, 84),
		HiddenName = "? ? ?",
	}),
})
