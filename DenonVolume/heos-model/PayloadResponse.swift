//
//  GetPlayersResponse.swift
//  DenonVolume
//
//  Created by Tim Carr on 2024-12-01.
//  Copyright © 2024 Solodigitalis. All rights reserved.
//

// heos://player/get_players
/*
 {
   "heos": {
     "command": "player/get_players",
     "result": "success",
     "message": ""
   },
   "payload": [
     {
       "name": "Denon AVR-X3600H",
       "pid": -1320513458,
       "model": "Denon AVR-X3600H",
       "version": "3.34.410",
       "ip": "192.168.1.218",
       "network": "wifi",
       "lineout": 0,
       "serial": "BHA36190806276"
     }
   ]
 }
 */

/*
 heos://player/get_now_playing_media?pid=-1320513458
 {
   "heos": {
     "command": "player/get_now_playing_media",
     "result": "success",
     "message": "pid=-1320513458"
   },
   "payload": {
     "type": "station",
     "song": "Didn't Cha Know",
     "station": "Didn't Cha Know",
     "album": "Mama's Gun",
     "artist": "Erykah Badu",
     "image_url": "https://i.scdn.co/image/ab67616d0000b2730d934cb462fae5a26f829efb",
     "album_id": "1",
     "mid": "spotify:track:7pv80uUHfocFqfTytu1MVi",
     "qid": 1,
     "sid": 4
   },
   "options": [
     {
       "play": [
         {
           "id": 19,
           "name": "Add to HEOS Favorites"
         }
       ]
     }
   ]
 }
 */

struct PayloadResponse<T: Codable> : Codable {
    var payload: [T]
}
