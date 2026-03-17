// @name       Auto Jazz EQ
// @description Logs track info when a jazz track starts playing
// @author     Orange Music Player
// @event      trackChanged

orange.on('trackChanged', function(track) {
    if (!track) return;

    console.log('Now playing: ' + track.title + ' by ' + track.artist);

    if (track.genre && track.genre.toLowerCase().indexOf('jazz') !== -1) {
        console.log('Jazz detected! Genre: ' + track.genre);
    }
});
