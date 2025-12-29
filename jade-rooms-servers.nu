#!/usr/bin/env nu

# Jade's Room and Server Analysis Script
#
# This script finds all Matrix rooms that a specified user has joined and analyzes
# the servers (homeservers) of other users in those rooms. It provides various
# functions to explore room membership and server distribution.
#
# The user to analyze is set by the JADE_USER constant at the top of the file.
#
# Main Functions:
# - jade-rooms-servers: Returns table with room_id and up to 10 servers per room (excludes user's server)
# - jade-rooms-servers-detailed: Includes server user counts (excludes user's server)
# - jade-room-count: Total number of rooms the user is in
# - jade-all-servers: All unique servers across user's rooms with stats (excludes user's server)
# - test-script: Runs sample analysis
#
# Database Schema Requirements:
# - Uses gomuks SQLite database with current_state table
# - Expects standard Matrix room membership events (m.room.member)
# - Filters for membership = 'join' and excludes the specified user and their server from results
#
# Usage:
# ./jade-rooms-servers.nu                                    # Run main function
# nu -c "source jade-rooms-servers.nu; jade-room-count"      # Get room count
# nu -c "source jade-rooms-servers.nu; test-script"          # Run full analysis
#
# To analyze a different user, change the JADE_USER constant below.

# The user to analyze - change this to analyze a different user
const JADE_USER = "@jade:ellis.link"

