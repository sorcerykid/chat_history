--------------------------------------------------------
-- Minetest :: Chat History Mod v2.0 (chat_history)
--
-- See README.txt for licensing and other information.
-- Copyright (c) 2016-2018, Leslie E. Krause
--------------------------------------------------------

chat_history = { }	-- global namespace

local buffer = { }
local buffer_limit = nil
local review_limit = 100

minetest.register_on_chat_message( function( sender, message )
	table.insert( buffer, { sender = sender, time = os.time( ), message = message } )
	if buffer_limit and #buffer > buffer_limit then
		table.remove( buffer, 1 )
	end
end )

local old_chatcommand = minetest.chatcommands[ "msg" ].func

minetest.chatcommands[ "msg" ].func = function( sender, param )
	local recipient, message = string.match( param, "^([A-Za-z0-9_]+)%s(.+)$" )
	if recipient and message then
		minetest.sound_play( "mailbox_chime", { to_player = recipient, gain = 0.5, loop = false } )
		table.insert( buffer, { sender = sender, recipient = recipient, time = os.time( ), message = message } )
		if buffer_limit and #buffer > buffer_limit then
			table.remove( buffer, 1 )
		end
	end
	return old_chatcommand( sender, param )
end

local find_phrase = function( source, phrase )
	-- sanitize search phrase and convert to regexp pattern
	local sanitizer =
	{
		["^"] = "%^";
		["$"] = "%$";
		["("] = "%(";
		[")"] = "%)";
		["%"] = "%%";
		["."] = "%.";
		["["] = "";
		["]"] = "";
		["*"] = "%w*";
		["+"] = "%w+";
		["-"] = "%-";
		["?"] = "%w";
	}
	return string.find( string.upper( source ), ( string.gsub( string.upper( phrase ), ".", sanitizer ) ) )		-- parens capture only first return value of gsub
end

local get_player_list = function( )
	local player_list = { }
	for i, p in ipairs( minetest.get_connected_players( ) ) do
		table.insert( player_list, p:get_player_name( ) )
	end
	table.sort( player_list, function( a, b ) return a < b end )	-- sort modifies table, hence the need to create a local copy
	return player_list
end

local get_player_formspec = function( recipient, meta, filter_player, is_filter_pm, is_filter_shout )
	local filter_player_idx = 1
	local review_count = 0
	local buffer_count = #buffer
	local formspec = "size[11,7.8]"
		.. default.gui_bg
		.. default.gui_bg_img

