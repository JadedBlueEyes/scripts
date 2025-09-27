# All server versions
do {|destinations_cache|
    let modified_date = ls $destinations_cache | get modified | get 0;
    let destinations_table = open $destinations_cache | from csv --separator "|" --trim all | where {|s| ($s.Expires | into datetime) > $modified_date } | select "Server Name" "Destination" "Hostname" "Expires";
    let servers_table = $destinations_table | par-each --threads 20  {|s| try {http get -m 10sec $'https://($s.Destination)/_matrix/federation/v1/version' | select server.name server.version | insert FederationOK true } catch { {FederationOK: false} } | insert ServerName $s."Server Name"};
    $servers_table | to msgpackz | save servers.msgpackz;
    echo $servers_table
} "/Users/jade/Downloads/output(3).md"


# All support files
do {|destinations_cache|
    let modified_date = ls $destinations_cache | get modified | get 0;
    let destinations_table = open $destinations_cache | from csv --separator "|" --trim all | where {|s| ($s.Expires | into datetime) > $modified_date } | select "Server Name" "Destination" "Hostname" "Expires";
    let support_table = $destinations_table | par-each --threads 20  {|s| try {http get -m 10sec $'https://($s."Server Name")/.well-known/matrix/support' | insert SupportOK true } catch { {SupportOK: false} } | insert ServerName $s."Server Name"};
    $support_table | to msgpackz | save support.msgpackz;
    echo $support_table
} "/Users/jade/Downloads/output(3).md"

do {|servers|
    let support_table = $servers | par-each --threads 20  {|s| try {http get -m 10sec $'https://($s.ServerName)/.well-known/matrix/support' | insert SupportOK true } catch { {SupportOK: false} } | insert ServerName $s.ServerName};
    $support_table | to msgpackz | save support.msgpackz;
    echo $support_table
} (open everyone-2.csv | where {|s| $s."server.name" | str downcase | str contains  "continuwuity" } )

# open everyone.json
open servers.msgpackz | from msgpackz | where {|s| $s.FederationOK} | sort-by "ServerName" | sort-by FederationOK | sort-by "server.version" | sort-by "server.name" | to csv | save everyone.csv

let vuln_versions = open "/Users/jade/Code/scripts/vulerable_commits" | lines
let vuln_servers = open ../scripts/everyone.csv | where {|s| $s."server.name" | str downcase | str contains  "continuwuity" } | each {|s| $s."server.version" | parse --regex '^\s*(?<name>[^( ]+)(?:$|\s+)(?:\((?<commit>\w+)(?:,?\s+.*)?\))?' | insert server_name $s.ServerName } | flatten | where {|s| $s.commit != "" } | each {|s| insert commit_message (git log --format=%B -n 1 $s.commit | str trim | lines | first) | insert commit_date (git show -s --format=%ci $s.commit | into datetime) } | sort-by commit_date | where {|s| $vuln_versions | any {|v| $v |str contains $s.commit} }


get-active-servers "!main-1:continuwuity.org" | par-each --threads 5  {|s| http get $'https://federationtester.matrix.org/api/report?server_name=($s.server)' | insert ServerName $s.server} | to msgpackz | save res.msgpackz

open res.msgpackz | from msgpackz| select -i ServerName Version.name Version.version FederationOK WellKnownResult."m.server" | to csv | save servers.csv

# All server versions, but with an actual resolver
do {|destinations_cache|
    let modified_date = ls $destinations_cache | get modified | get 0;
    let destinations_table = open $destinations_cache | from csv --separator "|" --trim all | where {|s| ($s.Expires | into datetime) > $modified_date } | select "Server Name" "Destination" "Hostname" "Expires";
    let servers_table = $destinations_table | each {|s| sleep 100ms; $s } | par-each --threads 40  {|s| try { http get $'https://federationtester.matrix.org/api/report?server_name=($s."Server Name")' } catch { {FederationOK: false} } | insert ServerName $s."Server Name"};
    $servers_table | to msgpackz | save res.msgpackz;
    echo $servers_table
} "/Users/jade/Downloads/output(3).md"


find-users-from-servers "" ($vuln_servers | get server_name) | group-by user_id --to-table

find-users-from-servers "!main-1:continuwuity.org" (["continuwuity.org"]) |  each {|s| $"[($s.server)]\(https://matrix.to/#/($s.user_id|url encode ))"} |str join ", "
# open servers.csv | where {|s| $s."Version.version" | str starts-with "0.5.0-rc.5" } | get ServerName
find-users-from-servers "!hyuEWFORfWYLZitABm:chatbrainz.org" (["chatbrainz.org"]) | where {|s| $s.user_id !~ "^@(_discord|irc)_" } |  each {|s| $"[($s.content_parsed | get -i displayname | default $s.user_id)]\(https://matrix.to/#/($s.user_id|url encode ))"} |str join ", "


let version_sig = {Version.name: "", Version.version: ""} | describe; open ../scripts/res.msgpackz | from msgpackz | where ($it| select Version.name Version.version -i | describe) == $version_sig | where {|s| $s.Version.name | str downcase | str contains  "continuwuity" } | each {|s| $s.Version.version | parse --regex '^\s*(?<name>[^( ]+)(?:$|\s+)(?:\((?<commit>\w+)(?:,?\s+.*)?\))?' | insert server_name $s.ServerName } | flatten | where {|s| $s.commit != "" } | each {|s| insert commit_message (git log --format=%B -n 1 $s.commit | str trim | lines | first) | insert commit_date (git show -s --format=%ci $s.commit | into datetime) } | sort-by commit_date


open ('~/Library/Application Support/gomuks/gomuks.db' | path expand) | query db ('SELECT DISTINCT r.room_id,
       r.name,
       json_extract(e.content, '$.users."@jade:ellis.link"') as power_level
FROM room r
INNER JOIN current_state cs ON r.room_id = cs.room_id
INNER JOIN event e ON cs.event_rowid = e.rowid
WHERE cs.event_type = 'm.room.power_levels'
  AND cs.state_key = ''
  AND json_extract(e.content, '$.users."@jade:ellis.link"') IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM current_state cs2
    WHERE cs2.room_id = r.room_id
      AND cs2.event_type = 'uk.half-shot.bridge'
  );
')

# TODO: Filter out membership restricted to a invite-only room
open ('~/Library/Application Support/gomuks/gomuks.db' | path expand) | query db ('
SELECT DISTINCT r.room_id,
       r.name,
       json_extract(e.content, '$.users."@jade:ellis.link"') as power_level
FROM room r
INNER JOIN current_state cs ON r.room_id = cs.room_id
INNER JOIN event e ON cs.event_rowid = e.rowid
WHERE cs.event_type = 'm.room.power_levels'
  AND cs.state_key = ''
  AND json_extract(e.content, '$.users."@jade:ellis.link"') IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM current_state cs2
    INNER JOIN event e2 ON cs2.event_rowid = e2.rowid
    WHERE cs2.room_id = r.room_id
      AND cs2.event_type = 'm.room.join_rules'
      AND cs2.state_key = ''
      AND json_extract(e2.content, '$.join_rule') = 'invite'
  );

')
