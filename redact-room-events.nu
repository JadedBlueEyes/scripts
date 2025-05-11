


# Query the database for events that need to be redacted
def get-redactable-events [
    room_ids: list<string>,
    sender_pattern: string,
    db_path: string = '~/Library/Application Support/gomuks/gomuks.db'
] {
    open ($db_path | path expand) | query db "
    select event_id, room_id 
    from event 
    where room_id in (SELECT value FROM json_each(:room_ids)) and sender like :sender_pattern and content != '{}' and type = 'm.room.message' and event_id NOT IN \(SELECT json_extract\(content, '$.redacts') FROM event WHERE type = 'm.room.redaction' AND room_id = event.room_id)
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


# Execute the redaction process
# redact-all-events $env.MATRIX_HOME_SERVER $env.MATRIX_ACCESS_TOKEN ["!main-1:continuwuity.org"]

get-redactable-events ["!main-1:continuwuity.org", "!offtopic-1:continuwuity.org", ] "@%:ellis.link"