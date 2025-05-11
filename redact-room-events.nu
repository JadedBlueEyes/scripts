


# Query the database for events that need to be redacted
def get-redactable-events [
    room_ids: list<string>,
    sender_pattern: string,
    db_path: string = '~/Library/Application Support/gomuks/gomuks.db'
] {
    open ($db_path | path expand) | query db "
    select event_id, room_id
    from event
    where room_id in (SELECT value FROM json_each(:room_ids))
    and sender like :sender_pattern and content != '{}'
    and type = 'm.room.message'
    AND NOT EXISTS (
        SELECT 1
        FROM event r
        WHERE r.type = 'm.room.redaction'
        AND json_extract(r.content, '$.redacts') = event.event_id
        AND r.room_id = event.room_id
    )
    " -p { room_ids: ($room_ids | to json), sender_pattern: $sender_pattern }
}


# Process all events needing redaction
def redact-all-events [
    homeserver: string,
    access_token: string,
    room_ids: list<string>,
    sender_pattern: string
] {
    get-redactable-events $room_ids $sender_pattern
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

# get-redactable-events ["!main-1:continuwuity.org", "!offtopic-1:continuwuity.org", ] "@%:ellis.link"

filter-unredacted-events ["$7r8YNKrZ9rs8I_Qy5b1XFSknhSBMZ5fVoCjYjODqjYM", "$sPcEOoUTtz4S0vdaBJNMVnSBSfEmtljcKxFj4KWBo_4"] "!main-1:continuwuity.org"
