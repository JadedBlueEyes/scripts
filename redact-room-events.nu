


# Query the database for events that need to be redacted
def get-redactable-events [
    room_ids: list<string>,
    filter: string,
    params?: record,
    db_path: string = '~/Library/Application Support/gomuks/gomuks.db'
] {
    open ($db_path | path expand) | query db ("
    select event_id, room_id, content
    from event
    where room_id in (SELECT value FROM json_each(:room_ids))
    and " + $filter + " and content != '{}'
    and type = 'm.room.message'
    AND NOT EXISTS (
        SELECT 1
        FROM event r
        WHERE r.type = 'm.room.redaction'
        AND json_extract(r.content, '$.redacts') = event.event_id
        AND r.room_id = event.room_id
    )
    ") -p ($params | merge { room_ids: ($room_ids | to json) })
}


# Process all events needing redaction
def redact-all-events [
    homeserver: string,
    access_token: string,
    room_ids: list<string>,
    filter: string
] {
    get-redactable-events $room_ids $filter
    | each { |row|
        ./scripts/matrix.nu redact $homeserver $access_token $row.room_id $row.event_id 'spam'
    }
}


# Filter already-redacted events from a list
def filter-unredacted-events [
    target_event_ids: list<string>,    # List of event IDs to check and potentially redact
    room_id: string,                   # Room ID to check & redact in
    db_path: string = '~/Library/Application Support/gomuks/gomuks.db' # Path to the gomuks database
] {
    # Find which of the target_event_ids are not yet redacted and get their room_id
    let events_to_redact = open ($db_path | path expand) | query db "
        SELECT value as original_event_id
        FROM json_each(:target_event_ids_json)
        WHERE NOT EXISTS (
            SELECT 1
            FROM event r
            WHERE r.type = 'm.room.redaction'
            AND json_extract(r.content, '$.redacts') = original_event_id
            AND r.room_id = :room_id
        );
    " -p { target_event_ids_json: ($target_event_ids | to json), room_id: $room_id }

    return $events_to_redact
}


# Execute the redaction process
# redact-all-events $env.MATRIX_HOME_SERVER $env.MATRIX_ACCESS_TOKEN ["!main-1:continuwuity.org"]

# get-redactable-events ["!main-1:continuwuity.org", "!offtopic-1:continuwuity.org", ] 'sender like "@%:ellis.link"'

# filter-unredacted-events ["$7r8YNKrZ9rs8I_Qy5b1XFSknhSBMZ5fVoCjYjODqjYM", "$sPcEOoUTtz4S0vdaBJNMVnSBSfEmtljcKxFj4KWBo_4"] "!main-1:continuwuity.org"


# Get a list of users who joined a room after a specific timestamp
def get-room-members-after-timestamp [
    homeserver: string,      # Matrix homeserver URL
    access_token: string,    # Matrix access token
    room_id: string,         # Room ID to check
    timestamp: int,           # Unix timestamp in milliseconds
    membership: string,       # Membership status to filter by
] {
    http get $"($homeserver)/_matrix/client/v3/rooms/($room_id)/state" --headers {Authorization: $"Bearer ($access_token)"} |
      where type == "m.room.member" and origin_server_ts >= $timestamp and content.membership == $membership |
      get state_key
}

# get-redactable-events ["!CHHeCdeLwEtmDAOcZg:fachschaften.org", ] "sender in (SELECT value FROM json_each(:banned_users))" { banned_users: (get-room-members-after-timestamp $env.MATRIX_HOME_SERVER $env.MATRIX_ACCESS_TOKEN "!CHHeCdeLwEtmDAOcZg:fachschaften.org" ((((date now) - 4hr) | into int) // 1000000) "ban" | to json)} | get event_id| str join "\n"

# get-redactable-events ["!main-1:continuwuity.org", "!offtopic-1:continuwuity.org", ] "@%:matrix.sucroid.com" | each { |row|
#     ./scripts/matrix.nu redact $env.MATRIX_HOME_SERVER $env.MATRIX_ACCESS_TOKEN $row.room_id $row.event_id 'spam'
# }

get-redactable-events ["!GNPBRmjZKKEGszhMtB:matrix.org", ] "json_extract(content, '$.body') LIKE '%'" {} | get event_id| str join "\n" | save events.txt
# get-redactable-events ["!GNPBRmjZKKEGszhMtB:matrix.org", ] "json_extract(content, '$.body') LIKE '%'" {}
