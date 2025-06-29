local Players = game:GetService("Players")

local function list_players()
	local players = Players:GetPlayers()
	local dict_of_user_ids = {}
	for _, player in ipairs(players) do
		dict_of_user_ids[`{player.UserId}`] = 0
	end

	return dict_of_user_ids, #players
end

local function messaging_metadata<T>(raw_server_metadata: T & {})
	if type(raw_server_metadata) == "table" then
		return {
			GameId = raw_server_metadata[1] :: number,
			PlaceId = raw_server_metadata[2] :: number,
			PlaceVersion = raw_server_metadata[3] :: number,
			JobId = raw_server_metadata[4] :: string,
			Players = raw_server_metadata[5] :: { [string]: number },
			TotalPlayers = raw_server_metadata[6] :: number,
		}
	end

	local dict_of_user_ids, current_num_players = list_players()
	return {
		game.GameId,
		game.PlaceId,
		game.PlaceVersion,
		game.JobId,
		dict_of_user_ids,
		current_num_players,
	}
end

export type MessagingMetadata = typeof(messaging_metadata())

return messaging_metadata
