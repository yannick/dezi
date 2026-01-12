import 'package:flutter/material.dart';
import 'package:spotify_sdk/spotify_sdk.dart';
import 'package:spotify_sdk/models/player_state.dart';
import '../services/spotify_service.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.spotifyUrl});

  final String spotifyUrl;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  bool _isConnected = false;
  String? _errorMessage;
  PlayerState? _playerState;
  late AnimationController _rotationController;
  bool _isDragging = false;
  bool _wasPlayingBeforeDrag = false;
  double _dragVelocity = 0.0;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final connected = await SpotifyService.connectToSpotify();

      if (!connected) {
        setState(() {
          _errorMessage = 'Failed to connect to Spotify';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _isConnected = true;
      });

      SpotifyService.getPlayerStateStream().listen((playerState) {
        if (mounted) {
          setState(() {
            _playerState = playerState;
          });
          // Control vinyl rotation based on playback state
          if (playerState.isPaused) {
            _rotationController.stop();
          } else {
            if (!_rotationController.isAnimating) {
              _rotationController.repeat();
            }
          }
        }
      });

      final trackUri = SpotifyService.extractTrackUri(widget.spotifyUrl);
      await SpotifyService.playTrack(trackUri);

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _togglePlayPause() async {
    if (_playerState?.isPaused ?? true) {
      await SpotifyService.resume();
    } else {
      await SpotifyService.pause();
    }
  }

  void _onVinylDragStart(DragStartDetails details) {
    setState(() {
      _isDragging = true;
      _wasPlayingBeforeDrag = !(_playerState?.isPaused ?? true);
      _dragVelocity = 0.0;
    });

    // Pause playback when user starts dragging
    if (_wasPlayingBeforeDrag) {
      SpotifyService.pause();
    }

    // Stop the automatic rotation
    _rotationController.stop();
  }

  void _onVinylDragUpdate(DragUpdateDetails details) {
    // Calculate rotational velocity based on drag distance
    // Using the center of the vinyl as pivot point
    final RenderBox box = context.findRenderObject() as RenderBox;
    final center = Offset(box.size.width / 2, box.size.height / 2);

    // Calculate angle change from drag delta
    final dx = details.delta.dx;
    final dy = details.delta.dy;

    // Convert linear drag to rotational velocity
    // Positive values = clockwise, negative = counter-clockwise
    final rotationalDelta = (dx - dy) / 300;

    setState(() {
      _dragVelocity = rotationalDelta;
    });

    // Manually advance the rotation based on drag
    final newValue = _rotationController.value + rotationalDelta;
    _rotationController.value = newValue % 1.0;
  }

  void _onVinylDragEnd(DragEndDetails details) {
    setState(() {
      _isDragging = false;
    });

    // Calculate fling velocity for smooth deceleration
    final velocity = details.velocity.pixelsPerSecond;
    final speed = velocity.distance;

    if (speed > 100) {
      // User flicked the vinyl - spin it with momentum
      final rotationalVelocity = speed / 1000;
      _rotationController.duration = Duration(
        milliseconds: (3000 / rotationalVelocity).round().clamp(500, 3000),
      );
      _rotationController.repeat();

      // Gradually return to normal speed
      Future.delayed(Duration(milliseconds: 1000), () {
        if (mounted && !_isDragging) {
          _rotationController.duration = const Duration(seconds: 3);
        }
      });
    }

    // Resume playback if it was playing before
    if (_wasPlayingBeforeDrag) {
      Future.delayed(Duration(milliseconds: 200), () {
        if (mounted && !_isDragging) {
          SpotifyService.resume();
        }
      });
    } else if (!(_playerState?.isPaused ?? true)) {
      // Resume normal rotation if playing
      _rotationController.repeat();
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    SpotifyService.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Now Playing',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    color: Color(0xFF1DB954),
                  ),
                  SizedBox(height: 24),
                  Text(
                    'Connecting to Spotify...',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 80,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Oops! Something went wrong',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 32),
                        ElevatedButton(
                          onPressed: _initializePlayer,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1DB954),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 16,
                            ),
                          ),
                          child: const Text('Try Again'),
                        ),
                      ],
                    ),
                  ),
                )
              : _buildPlayerUI(),
    );
  }

  Widget _buildPlayerUI() {
    final isPaused = _playerState?.isPaused ?? false;
    final playbackPosition = _playerState?.playbackPosition ?? 0;
    final trackDuration = _playerState?.track?.duration ?? 0;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Spinning vinyl record with touch control
            GestureDetector(
              onPanStart: _onVinylDragStart,
              onPanUpdate: _onVinylDragUpdate,
              onPanEnd: _onVinylDragEnd,
              child: RotationTransition(
                turns: _rotationController,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _isDragging
                            ? const Color(0xFF1DB954).withAlpha(128)
                            : Colors.black.withAlpha(128),
                        blurRadius: _isDragging ? 40 : 30,
                        offset: const Offset(0, 15),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/dezi.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 60),
            // Progress bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: trackDuration > 0
                          ? playbackPosition / trackDuration
                          : 0,
                      backgroundColor: const Color(0xFF282828),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF1DB954),
                      ),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Time labels
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(playbackPosition),
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        _formatDuration(trackDuration - playbackPosition),
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            // Play/Pause button
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1DB954),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1DB954).withAlpha(102),
                    blurRadius: 20,
                    spreadRadius: 3,
                  ),
                ],
              ),
              child: IconButton(
                icon: Icon(
                  isPaused ? Icons.play_arrow : Icons.pause,
                  size: 56,
                ),
                color: Colors.white,
                padding: const EdgeInsets.all(24),
                onPressed: _togglePlayPause,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes}:${seconds.toString().padLeft(2, '0')}';
  }
}
