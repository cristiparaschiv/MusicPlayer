// @name       Quick Favorites Playlist
// @description Creates a playlist from your favorite tracks
// @author     Orange Music Player

var favorites = orange.library.searchTracks('');
var favTracks = [];

for (var i = 0; i < favorites.length; i++) {
    if (favorites[i].isFavorite) {
        favTracks.push(favorites[i]);
    }
}

console.log('Found ' + favTracks.length + ' favorite tracks');

if (favTracks.length > 0) {
    orange.playlists.create('My Favorites (Script)');
    console.log('Created playlist: My Favorites (Script)');
}