# Find all rooms joined by the specified user and list servers of other joined users
def jade-rooms-servers [
    db_path: string = '/Users/jade/Library/Application Support/gomuks-archive/gomuks.db' # Path to the gomuks database
] {
    let jade_user = $JADE_USER
    let jade_server = ($jade_user | str replace --regex '^@[^:]+:(.*)$' '${1}')

    # Pre-calculate server room counts once for efficiency
    let server_room_counts = (open ($db_path | path expand) | query db "
        SELECT
            substr(state_key, instr(state_key, ':') + 1) as server,
            COUNT(DISTINCT room_id) as room_count
        FROM current_state
        WHERE event_type = 'm.room.member'
        AND membership = 'join'
        AND state_key LIKE '@%:%'
        AND state_key != :jade_user
        AND substr(state_key, instr(state_key, ':') + 1) != :jade_server
        GROUP BY server
    " -p { jade_user: $jade_user, jade_server: $jade_server })

    # Create a lookup map for server room counts
    let server_counts_map = ($server_room_counts | reduce -f {} { |row, acc|
        $acc | insert $row.server $row.room_count
    })

    # First get all of jade's rooms with room metadata
    let jade_rooms = (open ($db_path | path expand) | query db "
        SELECT DISTINCT cs.room_id, r.name, r.topic, r.avatar, r.canonical_alias, r.sorting_timestamp
        FROM current_state cs
        LEFT JOIN room r ON cs.room_id = r.room_id
        WHERE cs.state_key = :jade_user
        AND cs.event_type = 'm.room.member'
        AND cs.membership = 'join'
        ORDER BY cs.room_id
    " -p { jade_user: $jade_user })

    # Get all room-server combinations for jade's rooms in one query
    let room_servers = (open ($db_path | path expand) | query db "
        SELECT
            cs.room_id,
            substr(cs.state_key, instr(cs.state_key, ':') + 1) as server
        FROM current_state cs
        WHERE cs.room_id IN (
            SELECT DISTINCT room_id
            FROM current_state
            WHERE state_key = :jade_user
            AND event_type = 'm.room.member'
            AND membership = 'join'
        )
        AND cs.event_type = 'm.room.member'
        AND cs.membership = 'join'
        AND cs.state_key LIKE '@%:%'
        AND cs.state_key != :jade_user
        AND substr(cs.state_key, instr(cs.state_key, ':') + 1) != :jade_server
        ORDER BY cs.room_id
    " -p { jade_user: $jade_user, jade_server: $jade_server }
    | group-by room_id)

    # Process all jade's rooms, including those with no other users
    $jade_rooms | each { |room_row|
        let room_id = $room_row.room_id
        let room_data = ($room_servers | get -o $room_id | default [])

        let servers = if ($room_data | length) > 0 {
            ($room_data
                | get server
                | uniq
                | each { |server| { server: $server, room_count: ($server_counts_map | get -o $server | default 0) } }
                | sort-by room_count -r
                | first 10
                | get server)
        } else {
            []
        }

        {
            room_id: $room_id,
            name: $room_row.name,
            topic: $room_row.topic,
            avatar: $room_row.avatar,
            canonical_alias: $room_row.canonical_alias,
            sorting_timestamp: $room_row.sorting_timestamp,
            servers: $servers
        }
    }
}

# Get detailed server info with user counts for jade's rooms
def jade-rooms-servers-detailed [
    db_path: string = '/Users/jade/Library/Application Support/gomuks-archive/gomuks.db' # Path to the gomuks database
] {
    let jade_user = $JADE_USER
    let jade_server = ($jade_user | str replace --regex '^@[^:]+:(.*)$' '${1}')


    # Pre-calculate server room counts once for efficiency
    let server_room_counts = (open ($db_path | path expand) | query db "
        SELECT
            substr(state_key, instr(state_key, ':') + 1) as server,
            COUNT(DISTINCT room_id) as room_count
            FROM current_state
            WHERE event_type = 'm.room.member'
            AND membership = 'join'
            AND state_key LIKE '@%:%'
            AND state_key != :jade_user
            AND substr(state_key, instr(state_key, ':') + 1) != :jade_server
            GROUP BY server
        " -p { jade_user: $jade_user, jade_server: $jade_server })

    # Create a lookup map for server room counts
    let server_counts_map = ($server_room_counts | reduce -f {} { |row, acc|
        $acc | insert $row.server $row.room_count
    })

    # First get all of jade's rooms
    let jade_rooms = (open ($db_path | path expand) | query db "
        SELECT DISTINCT room_id
        FROM current_state
        WHERE state_key = :jade_user
        AND event_type = 'm.room.member'
        AND membership = 'join'
        ORDER BY room_id
    " -p { jade_user: $jade_user })

    # Get all room-server combinations with user counts for jade's rooms
    let room_servers = (open ($db_path | path expand) | query db "
        SELECT
            cs.room_id,
            substr(cs.state_key, instr(cs.state_key, ':') + 1) as server,
            COUNT(*) as user_count
        FROM current_state cs
        WHERE cs.room_id IN (
            SELECT DISTINCT room_id
            FROM current_state
            WHERE state_key = :jade_user
            AND event_type = 'm.room.member'
            AND membership = 'join'
        )
        AND cs.event_type = 'm.room.member'
        AND cs.membership = 'join'
        AND cs.state_key LIKE '@%:%'
        AND cs.state_key != :jade_user
        AND substr(cs.state_key, instr(cs.state_key, ':') + 1) != :jade_server
        GROUP BY cs.room_id, server
        ORDER BY cs.room_id
    " -p { jade_user: $jade_user, jade_server: $jade_server }
    | group-by room_id)

    # Process all jade's rooms, including those with no other users
    $jade_rooms | each { |room_row|
        let room_id = $room_row.room_id
        let room_data = ($room_servers | get -o $room_id | default [])

        let server_info = if ($room_data | length) > 0 {
            ($room_data
                | each { |row| $row | insert room_count ($server_counts_map | get -o $row.server | default 0) }
                | sort-by room_count -r user_count -r server
                | first 10)
        } else {
            []
        }

        {
            room_id: $room_id,
            servers: ($server_info | get -o server | default []),
            server_details: (if ($server_info | length) > 0 { $server_info | select server user_count } else { [] })
        }
    }
}

# Get a summary count of rooms jade is in
def jade-room-count [
    db_path: string = '/Users/jade/Library/Application Support/gomuks-archive/gomuks.db' # Path to the gomuks database
] {
    let jade_user = $JADE_USER

    open ($db_path | path expand) | query db "
        SELECT COUNT(DISTINCT room_id) as room_count
        FROM current_state
        WHERE state_key = :jade_user
        AND event_type = 'm.room.member'
        AND membership = 'join'
    " -p { jade_user: $jade_user }
}

# Get all unique servers across all of jade's rooms
def jade-all-servers [
    db_path: string = '/Users/jade/Library/Application Support/gomuks-archive/gomuks.db' # Path to the gomuks database
] {
    let jade_user = $JADE_USER
    let jade_server = ($jade_user | str replace --regex '^@[^:]+:(.*)$' '${1}')

    open ($db_path | path expand) | query db "
        SELECT
            substr(cs.state_key, instr(cs.state_key, ':') + 1) as server,
            COUNT(DISTINCT cs.state_key) as total_users,
            COUNT(DISTINCT cs.room_id) as room_count
        FROM current_state cs
        WHERE cs.room_id IN (
            SELECT DISTINCT room_id
            FROM current_state
            WHERE state_key = :jade_user
            AND event_type = 'm.room.member'
            AND membership = 'join'
        )
        AND cs.event_type = 'm.room.member'
        AND cs.membership = 'join'
        AND cs.state_key LIKE '@%:%'
        AND cs.state_key != :jade_user
        AND substr(cs.state_key, instr(cs.state_key, ':') + 1) != :jade_server
        GROUP BY server
        ORDER BY total_users DESC, server ASC
    " -p { jade_user: $jade_user, jade_server: $jade_server }
}

# Main function - returns the requested table format
def main [
    db_path: string = '/Users/jade/Library/Application Support/gomuks-archive/gomuks.db' # Path to the gomuks database
] {
    jade-rooms-servers $db_path
}

# Test the script with some example queries
def test-script [] {
    let jade_user = $JADE_USER
    let jade_server = ($jade_user | str replace --regex '^@[^:]+:(.*)$' '${1}')

    print $"=== ($jade_user)'s Room and Server Analysis ==="
    print $"Note: Excludes servers from ($jade_server) domain"
    print ""

    let room_count = (jade-room-count | get room_count | first)
    print $"Total rooms ($jade_user) is joined to: ($room_count)"
    print ""

    print $"Top 10 servers across all ($jade_user)'s rooms \(excluding ($jade_server)\):"
    jade-all-servers | first 10 | table
    print ""

    print "Sample of rooms with multiple servers (first 3):"
    jade-rooms-servers | where ($it.servers | length) > 1 | first 3 | table
    print ""

    print "Rooms with most diverse server representation:"
    jade-rooms-servers-detailed
    | where ($it.servers | length) > 5
    | first 5
    | select room_id servers
    | table
}

# Example usage:
# ./jade-rooms-servers.nu
# jade-rooms-servers
# jade-rooms-servers-detailed
# jade-room-count
# jade-all-servers
# test-script

# $servers | where {|i| ($i.servers | length) == 0 and ($i.room_id | parse --regex '![a-zA-Z0-9]{18}:ellis.link') == []}
