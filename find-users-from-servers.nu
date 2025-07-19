#!/usr/bin/env nu

# Find users from specific servers in a room
def find-users-from-servers [
    room_id: string,                    # Room ID to search in
    servers: list<string>,              # List of server domains to find users from
    db_path: string = '~/Library/Application Support/gomuks/gomuks.db' # Path to the gomuks database
] {
    find-users-from-servers-multi-room [$room_id] $servers $db_path
}

# Find all users from specific servers across multiple rooms
def find-users-from-servers-multi-room [
    room_ids: list<string>,             # List of room IDs to search in
    servers: list<string>,              # List of server domains to find users from
    db_path: string = '~/Library/Application Support/gomuks/gomuks.db' # Path to the gomuks database
] {
    # Build the SQL condition for server matching
    let server_conditions = $servers | each { |server| $"state_key LIKE '%:($server)'" } | str join " OR "

    # Query the database for current room members from the specified servers
    open ($db_path | path expand) | query db $"
        SELECT DISTINCT room_id, state_key as user_id, membership
        FROM current_state WHERE
        room_id IN \(SELECT value FROM json_each\(:room_ids)) AND
        event_type = 'm.room.member'
        AND \(($server_conditions)\)
        ORDER BY room_id, state_key
    " -p { room_ids: ($room_ids | to json) } | insert server { |row|
        $row.user_id | str replace --regex '^.*:(.*)$' '${1}'
    }
}
def find-users-from-all-servers [
    servers: list<string>,              # List of server domains to find users from
    db_path: string = '~/Library/Application Support/gomuks/gomuks.db' # Path to the gomuks database
] {
    # Build the SQL condition for server matching
    let server_conditions = $servers | each { |server| $"state_key LIKE '%:($server)'" } | str join " OR "

    # Query the database for current room members from the specified servers
    open ($db_path | path expand) | query db $"
        SELECT DISTINCT room_id, state_key as user_id, membership
        FROM current_state WHERE
        event_type = 'm.room.member'
        AND \(($server_conditions)\)
        ORDER BY room_id, state_key
    "
    # -p { room_ids: ($room_ids | to json) }
    | insert server { |row|
        $row.user_id | str replace --regex '^.*:(.*)$' '${1}'
    }
}

# Get only active members (joined) from specific servers
def get-active-users-from-servers [
    room_id: string,                    # Room ID to search in
    servers: list<string>,              # List of server domains to find users from
    db_path: string = '~/Library/Application Support/gomuks/gomuks.db' # Path to the gomuks database
] {
    find-users-from-servers $room_id $servers $db_path | where membership == "join"
}

# Get user counts by server from a room
def get-user-counts-by-server [
    room_id: string,                    # Room ID to search in
    servers: list<string>,              # List of server domains to count users from
    db_path: string = '~/Library/Application Support/gomuks/gomuks.db' # Path to the gomuks database
] {
    find-users-from-servers $room_id $servers $db_path
    | insert server { |row|
        $row.user_id | str replace --regex '^.*:(.*)$' '${1}'
    }
    | group-by server membership
    | transpose server data
    | each { |row|
        {
            server: $row.server,
            joined: ($row.data | get -i join | default [] | length),
            left: ($row.data | get -i leave | default [] | length),
            banned: ($row.data | get -i ban | default [] | length),
            invited: ($row.data | get -i invite | default [] | length),
            total: ($row.data | values | flatten | length)
        }
    }
}

# Example usage:
# find-users-from-servers "!main-1:continuwuity.org" ["continuwuity.org", "explodie.org"]
# get-active-users-from-servers "!main-1:continuwuity.org" ["continuwuity.org", "explodie.org"]
# get-user-counts-by-server "!main-1:continuwuity.org" ["continuwuity.org", "explodie.org"]
# find-users-from-servers-multi-room ["!main-1:continuwuity.org", "!offtopic-1:continuwuity.org"] ["continuwuity.org", "explodie.org"]
# find-users-from-servers "!main-1:continuwuity.org" (open servers.csv | where {|s| $s.version | str starts-with "0.5.0-rc.5" } | get homeserver)
# find-users-from-servers "!main-1:continuwuity.org" (open servers.csv | where {|s| $s.version | str starts-with "0.5.0-rc.5" } | get homeserver) |  each {|s| $"[($s.server)]\(https://matrix.to/#/($s.user_id|url encode ))"} |str join ", "
