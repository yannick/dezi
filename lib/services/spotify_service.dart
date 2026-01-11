import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:spotify_sdk/spotify_sdk.dart';
import 'package:spotify_sdk/models/player_state.dart';

class SpotifyService {
  static String get clientId => dotenv.env['SPOTIFY_CLIENT_ID'] ?? '';
  static String get clientSecret => dotenv.env['SPOTIFY_CLIENT_SECRET'] ?? '';
  static const String redirectUrl = 'spotify-sdk://auth';

  static Future<bool> connectToSpotify() async {
    try {
      developer.log('=== Starting Spotify Authentication ===');
      developer.log('Client ID: ${clientId.substring(0, 8)}...');
      developer.log('Redirect URL: $redirectUrl');

      // Step 1: Get authentication token (this will trigger OAuth flow if needed)
      developer.log('Step 1: Getting authentication token...');
      final token = await SpotifySdk.getAuthenticationToken(
        clientId: clientId,
        redirectUrl: redirectUrl,
        scope: 'app-remote-control,user-modify-playback-state,'
            'user-read-currently-playing,user-read-playback-state',
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          developer.log('ERROR: Auth token request timed out after 30 seconds');
          throw TimeoutException('Spotify authentication timed out');
        },
      );

      developer.log('Step 1 Complete: Got token: ${token?.substring(0, 10)}...');

      // Step 2: Connect to Spotify Remote
      developer.log('Step 2: Connecting to Spotify Remote...');
      final connected = await SpotifySdk.connectToSpotifyRemote(
        clientId: clientId,
        redirectUrl: redirectUrl,
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          developer.log('ERROR: Remote connection timed out after 15 seconds');
          throw TimeoutException('Spotify remote connection timed out');
        },
      );

      developer.log('=== Successfully Connected to Spotify: $connected ===');
      return connected;
    } on TimeoutException catch (e) {
      developer.log(
        'Spotify connection timed out - this usually means the auth flow did not complete',
        name: 'SpotifyService',
        error: e,
      );
      return false;
    } catch (e, s) {
      developer.log(
        'Failed to connect to Spotify',
        name: 'SpotifyService',
        error: e,
        stackTrace: s,
      );

      // If connection fails, show user-friendly error
      final errorStr = e.toString();
      if (errorStr.contains('AUTHENTICATION_SERVICE_UNAVAILABLE')) {
        developer.log(
          'Make sure Spotify app is installed, logged in, and you have Premium',
          name: 'SpotifyService',
        );
      } else if (errorStr.contains('UserNotAuthorizedException')) {
        developer.log(
          'User needs to authorize the app. Package name and SHA-1 must be registered in Spotify Dashboard.',
          name: 'SpotifyService',
        );
      }
      return false;
    }
  }

  static Future<void> playTrack(String trackUri) async {
    try {
      await SpotifySdk.play(spotifyUri: trackUri);
      developer.log('Playing track: $trackUri');
    } catch (e, s) {
      developer.log(
        'Failed to play track',
        name: 'SpotifyService',
        error: e,
        stackTrace: s,
      );
      rethrow;
    }
  }

  static Future<void> pause() async {
    try {
      await SpotifySdk.pause();
      developer.log('Paused playback');
    } catch (e, s) {
      developer.log(
        'Failed to pause',
        name: 'SpotifyService',
        error: e,
        stackTrace: s,
      );
    }
  }

  static Future<void> resume() async {
    try {
      await SpotifySdk.resume();
      developer.log('Resumed playback');
    } catch (e, s) {
      developer.log(
        'Failed to resume',
        name: 'SpotifyService',
        error: e,
        stackTrace: s,
      );
    }
  }

  static String extractTrackUri(String url) {
    developer.log('Extracting track URI from: $url');

    // Already a spotify URI
    if (url.contains('spotify:track:')) {
      return url;
    }

    // Custom dezi.re/sp/ format
    if (url.contains('dezi.re/sp/')) {
      final trackId = url.split('/sp/')[1].split('?')[0].split('/')[0];
      final uri = 'spotify:track:$trackId';
      developer.log('Extracted from dezi.re format: $uri');
      return uri;
    }

    // Standard Spotify open.spotify.com URL
    if (url.contains('open.spotify.com/track/')) {
      final trackId = url.split('/track/')[1].split('?')[0];
      final uri = 'spotify:track:$trackId';
      developer.log('Extracted from open.spotify.com: $uri');
      return uri;
    }

    // Generic track/ format
    if (url.contains('track/')) {
      final trackId = url.split('track/')[1].split('?')[0];
      final uri = 'spotify:track:$trackId';
      developer.log('Extracted from generic format: $uri');
      return uri;
    }

    // Assume it's just a track ID
    developer.log('Assuming raw track ID: $url');
    return 'spotify:track:$url';
  }

  static Stream<PlayerState> getPlayerStateStream() {
    return SpotifySdk.subscribePlayerState();
  }

  static Future<void> disconnect() async {
    try {
      await SpotifySdk.disconnect();
      developer.log('Disconnected from Spotify');
    } catch (e, s) {
      developer.log(
        'Failed to disconnect',
        name: 'SpotifyService',
        error: e,
        stackTrace: s,
      );
    }
  }
}
