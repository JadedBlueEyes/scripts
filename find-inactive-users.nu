#!/usr/bin/env nu

# Find users in a room who are joined but haven't sent messages in a specified time period
def find-inactive-users [
    room_id: string,                    # Room ID to analyze
    months_inactive?: int = 6,          # Number of months of inactivity (default: 6)
    db_path: string = '~/Library/Application Support/gomuks/gomuks.db' # Path to the gomuks database
] {
    let cutoff_timestamp = ((date now | into int) / 1000000 - ($months_inactive * 30 * 24 * 60 * 60)) * 1000

    open ($db_path | path expand) | query db "
        SELECT
            cs.state_key as user_id,
            COALESCE(last_msg.last_message_time, 0) as last_message_timestamp,
            CASE
                WHEN last_msg.last_message_time IS NULL THEN 'Never sent a message'
                ELSE datetime(last_msg.last_message_time / 1000, 'unixepoch')
            END as last_message_date,
            CASE
                WHEN last_msg.last_message_time IS NULL THEN 'Never'
                ELSE printf('%.1f', (CAST(:current_time AS REAL) - CAST(last_msg.last_message_time AS REAL)) / (1000.0 * 60 * 60 * 24 * 30))
            END as months_since_last_message
        FROM current_state cs
        LEFT JOIN (
            SELECT
                sender,
                MAX(timestamp) as last_message_time
            FROM event
            WHERE room_id = :room_id
            AND (type = 'm.room.message' OR type = 'm.room.encrypted')
            AND state_key IS NULL
            AND redacted_by IS NULL
            GROUP BY sender
        ) last_msg ON cs.state_key = last_msg.sender
        WHERE cs.room_id = :room_id
        AND cs.event_type = 'm.room.member'
        AND cs.membership = 'join'
        AND (last_msg.last_message_time IS NULL OR last_msg.last_message_time < :cutoff_time)
        ORDER BY last_msg.last_message_time ASC NULLS FIRST, cs.state_key ASC
    " -p {
        room_id: $room_id,
        cutoff_time: $cutoff_timestamp,
        current_time: ((date now | into int) / 1000000 * 1000)
    }
}

# Find users who have never sent any messages in a room
def find-users-never-messaged [
    room_id: string,                    # Room ID to analyze
    db_path: string = '~/Library/Application Support/gomuks/gomuks.db' # Path to the gomuks database
] {
    open ($db_path | path expand) | query db "
        SELECT
            cs.state_key as user_id,
            'Never sent a message' as status
        FROM current_state cs
        LEFT JOIN (
            SELECT DISTINCT sender
            FROM event
            WHERE room_id = :room_id
            AND state_key IS NULL
            AND redacted_by IS NULL
        ) msg ON cs.state_key = msg.sender
        WHERE cs.room_id = :room_id
        AND cs.event_type = 'm.room.member'
        AND cs.membership = 'join'
        AND msg.sender IS NULL
        ORDER BY cs.state_key ASC
    " -p { room_id: $room_id }
}

# Get activity summary for all joined users in a room
def get-user-activity-summary [
    room_id: string,                    # Room ID to analyze
    db_path: string = '~/Library/Application Support/gomuks/gomuks.db' # Path to the gomuks database
] {
    let current_time = ((date now | into int) / 1000000 * 1000)

    open ($db_path | path expand) | query db "
        SELECT
            cs.state_key as user_id,
            COALESCE(msg_stats.message_count, 0) as total_messages,
            CASE
                WHEN msg_stats.last_message_time IS NULL THEN 'Never'
                ELSE datetime(msg_stats.last_message_time / 1000, 'unixepoch')
            END as last_message_date,
            CASE
                WHEN msg_stats.first_message_time IS NULL THEN 'Never'
                ELSE datetime(msg_stats.first_message_time / 1000, 'unixepoch')
            END as first_message_date,
            CASE
                WHEN msg_stats.last_message_time IS NULL THEN 'Never'
                ELSE printf('%.1f', (CAST(:current_time AS REAL) - CAST(msg_stats.last_message_time AS REAL)) / (1000.0 * 60 * 60 * 24))
            END as days_since_last_message
        FROM current_state cs
        LEFT JOIN (
            SELECT
                sender,
                COUNT(*) as message_count,
                MIN(timestamp) as first_message_time,
                MAX(timestamp) as last_message_time
            FROM event
            WHERE room_id = :room_id
            AND (type = 'm.room.message' OR type = 'm.room.encrypted')
            AND state_key IS NULL
            AND redacted_by IS NULL
            GROUP BY sender
        ) msg_stats ON cs.state_key = msg_stats.sender
        WHERE cs.room_id = :room_id
        AND cs.event_type = 'm.room.member'
        AND cs.membership = 'join'
        ORDER BY msg_stats.last_message_time DESC NULLS LAST, cs.state_key ASC
    " -p {
        room_id: $room_id,
        current_time: $current_time
    }
}