--	formspec = formspec .. "textarea[0.3,0.3;11,7.5;buffer;Chat History (Last " .. ( #buffer == buffer_limit and buffer_limit or #buffer ) .. " Messages);\n"
	formspec = formspec .. "textarea[0.3,0.5;11,7.5;buffer;Chat History ("
		.. ( meta.filter_phrase == "" and "All Player Messages" or "Player Messages Containing '" .. minetest.formspec_escape( meta.filter_phrase ) .. "'" ) .. ");"

	while buffer_count > 0 and review_count < review_limit do
		local m = buffer[ buffer_count ]

		if ( filter_player == "" or filter_player == m.sender ) and ( meta.filter_phrase == "" or find_phrase( m.message, meta.filter_phrase ) ) and
		not( is_filter_shout == true and string.byte( m.message ) ~= 33 or is_filter_pm == true and not m.recipient ) and string.byte( m.sender ) ~= 95 then
			if not m.recipient then
        	                formspec = formspec .. string.format( "\\[%s\\] <%s> %s\n", os.date( "%X", m.time ), m.sender, minetest.formspec_escape( m.message ) )
				review_count = review_count + 1
			elseif m.recipient == recipient then
				formspec = formspec .. string.format( "\\[%s\\] PM from %s: %s\n", os.date( "%X", m.time ), m.sender, minetest.formspec_escape( m.message ) )
				review_count = review_count + 1
			elseif m.sender == recipient then
				formspec = formspec .. string.format( "\\[%s\\] PM to %s: %s\n", os.date( "%X", m.time ), m.recipient, minetest.formspec_escape( m.message ) )
				review_count = review_count + 1
			end
		end
		buffer_count = buffer_count - 1
	end

	formspec = formspec .. "]"
		.. "label[9,0;" .. os.date( "%X" ) .. "]"
		.. "label[0,7.2;Player:]"
		.. "dropdown[1,7.2;3.5,1;filter_player;"
	for i, p in pairs( meta.player_list ) do
		formspec = formspec .. "," .. p
		if p == filter_player then
			filter_player_idx = 1 + i	 -- don't forget to skip over first entry
		end
	end
	formspec = formspec .. ";" .. filter_player_idx .. "]"
		.. "checkbox[4.5,7;is_filter_pm;Only PMs;" .. tostring( is_filter_pm ) .. "]"
		.. "checkbox[6.5,7;is_filter_shout; Only Shouts;" .. tostring( is_filter_shout ) .. "]"
		.. "button[9,7;2,1;update;Update]"
--		.. "hidden[filter_phrase;" .. filter_phrase .. "]"

	return formspec
end

local get_server_formspec = function( recipient, meta )
	local filter_player_idx = 1
	local review_count = 0
	local buffer_count = #buffer
	local formspec = "size[11,7.8]"
		.. default.gui_bg
		.. default.gui_bg_img

	formspec = formspec .. "textarea[0.3,0.5;11,7.5;buffer;Chat History (All Server Messages);"

	while buffer_count > 0 and review_count < review_limit do
		local m = buffer[ buffer_count ]

		if m.sender == meta.filter_server and ( not m.recipient or m.recipient == recipient ) then
       	                formspec = formspec .. string.format( "\\[%s\\] %s\n", os.date( "%X", m.time ),
				minetest.formspec_escape( m.recipient and m.message or "*** " .. m.message ) )
			review_count = review_count + 1
		end
		buffer_count = buffer_count - 1
	end

	formspec = formspec .. "]"
		.. "label[9,0;" .. os.date( "%X" ) .. "]"
		.. "label[0,7.2;" .. meta.filter_description .. "]"
		.. "button[9,7;2,1;update;Update]"

	return formspec
end

local on_close_player_formspec = function ( meta, player, fields )
	local name = player:get_player_name( )

	-- TODO: should we check buffer modification time to prevent flood of update requests?
	if fields.filter_player then
		minetest.update_form( player, get_player_formspec( name, meta, string.match( fields.filter_player, "^([A-Za-z0-9_-]*)" ), fields.is_filter_pm == "true", fields.is_filter_shout == "true" ) )
	end
end

local on_close_server_formspec = function ( meta, player, fields )
	local name = player:get_player_name( )

	if fields.update then
		minetest.update_form( player, get_server_formspec( name, meta ) )
	end
end

chat_history.add_message = function ( sender, recipient, message )
	table.insert( buffer, { sender = sender, recipient = recipient, time = os.time( ), message = message } )
end

chat_history.open = function ( name, filter_player )
	local meta = { filter_phrase = "", player_list = get_player_list( ) }
	minetest.create_form( meta, minetest.get_player_by_name( name ), get_player_formspec( name, meta, filter_player or "", false, false ), on_close_player_formspec )
end

minetest.register_chatcommand( "chat", {
        description = "View the recent chat history with optional message filters.",
        func = function( name, param )
		if param ~= "" and not minetest.player_exists( param ) then
			return false, "Unknown player specified."
		else
			-- we must save player list, because client doesn't update formspec drop-downs correctly
			local meta = { filter_phrase = "", player_list = get_player_list( ) }
			minetest.create_form( meta, minetest.get_player_by_name( name ), get_player_formspec( name, meta, param, false, false ), on_close_player_formspec )
		end
	end
} )

minetest.register_chatcommand( "c", {
        description = "View the recent chat history given a search pattern.",
        func = function( name, param )
		if string.len( param ) < 3 or string.len( param ) > 30 then
			return false, "Invalid search pattern specified."
		else
			-- we must save player list, because client doesn't update formspec drop-downs correctly
			local meta = { filter_phrase = param, player_list = get_player_list( ) }
			minetest.create_form( meta, minetest.get_player_by_name( name ), get_player_formspec( name, meta, "", false, false ), on_close_player_formspec )
		end
	end
} )

minetest.register_chatcommand( "info", {
        description = "View automated info notifications.",
        func = function( name, param )
		local meta = { filter_server = "_infobot", filter_description = "Showing info notifications only" }
		minetest.create_form( meta, minetest.get_player_by_name( name ), get_server_formspec( name, meta ), on_close_server_formspec )
	end
} )

minetest.register_on_joinplayer( function( player )
	local name = player:get_player_name( )
	chat_history.add_message( "_infobot", nil, name .. " joined the game." )

	if minetest.get_modpath( "chat2" ) then
		minetest.after( 10, function( )
		        chat2.send_message( name, 'Use /chat or /c [search_phrase] commands to view chat history with optional message filters.', 0xDDAA55 )
		end )
	end
end )

minetest.register_on_leaveplayer( function( player, is_timeout )
	local name = player:get_player_name( )
	chat_history.add_message( "_infobot", nil, name .. " left the game." )
end )
