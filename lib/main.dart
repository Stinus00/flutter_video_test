import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:web_browser_detect/web_browser_detect.dart';

import 'media_cacher_stub.dart'
  if (dart.library.js_interop) 'media_cacher.dart';
import 'media_downloader.dart';
import 'media_link.dart';
import 'media_sources.dart';

void main() => runApp(const VideoApp());

class VideoApp extends StatefulWidget {
  const VideoApp({super.key});

  @override
  State<VideoApp> createState() => _VideoAppState();
}

class _VideoAppState extends State<VideoApp> {
  final MediaDownloader _mediaDownloader = MediaDownloader();
  final MediaCacher _mediaCacher = MediaCacher();
  List<MediaLink> _mediaLinks = [];

  String? _imagePath;
  ImageProvider? _activeImageProvider;
  String? _videoPath;
  String? _activeBlobUrl;
  VideoPlayerController? _controller;
  String? _nextImagePath;
  ImageProvider? _nextImageProvider;
  VideoPlayerController? _nextController;
  String? _nextBlobUrl;
  int? _nextPreparedIndex;
  int? _nextPreparationIndex;
  Future<void>? _nextPreparation;
  Timer? _imageTimer;
  String? _imageError;
  String? _videoError;
  bool _isChangingVideo = false;
  bool _hasStartedPlayback = false;
  bool _isPreparingMedia = true;
  String? _preloadError;
  int _currentLinkIndex = 0;

  Browser? _browser;

  MediaLink? get _currentMedia =>
      _mediaLinks.isEmpty ? null : _mediaLinks[_currentLinkIndex];

  @override
  void initState() {
    super.initState();
    unawaited(WakelockPlus.enable());
    unawaited(_prepareMedia());
  }

  // Check which webbrowser the user is using
  void _checkForWebBrowser() {
    if (kIsWeb) {
      _browser = Browser.detectOrNull();
    }
  }

