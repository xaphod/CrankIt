//
//  Media.swift
//  DenonVolume
//
//  Created by Tim Carr on 2024-12-01.
//  Copyright © 2024 Solodigitalis. All rights reserved.
//


/*
 heos://player/get_now_playing_media?pid=-1320513458
 --> the payload part of
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

struct NowPlayingMedia : Codable {
    var song: String?
    var album: String?
    var artist: String
    var station: String?
    var image_url: String?
}

enum NowPlayingMediaNotificationKeys : String {
    case song
    case album
    case artist
    case mediaUrl
}
