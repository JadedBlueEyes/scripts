#!/usr/bin/env -S nu

def ts [] {
    date now | format date "%0s%f"
}

def "main send_message" [homeserver, access_token, room_id, msg] {
    return (http put $"($homeserver)/_matrix/client/v3/rooms/($room_id)/send/m.room.message/(ts)"
    --headers [
        User-Agent "matrix-cli"
        Accept "application/json"
        Authorization $"Bearer ($access_token)"
        Content-Type "application/json"
    ]
    # -t "application/json"
    $msg)
}
def "main login" [homeserver, user, password] {
    return (http post $"($homeserver)/_matrix/client/v3/login"
    --headers [
        User-Agent "matrix-cli"
        Accept "application/json"
    ]
    -t "application/json"
    {
        "type":"m.login.password",
        "identifier": {
            "type":"m.id.user",
            "user":$user
        },
        "password":$password
    })
}
def main [] {
    echo "Hello World!"
}