import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_video_test/media_cacher_stub.dart'
    if (dart.library.js_interop) 'package:flutter_video_test/media_cacher.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:web_browser_detect/web_browser_detect.dart';

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
  VideoPlayerController? _controller;
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
          if (!mounted) return;
          _imagePath = blobUrl;
          _activeImageProvider = NetworkImage(blobUrl);
        } catch (error) {
          if (!mounted) return;
          setState(() {
            _imageError = error.toString();
          });
          return;
        }
      } else {
        _imagePath = media.link;
      }

      if (!mounted) return;
      setState(() {});
      if (!kIsWeb || _hasStartedPlayback) {
        _startImageTimer(media);
      }
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
        if (!mounted) return;
        _videoPath = blobUrl;
        controller = VideoPlayerController.networkUrl(Uri.parse(blobUrl));
      } catch (error) {
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
    } catch (error) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _videoError =
            "$error\nid: ${media.link}\ntype: ${media.type}\ncontroller: ${controller.value}";
      });
    }
  }

  // Handle video state changes
  //  and play next media if video is finished.
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

  // Start timer for image
  // Cancel any existing timer
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
    if (_mediaLinks.isEmpty) return;

    _isChangingVideo = true;
    _imageTimer?.cancel();
    _imageTimer = null;

    final nextIndex = (_currentLinkIndex + 1) % _mediaLinks.length;
    final nextMedia = _mediaLinks[nextIndex];
    if (nextMedia.type == 'image') {
      await _playNextImage(nextIndex, nextMedia);
      return;
    }

    await _playNextVideo(nextIndex, nextMedia);
  }

  // Play next video.
  // // Dispose of current controller
  // // Load next video from blob url if on web
  // // Load next video from file if not on web
  // // Initialize next video controller
  Future<void> _playNextVideo(int nextIndex, MediaLink media) async {
    VideoPlayerController? nextController;
    String? nextVideoPath;

    try {
      if (kIsWeb) {
        final blobUrl = await _mediaCacher.loadVideoBlobUrlFromIndexedDB(
          media.id!,
        );
        nextVideoPath = blobUrl;
        nextController = VideoPlayerController.networkUrl(Uri.parse(blobUrl));
      } else {
        nextVideoPath = media.link;
        nextController = VideoPlayerController.file(File(nextVideoPath));
      }

      final controllerToInitialize = nextController;
      await controllerToInitialize.setLooping(false);
      controllerToInitialize.value = controllerToInitialize.value.copyWith(
        volume: 0.0,
      );
      await controllerToInitialize.initialize();
      if (!kIsWeb || _hasStartedPlayback) {
        await controllerToInitialize.play();
      }
    } catch (error) {
      await nextController?.dispose();
      if (!mounted) return;
      setState(() {
        _videoError = '$error\nid: ${media.link}\ntype: ${media.type}';
        _isChangingVideo = false;
      });
      return;
    }

    final readyController = nextController;
    if (!mounted) {
      await readyController.dispose();
      return;
    }

    final controller = _controller;
    controller?.removeListener(_handleVideoState);
    readyController.addListener(_handleVideoState);
    _controller = readyController;
    _currentLinkIndex = nextIndex;
    _videoPath = nextVideoPath;
    _videoError = null;
    _imageError = null;
    _imagePath = null;
    _isChangingVideo = false;
    setState(() {});

    await controller?.dispose();
    await _evictActiveImage();
    _handleVideoState();
  }

  // Play next image.
  // // Dispose of current controller
  // // Load next image from blob url if on web
  // // Load next image from file if not on web
  // // Precache next image
  // // Set next image as active image
  Future<void> _playNextImage(int nextIndex, MediaLink media) async {
    String? imagePath;
    ImageProvider? imageProvider;
    String? imageError;

    try {
      if (kIsWeb) {
        imagePath = await _mediaCacher.loadImageBlobUrlFromIndexedDB(media.id!);
        imageProvider = NetworkImage(imagePath);
      } else {
        imagePath = media.link;
        imageProvider = FileImage(File(imagePath));
      }

      if (!mounted) return;
      Object? loadingError;
      await precacheImage(
        imageProvider,
        context,
        onError: (exception, _) {
          loadingError = exception;
        },
      );
      if (loadingError != null) {
        throw StateError('Could not decode image: $loadingError');
      }
    } catch (error) {
      imageError = error.toString();
      imagePath = null;
      imageProvider = null;
    }

    final controller = _controller;
    controller?.removeListener(_handleVideoState);
    await controller?.dispose();
    await _evictActiveImage();
    if (!mounted) return;

    _controller = null;
    _currentLinkIndex = nextIndex;
    _videoError = null;
    _imageError = imageError;
    _imagePath = imagePath;
    _activeImageProvider = imageProvider;
    _videoPath = null;
    _isChangingVideo = false;
    setState(() {});

    if (imageError == null && (!kIsWeb || _hasStartedPlayback)) {
      _startImageTimer(media);
    }
  }

  // Evict the active image from memory to free up resources.
  Future<void> _evictActiveImage() async {
    final imageProvider = _activeImageProvider;
    _activeImageProvider = null;
    _imagePath = null;
    if (imageProvider != null) {
      await imageProvider.evict();
    }
  }

  // Widget to display the app
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Demo',
      theme: ThemeData(scaffoldBackgroundColor: Colors.black),
      home: Scaffold(
        body: Stack(
          alignment: Alignment.center,
          children: [
            Center(child: _buildMedia()),
            _buildStartButton(),
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
    // Show any error if there is one
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

    // Show the media if there is no error
    final media = _currentMedia!;
    if (media.type == 'image') {
      if (kIsWeb) {
        return _imagePath == null
            ? const CircularProgressIndicator()
            : Image(
                image: _activeImageProvider!,
                fit: BoxFit.contain,
                height: double.infinity,
                width: double.infinity,
              );
      }
      return _imagePath == null
          ? const CircularProgressIndicator()
          : Image.file(
              File(_imagePath!),
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

  // Dispose of the controller and cancel the timer when the widget is disposed.
  @override
  void dispose() {
    _imageTimer?.cancel();
    final controller = _controller;
    unawaited(() async {
      await controller?.dispose();
      await _evictActiveImage();
    }());
    unawaited(WakelockPlus.disable());
    super.dispose();
  }
}
