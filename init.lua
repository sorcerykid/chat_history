--------------------------------------------------------
-- Minetest :: Chat History Mod v3.0 (chat_history)
--
-- See README.txt for licensing and other information.
-- Copyright (c) 2016-2020, Leslie E. Krause
--
-- ./games/minetest_game/mods/chat_history/init.lua
--------------------------------------------------------

chat_history = { }	-- global namespace

local config = minetest.load_config( )
local buffer = { }

---------------------
-- Private Methods --
---------------------

local fs = minetest.formspec_escape
local sprintf = string.format

local function find_phrase( source, phrase )
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

--------------------
-- Public Methods --
--------------------

chat_history.open_player_viewer = function ( recipient, filter_phrase, filter_player )
	local player_list = { }
	local filter_server = "_infobot"
	local is_filter_pm = false
	local is_filter_shout = false

	local function get_formspec( )
		local review_count = 0
		local buffer_count = #buffer

		local formspec = "size[11.0,7.8]"
			.. minetest.gui_bg
			.. minetest.gui_bg_img

		formspec = formspec .. "textarea[0.3,0.5;11.0,7.5;buffer;Chat History ("
			.. ( filter_phrase == "" and "All Player Messages" or "Player Messages Containing '" .. fs( filter_phrase ) .. "'" ) .. ");"

		while buffer_count > 0 and review_count < config.review_limit do
			local m = buffer[ buffer_count ]
			local has_filter_player = not filter_player or m.sender == filter_player or m.sender == recipient
			local has_filter_phrase = filter_phrase == "" or find_phrase( m.message, filter_phrase )
			local has_filter_option = not ( is_filter_shout and string.byte( m.message ) ~= 33 or is_filter_pm and not m.recipient ) 

			if m.sender == filter_server and not filter_player then
				if not m.recipient or m.recipient == recipient then
					formspec = formspec .. sprintf( "\\[%s\\] %s\n", os.date( "%X", m.time ),
						fs( m.recipient and m.message or "*** " .. m.message ) )
					review_count = review_count + 1
				end
			elseif has_filter_player and has_filter_phrase and has_filter_option and string.byte( m.sender ) ~= 95 then
				if not m.recipient then
        		                formspec = formspec .. sprintf( "\\[%s\\] <%s> %s\n", os.date( "%X", m.time ), m.sender, fs( m.message ) )
					review_count = review_count + 1
				elseif m.recipient == recipient then
					formspec = formspec .. sprintf( "\\[%s\\] PM from %s: %s\n", os.date( "%X", m.time ), m.sender, fs( m.message ) )
					review_count = review_count + 1
				elseif m.sender == recipient then
					formspec = formspec .. sprintf( "\\[%s\\] PM to %s: %s\n", os.date( "%X", m.time ), m.recipient, fs( m.message ) )
					review_count = review_count + 1
				end
			end

			buffer_count = buffer_count - 1
		end

		local filter_player_idx = 1

		formspec = formspec .. "]"
			.. "label[9.0,0.0;" .. os.date( "%X" ) .. "]"
			.. "label[0,7.3;Player:]"
			.. "dropdown[1,7.2;3.5,1;filter_player;,"
		formspec = formspec .. table.join( player_list, ",", function ( i, v )
			if v.name == filter_player then
				filter_player_idx = i + 1
			end
			return fs( v.name .. registry.rank_badges[ v.rank ] )
		end )
		formspec = formspec .. ";" .. filter_player_idx .. ";true]"
			.. "checkbox[4.5,7.1;is_filter_pm;Only PMs;" .. tostring( is_filter_pm ) .. "]"
			.. "checkbox[6.5,7.1;is_filter_shout; Only Shouts;" .. tostring( is_filter_shout ) .. "]"
			.. "button[9.0,7.1;2.0,1.0;update;Update]"

		return formspec
	end

	local function on_close( meta, player, fields )
		if fields.quit then return end

		if fields.update then
			minetest.update_form( recipient, get_formspec( ) )

		elseif fields.is_filter_pm then
			is_filter_pm = fields.is_filter_pm == "true"
			if is_filter_shout then
				is_filter_shout = false
			end
			minetest.update_form( recipient, get_formspec( ) )

		elseif fields.is_filter_shout then
			is_filter_shout = fields.is_filter_shout == "true"
			if is_filter_pm then
				is_filter_pm = false
			end
			minetest.update_form( recipient, get_formspec( ) )

		elseif fields.filter_player then
			filter_player = fields.filter_player > 1 and player_list[ fields.filter_player - 1 ].name or nil
			minetest.update_form( recipient, get_formspec( ) )
		end
	end

	-- we need to copy the player list to ensure consistency of dropdown
	-- menu in case players log on/off in background
	for name, data in registry.iterate( ) do
		table.insert( player_list, { name = name, rank = data.rank } )
	end
	table.sort( player_list, function( a, b ) return a.name < b.name end )

	minetest.create_form( nil, recipient, get_formspec( ), on_close )