# Count inactive users by time periods
def count-inactive-users [
    room_id: string,                    # Room ID to analyze
    db_path: string = '~/Library/Application Support/gomuks/gomuks.db' # Path to the gomuks database
] {
    let current_time = ((date now | into int) / 1000000 * 1000)
    let one_month = (30 * 24 * 60 * 60 * 1000)
    let three_months = (3 * $one_month)
    let six_months = (6 * $one_month)
    let one_year = (12 * $one_month)

    open ($db_path | path expand) | query db "
        SELECT
            SUM(CASE WHEN msg_stats.last_message_time IS NULL THEN 1 ELSE 0 END) as never_messaged,
            SUM(CASE WHEN msg_stats.last_message_time IS NOT NULL AND msg_stats.last_message_time < :one_month_ago THEN 1 ELSE 0 END) as inactive_1_month,
            SUM(CASE WHEN msg_stats.last_message_time IS NOT NULL AND msg_stats.last_message_time < :three_months_ago THEN 1 ELSE 0 END) as inactive_3_months,
            SUM(CASE WHEN msg_stats.last_message_time IS NOT NULL AND msg_stats.last_message_time < :six_months_ago THEN 1 ELSE 0 END) as inactive_6_months,
            SUM(CASE WHEN msg_stats.last_message_time IS NOT NULL AND msg_stats.last_message_time < :one_year_ago THEN 1 ELSE 0 END) as inactive_1_year,
            COUNT(*) as total_joined_users
        FROM current_state cs
        LEFT JOIN (
            SELECT
                sender,
                MAX(timestamp) as last_message_time
            FROM event
            WHERE room_id = :room_id
            AND (type = 'm.room.message' OR type = 'm.room.encrypted')
            AND state_key IS NULL
            AND redacted_by IS NULL
            GROUP BY sender
        ) msg_stats ON cs.state_key = msg_stats.sender
        WHERE cs.room_id = :room_id
        AND cs.event_type = 'm.room.member'
        AND cs.membership = 'join'
    " -p {
        room_id: $room_id,
        one_month_ago: ($current_time - $one_month),
        three_months_ago: ($current_time - $three_months),
        six_months_ago: ($current_time - $six_months),
        one_year_ago: ($current_time - $one_year)
    }
}

# Example usage:
# find-inactive-users "!tAtvIGooaMuCBlrtKP:matrix.org" 6
# find-users-never-messaged "!tAtvIGooaMuCBlrtKP:matrix.org"
# get-user-activity-summary "!tAtvIGooaMuCBlrtKP:matrix.org"
# count-inactive-users "!tAtvIGooaMuCBlrtKP:matrix.org"

# Test the script with the specified room
def test-script [] {
    print "=== CORRECTED: Find Inactive Users Script ==="
    print $"Room: !tAtvIGooaMuCBlrtKP:matrix.org"
    print ""
    print "NOTE: Now includes encrypted messages (m.room.encrypted) in addition to plain messages"
    print ""

    print "1. Summary counts:"
    let summary = (count-inactive-users "!tAtvIGooaMuCBlrtKP:matrix.org")
    print $"- Total joined users: ($summary | get total_joined_users | first)"
    print $"- Never sent messages: ($summary | get never_messaged | first)"
    print $"- Inactive 6+ months: ($summary | get inactive_6_months | first)"
    print $"- Users who have sent messages: (($summary | get total_joined_users | first) - ($summary | get never_messaged | first))"
    print ""

    print "2. Users inactive for 6+ months (including those who never messaged):"
    let inactive_count = (find-inactive-users "!tAtvIGooaMuCBlrtKP:matrix.org" 6 | length)
    print $"Total inactive 6+ months: ($inactive_count)"
    print ""

    print "3. Recently active users (sent messages today):"
    let active_users = (get-user-activity-summary "!tAtvIGooaMuCBlrtKP:matrix.org" | where total_messages > 0 | where last_message_date =~ "2025-08-30")
    print $"Users active today: ($active_users | length)"
    if ($active_users | length) > 0 {
        $active_users | select user_id total_messages last_message_date | first 5 | table
    }
    print ""

    print "4. Sample of inactive users who never messaged (first 5):"
    find-users-never-messaged "!tAtvIGooaMuCBlrtKP:matrix.org" | first 5 | table
}