  // Download the media given and initialize the first media.
  Future<void> _prepareMedia() async {
    try {
      // If on web give back just the links,
      //  otherwise download media.
      _mediaLinks = kIsWeb == true
          ? await _mediaCacher.cacheAllMedia(links: mediaLinks)
          : await _mediaDownloader.downloadAllMedia(links: mediaLinks);
      _isPreparingMedia = false;
      if (mounted) setState(() {});
      await _initializeMedia();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isPreparingMedia = false;
        _preloadError = error.toString();
      });
    }
  }

  // Check if first media is image or video
  //  then set first media appropriately
  //  (set timer for image and set controller for video)
  Future<void> _initializeMedia() async {
    final media = _currentMedia;
    if (media == null) return;
    if (media.type == 'image') {
      if (kIsWeb) {
        try {
          final blobUrl = await _mediaCacher.loadImageBlobUrlFromIndexedDB(
            media.id!,
          );
          if (!mounted) {
            _mediaCacher.revokeBlobUrl(blobUrl);
            return;
          }
          _imagePath = blobUrl;
          _activeImageProvider = NetworkImage(blobUrl);
          _activeBlobUrl = _imagePath;
        } catch (error) {
          if (!mounted) return;
          setState(() {
            _imageError = error.toString();
          });
          return;
        }
      } else {
        _imagePath = media.link;
        _activeImageProvider = FileImage(File(media.link));
      }

      if (!mounted) return;
      setState(() {});
      if (!kIsWeb || _hasStartedPlayback) {
        _startImageTimer(media);
      }
      unawaited(_prepareNextMedia());
      return;
    }

    _checkForWebBrowser();

    // Use file path if not on web and
    //  use url if on web.
    VideoPlayerController controller;
    if (!kIsWeb) {
      _videoPath = media.link;
      controller = VideoPlayerController.file(File(_videoPath!));
    } else {
      try {
        final blobUrl = await _mediaCacher.loadVideoBlobUrlFromIndexedDB(
          media.id!,
        );
        if (!mounted) {
          _mediaCacher.revokeBlobUrl(blobUrl);
          return;
        }
        _activeBlobUrl = blobUrl;
        _videoPath = blobUrl;
        controller = VideoPlayerController.networkUrl(Uri.parse(blobUrl));
      } catch (error) {
        revokeBlobUrl();
        if (!mounted) return;
        setState(() {
          _videoError = "$error\nid: ${media.id}\ntype: ${media.type}";
        });
        return;
      }
    }

    _controller = controller;
    controller.addListener(_handleVideoState);

    // Add controller settings.
    try {
      await controller.setLooping(false);
      controller.value = controller.value.copyWith(volume: 0.0);
      await controller.initialize();
      if (!mounted) return;
      if (!kIsWeb || _hasStartedPlayback) {
        await controller.play();
      }
      setState(() {});
      unawaited(_prepareNextMedia());
    } catch (error) {
      await controller.dispose();
      revokeBlobUrl();
      if (!mounted) return;
      setState(() {
        _videoError =
            "$error\nid: ${media.link}\ntype: ${media.type}\ncontroller: ${controller.value}";
      });
    }
  }

  void _handleVideoState() {
    final value = _controller?.value;
    if (value == null) return;
    if (value.isInitialized &&
        !value.isPlaying &&
        value.position >= value.duration &&
        !_isChangingVideo) {
      unawaited(_playNextMedia());
    }
  }

  void _startImageTimer(MediaLink media) {
    _imageTimer?.cancel();
    _imageTimer = Timer(
      Duration(milliseconds: (media.duration ?? 5000).round()),
      _playNextMedia,
    );
  }

  // Play next media.
  // // Stop image timer if there is one
  // // Remove controller if there is one
  // // Find next link
  Future<void> _playNextMedia() async {
    if (_mediaLinks.isEmpty || _isChangingVideo) return;

    _isChangingVideo = true;
    _imageTimer?.cancel();
    _imageTimer = null;
    final nextIndex = (_currentLinkIndex + 1) % _mediaLinks.length;
    if (_mediaLinks.length > 1) {
      await _prepareNextMedia();
    }
    if (!mounted) return;

    final oldController = _controller;
    oldController?.removeListener(_handleVideoState);
    final oldImageProvider = _activeImageProvider;
    final oldBlobUrl = _activeBlobUrl;
    final hasPreparedNext = _nextPreparedIndex == nextIndex;

    _currentLinkIndex = nextIndex;
    if (hasPreparedNext) {
      _controller = _nextController;
      _nextController = null;
      _imagePath = _nextImagePath;
      _activeImageProvider = _nextImageProvider;
      _nextImagePath = null;
      _nextImageProvider = null;
      _videoPath = _mediaLinks[nextIndex].type == 'video'
          ? (_nextBlobUrl ?? _mediaLinks[nextIndex].link)
          : null;
      _activeBlobUrl = _nextBlobUrl;
      _nextBlobUrl = null;
      _nextPreparedIndex = null;
    } else {
      _controller = null;
      _imagePath = null;
      _activeImageProvider = null;
      _videoPath = null;
      _activeBlobUrl = null;
    }

    await oldController?.dispose();
    if (oldImageProvider != null) await oldImageProvider.evict();
    if (oldBlobUrl != null) _mediaCacher.revokeBlobUrl(oldBlobUrl);

    _videoError = null;
    _imageError = null;
    _isChangingVideo = false;
    if (!mounted) return;
    setState(() {});

    if (hasPreparedNext) {
      final media = _currentMedia!;
      if (media.type == 'image') {
        if (!kIsWeb || _hasStartedPlayback) {
          _startImageTimer(media);
        }
      } else {
        final controller = _controller!;
        controller.addListener(_handleVideoState);
        if (!kIsWeb || _hasStartedPlayback) {
          await controller.play();
        }
      }
      unawaited(_prepareNextMedia());
      return;
    }

    await _initializeMedia();
  }

  Future<void> _prepareNextMedia() async {
    if (_mediaLinks.length < 2) return;

    final nextIndex = (_currentLinkIndex + 1) % _mediaLinks.length;
    final currentMedia = _currentMedia;
    final nextMedia = _mediaLinks[nextIndex];
    if (currentMedia?.type == 'video' && nextMedia.type == 'video') return;

    if (_nextPreparedIndex == nextIndex) return;
    if (_nextPreparationIndex == nextIndex && _nextPreparation != null) {
      await _nextPreparation;
      return;
    }

    _nextPreparationIndex = nextIndex;
    final preparation = _loadNextMedia(nextIndex);
    _nextPreparation = preparation;
    try {
      await preparation;
    } finally {
      if (identical(_nextPreparation, preparation)) {
        _nextPreparation = null;
        _nextPreparationIndex = null;
      }
    }
  }

  Future<void> _loadNextMedia(int index) async {
    final media = _mediaLinks[index];
    String? blobUrl;
    ImageProvider? imageProvider;
    VideoPlayerController? controller;

    try {
      if (media.type == 'image') {
        if (kIsWeb) {
          blobUrl = await _mediaCacher.loadImageBlobUrlFromIndexedDB(media.id!);
          imageProvider = NetworkImage(blobUrl);
        } else {
          imageProvider = FileImage(File(media.link));
        }
        await precacheImage(imageProvider, context);
        if (!mounted) {
          await imageProvider.evict();
          if (blobUrl != null) _mediaCacher.revokeBlobUrl(blobUrl);
          return;
        }
        _nextImagePath = blobUrl ?? media.link;
        _nextImageProvider = imageProvider;
      } else {
        if (kIsWeb) {
          blobUrl = await _mediaCacher.loadVideoBlobUrlFromIndexedDB(media.id!);
          controller = VideoPlayerController.networkUrl(Uri.parse(blobUrl));
        } else {
          controller = VideoPlayerController.file(File(media.link));
        }
        await controller.setLooping(false);
        controller.value = controller.value.copyWith(volume: 0.0);
        await controller.initialize();
        if (!mounted) {
          await controller.dispose();
          if (blobUrl != null) _mediaCacher.revokeBlobUrl(blobUrl);
          return;
        }
        _nextController = controller;
      }

      _nextBlobUrl = blobUrl;
      _nextPreparedIndex = index;
    } catch (error) {
      await controller?.dispose();
      if (imageProvider != null) await imageProvider.evict();
      if (blobUrl != null) _mediaCacher.revokeBlobUrl(blobUrl);
      debugPrint('Could not prepare next media: $error');
    }
  }

  void revokeBlobUrl() {
    final blobUrl = _activeBlobUrl;
    if (blobUrl == null) return;

    _mediaCacher.revokeBlobUrl(blobUrl);
    _activeBlobUrl = null;
  }

  // Widget to display the app
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Demo',
      home: Scaffold(
        body: Stack(
          alignment: Alignment.center,
          children: [
            Center(child: _buildMedia()),
            _buildStartButton(),
            // if (kIsWeb)
            //   Column(
            //     mainAxisAlignment: MainAxisAlignment.center,
            //     mainAxisSize: MainAxisSize.min,
            //     children: [
            //       Text('Browser is ${_browser?.browser ?? 'Not on web'}'),
            //       Text('Version is ${_browser?.version ?? 'Not on web'}'),
            //     ],
            //   ),
          ],
        ),
      ),
    );
  }

  // Widget to show the media
  // // Image loading using Image.network on web
  // //  and Image.file on app
  // // Video loading using Videoplayer and controller
  // // Loading screen while media gets downloaded
  Widget _buildMedia() {
    if (_isPreparingMedia) {
      return const CircularProgressIndicator();
    }
    if (_preloadError != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Could not download media:\n$_preloadError',
          textAlign: TextAlign.center,
        ),
      );
    }

    if (_videoError != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Could not load video:\n$_videoError\n$_videoPath',
          textAlign: TextAlign.center,
        ),
      );
    }
    if (_imageError != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Could not load image:\n$_imageError',
          textAlign: TextAlign.center,
        ),
      );
    }

    final media = _currentMedia!;
    if (media.type == 'image') {
      return _activeImageProvider == null
          ? const CircularProgressIndicator()
          : Image(
              image: _activeImageProvider!,
              fit: BoxFit.contain,
              height: double.infinity,
              width: double.infinity,
            );
    }

    return _controller?.value.isInitialized ?? false
        ? AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: VideoPlayer(_controller!),
          )
        : const CircularProgressIndicator();
  }

  // Start button widget for web
  //  to comply with autoplay restrictions.
  Widget _buildStartButton() {
    final media = _currentMedia;
    final isImage = media?.type == 'image';

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: animation,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child:
          _videoError == null &&
              kIsWeb &&
              !_hasStartedPlayback &&
              (isImage ||
                  (_controller?.value.isInitialized == true &&
                      !_controller!.value.isPlaying))
          ? FloatingActionButton.extended(
              key: const ValueKey('sample-button'),
              backgroundColor: const Color.fromARGB(99, 0, 0, 0),
              hoverColor: const Color.fromARGB(175, 0, 0, 0),
              foregroundColor: Colors.white,
              elevation: 0,
              onPressed: () {
                setState(() {
                  _hasStartedPlayback = true;
                  if (isImage) {
                    _startImageTimer(media!);
                  } else {
                    _controller!.play();
                  }
                });
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start'),
            )
          : const SizedBox.shrink(key: ValueKey('hidden-button')),
    );
  }

  @override
  void dispose() {
    _imageTimer?.cancel();
    final controller = _controller;
    final nextController = _nextController;
    final activeImageProvider = _activeImageProvider;
    final nextImageProvider = _nextImageProvider;
    final nextBlobUrl = _nextBlobUrl;
    unawaited(() async {
      await controller?.dispose();
      await nextController?.dispose();
      await activeImageProvider?.evict();
      await nextImageProvider?.evict();
      revokeBlobUrl();
      if (nextBlobUrl != null) _mediaCacher.revokeBlobUrl(nextBlobUrl);
    }());
    unawaited(WakelockPlus.disable());
    super.dispose();
  }
}