end

chat_history.open_server_viewer = function ( recipient, filter_server, filter_description )
	local filter_server = "_infobot"
	local filter_description = "Showing info notifications only"

	local function get_formspec( )
		local review_count = 0
		local buffer_count = #buffer
		local formspec = "size[11.0,7.8]"
			.. minetest.gui_bg
			.. minetest.gui_bg_img

		formspec = formspec .. "textarea[0.3,0.5;11.0,7.5;buffer;Chat History (All Server Messages);"

		while buffer_count > 0 and review_count < config.review_limit do
			local m = buffer[ buffer_count ]

			if m.sender == filter_server and ( not m.recipient or m.recipient == recipient ) then
       	                	formspec = formspec .. sprintf( "\\[%s\\] %s\n", os.date( "%X", m.time ),
					fs( m.recipient and m.message or "*** " .. m.message ) )
				review_count = review_count + 1
			end
			buffer_count = buffer_count - 1
		end

		formspec = formspec .. "]"
			.. "label[9.0,0.0;" .. os.date( "%X" ) .. "]"
			.. "label[0.0,7.1.2;" .. filter_description .. "]"
			.. "button[9.0,7.1;2,1;update;Update]"

		return formspec
	end

	local function on_close( meta, player, fields )
		if fields.update then
			minetest.update_form( recipient, get_formspec( ) )
		end
	end

	minetest.create_form( nil, recipient, get_formspec( ), on_close )
end

chat_history.add_message = function( sender, recipient, message )
	table.insert( buffer, { sender = sender, recipient = recipient, time = os.time( ), message = message } )
end

minetest.register_on_chat_message( function( sender, message )
	table.insert( buffer, { sender = sender, time = os.time( ), message = message } )
	if config.buffer_limit and #buffer > config.buffer_limit then
		table.remove( buffer, 1 )
	end
end )

------------------------------
-- Registered Chat Commands --
------------------------------

local old_chatcommand = minetest.chatcommands[ "msg" ].func

minetest.chatcommands[ "msg" ].func = function( sender, param )
	local recipient, message = string.match( param, "^([A-Za-z0-9_]+)%s(.+)$" )
	if recipient and message then
		minetest.sound_play( "mailbox_chime", { to_player = recipient, gain = 0.5, loop = false } )
		table.insert( buffer, { sender = sender, recipient = recipient, time = os.time( ), message = message } )
		if config.buffer_limit and #buffer > config.buffer_limit then
			table.remove( buffer, 1 )
		end
	end
	return old_chatcommand( sender, param )
end

minetest.register_chatcommand( "chat", {
        description = "View the recent chat history with optional message filters.",
        func = function( name, param )
		if param ~= "" and not core.auth_table[ param ] then
			return false, "Unknown player specified."
		else
			chat_history.open_player_viewer( name, "", param ~= "" and param or nil )
		end
	end
} )

minetest.register_chatcommand( "c", {
        description = "View the recent chat history given a search pattern.",
        func = function( name, param )
		if string.len( param ) < 3 or string.len( param ) > 30 then
			return false, "Invalid search pattern specified."
		else
			chat_history.open_player_viewer( name, param )
		end
	end
} )

minetest.register_chatcommand( "info", {
        description = "View automated info notifications.",
        func = function( name, param )
		chat_history.open_server_viewer( name )
	end
} )

--------------------------
-- Registered Callbacks --
--------------------------

minetest.register_on_joinplayer( function( player )
	chat_history.add_message( "_infobot", nil, player:get_player_name( ) .. " joined the game." )
	minetest.after( 10, function( player )
	        chat2.send_message( player, 'Use /chat or /c [search_phrase] commands to view chat history with optional message filters.', 0xDDAA55 )
	end, player )
end )

minetest.register_on_leaveplayer( function( player )
	chat_history.add_message( "_infobot", nil, player:get_player_name( ) .. " left the game." )
end )

minetest.register_on_dieplayer( function( player )
	chat_history.add_message( "_infobot", player:get_player_name( ), "You died." )
end )

