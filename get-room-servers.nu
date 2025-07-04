#!/usr/bin/env nu

# Get all unique servers (homeservers) present in a room
def get-room-servers [
    room_id: string,                    # Room ID to analyze
    db_path: string = '~/Library/Application Support/gomuks/gomuks.db' # Path to the gomuks database
] {
    open ($db_path | path expand) | query db "
        SELECT DISTINCT 
            substr(state_key, instr(state_key, ':') + 1) as server,
            COUNT(*) as user_count
        FROM current_state
        WHERE room_id = :room_id
        AND event_type = 'm.room.member'
        AND state_key LIKE '@%:%'
        GROUP BY server
        ORDER BY user_count DESC, server ASC
    " -p { room_id: $room_id }
}

# Get all unique servers across multiple rooms
def get-servers-multi-room [
    room_ids: list<string>,             # List of room IDs to analyze
    db_path: string = '~/Library/Application Support/gomuks/gomuks.db' # Path to the gomuks database
] {
    open ($db_path | path expand) | query db "
        SELECT 
            substr(state_key, instr(state_key, ':') + 1) as server,
            COUNT(DISTINCT state_key) as total_users,
            COUNT(DISTINCT room_id) as room_count,
            GROUP_CONCAT(DISTINCT room_id) as rooms
        FROM current_state
        WHERE room_id IN (SELECT value FROM json_each(:room_ids))
        AND event_type = 'm.room.member'
        AND state_key LIKE '@%:%'
        GROUP BY server
        ORDER BY total_users DESC, server ASC
    " -p { room_ids: ($room_ids | to json) }
}

# Get servers with only active (joined) members
def get-active-servers [
    room_id: string,                    # Room ID to analyze
    db_path: string = '~/Library/Application Support/gomuks/gomuks.db' # Path to the gomuks database
] {
    open ($db_path | path expand) | query db "
        SELECT DISTINCT 
            substr(state_key, instr(state_key, ':') + 1) as server,
            COUNT(*) as active_user_count
        FROM current_state
        WHERE room_id = :room_id
        AND event_type = 'm.room.member'
        AND membership = 'join'
        AND state_key LIKE '@%:%'
        GROUP BY server
        ORDER BY active_user_count DESC, server ASC
    " -p { room_id: $room_id }
}

# Get detailed server breakdown with membership stats
def get-server-breakdown [
    room_id: string,                    # Room ID to analyze
    db_path: string = '~/Library/Application Support/gomuks/gomuks.db' # Path to the gomuks database
] {
    open ($db_path | path expand) | query db "
        SELECT 
            substr(state_key, instr(state_key, ':') + 1) as server,
            SUM(CASE WHEN membership = 'join' THEN 1 ELSE 0 END) as joined,
            SUM(CASE WHEN membership = 'leave' THEN 1 ELSE 0 END) as left,
            SUM(CASE WHEN membership = 'ban' THEN 1 ELSE 0 END) as banned,
            SUM(CASE WHEN membership = 'invite' THEN 1 ELSE 0 END) as invited,
            COUNT(*) as total
        FROM current_state
        WHERE room_id = :room_id
        AND event_type = 'm.room.member'
        AND state_key LIKE '@%:%'
        GROUP BY server
        ORDER BY total DESC, server ASC
    " -p { room_id: $room_id }
}

# Get just the server names as a simple list
def list-room-servers [
    room_id: string,                    # Room ID to analyze
    db_path: string = '~/Library/Application Support/gomuks/gomuks.db' # Path to the gomuks database
] {
    get-room-servers $room_id $db_path | get server
}

# Example usage:
# get-room-servers "!main-1:continuwuity.org"
# get-active-servers "!main-1:continuwuity.org"
# get-server-breakdown "!main-1:continuwuity.org"
# list-room-servers "!main-1:continuwuity.org"
# get-servers-multi-room ["!main-1:continuwuity.org", "!offtopic-1:continuwuity.org"]