import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'video.dart';

void main() => runApp(const VideoApp());

class MediaLink {
  const MediaLink({required this.link, required this.type, this.duration});

  final String link;
  final String type;
  final double? duration;
}

/// Stateful widget to fetch and then display video content.
class VideoApp extends StatefulWidget {
  const VideoApp({super.key});

  @override
  _VideoAppState createState() => _VideoAppState();
}

class _VideoAppState extends State<VideoApp> {
  Future<List<Video>> getVideosFromLinkk() async {
  
    final uri = Uri.https(
      'gist.githubusercontent.com/poudyalanil/ca84582cbeb4fc123a13290a586da925/raw/14a27bd0bcd0cd323b35ad79cf3b493dddf6216b/videos.json'
    );

    final response = await get(uri);

    if (response.statusCode != 200) {
      throw const HttpException('[main.dart] Failed to get videos');
    }

    return Video.fromJsonList(jsonDecode(response.body));
  }

  Future<bool> _checkFileExists({required String name, required String type}) async {
    final documentDirectory = await getApplicationDocumentsDirectory();
    final file = File('${documentDirectory.path}/${type}s/$name.${type == 'image' ? 'jpg' : 'mp4'}');
    print('[main.dart] ${type.capitalize()} does exist: ${await file.exists()}');
    return file.exists();
  }
 
  Future<void> _downloadImage({required String link}) async {
    var url = Uri.parse(link);
    RegExp exp = RegExp(r'(?<=images\/)(.*)(?=\.)');
    RegExpMatch? match = exp.firstMatch(link);
    String name = match![0]!;
    
    var exists = await _checkFileExists(name: name, type: 'image');
    var response;
    
    var documentDirectory = await getApplicationDocumentsDirectory();
    var firstPath = "${documentDirectory.path}/images";
    var filePathAndName = '${documentDirectory.path}/images/${name}.jpg'; 
    if(!exists)
    {
      response = await get(url);

      print("[main.dart] Get image from link.");
    
      await Directory(firstPath).create(recursive: true);
      File file2 = new File(filePathAndName);
      file2.writeAsBytesSync(response.bodyBytes);

      print("[main.dart] Create image in local files.");
    }
    setState(() {
      imageData = filePathAndName;
      dataLoaded = true;
    });
  }

  Future<void> _downloadVideo({required String link}) async {
    Dio dio = Dio();

    RegExp exp = RegExp(r'(?<=videos\/)(.*)(?=\.)');
    RegExpMatch? match = exp.firstMatch(link);
    String name = match![0]!;

    var dir = await getApplicationDocumentsDirectory();
    String? filePathAndName = '${dir.path}/videos/${name}.mp4'; 

    var exists = await _checkFileExists(name: name, type: 'video');

    if(!exists)
    {
      print("[main.dart] Downloading to ${dir.path}");
      await dio.download(link, "${dir.path}/videos/${name}.mp4",
          onReceiveProgress: (rec, total) {
        print("[download] Rec: $rec , Total: $total");

        setState(() {
          downloading = true;
          progressString = '${((rec / total) * 100).toStringAsFixed(0)}%';
        });
      });
    }

    setState(() {
      videoData = filePathAndName;
      downloading = false;
      progressString = "Completed";
    });
    if(!exists)
      print("[main.dart] Download completed");
  }

  String? imageData;
  bool dataLoaded = false;

  String? videoData;
  bool downloading = false;
  String progressString = "Completed";

  VideoPlayerController? _controller;
  Timer? _imageTimer;
  String? _videoError;
  bool _isChangingVideo = false;
  bool _hasStartedPlayback = false;

  int currentLinkIndex = 0;

  final List<MediaLink> uriLinks = [
    MediaLink(
      link: 'https://s3.eu-central-003.backblazeb2.com/bcm-test-stijn/images/Whats-On-Instagram-Post-2-1.jpg',
      type: 'image',
      duration: 5000.0,
    ),
    MediaLink(
      link: 'https://s3.eu-central-003.backblazeb2.com/bcm-test-stijn/images/f7274a459393cea97c688db8d6cc02210effb31fd386f5b993f3701747b4d55c.jpg',
      type: 'image',
      duration: 5000.0
    ),
    MediaLink(
      link: 'https://s3.eu-central-003.backblazeb2.com/bcm-test-stijn/images/208445601-besneeuwde-lekkernijen-kerst-winter-achtergrond-met-sneeuwpop-en-wazig-bokeh-prettige-kerstdagen.jpg',
      type: 'image',
      duration: 5000.0,
    ),
    MediaLink(
      link: 'https://s3.eu-central-003.backblazeb2.com/production--remote-webapp/videos/2eba793b-f285-44bc-9e3e-767744386aeb/gymna-launch.mp4',
      type: 'video',
    ),
    MediaLink(
      link: 'https://s3.eu-central-003.backblazeb2.com/production--remote-webapp/videos/0a6fa960-66e4-4805-87a2-b592e530e0e9/VID%20Rotate270gr.mp4',
      type: 'video',
    ),
    MediaLink(
      link: 'https://s3.eu-central-003.backblazeb2.com/bcm-test-stijn/images/05aac0e9f1269015f0cc65daf450c2a0b3f416f244691e80501582a284573874%20X1%3D1264%20Y1%3D385%20X2%3D2576%20Y2%3D1123.jpg',
      type: 'image',
      duration: 5000.0,
    ),
    MediaLink(
      link:   'https://s3.eu-central-003.backblazeb2.com/production--remote-webapp/videos/1755a007-b452-47a8-9611-1dcbf4086a31/CDP_Huisstijl-introductie-video-1920x1080.mp4',
      type: 'video',
    ),
    // MediaLink(
    //   link: 'https://s3.eu-central-003.backblazeb2.com/production--remote-webapp/videos/1755a007-b452-47a8-9611-1dcbf4086a31/CDP_Huisstijl-introductie-video-1920x1080.mp4',
    //   type: 'video',
    // ),
    // MediaLink(
    //   link: 'https://s3.eu-central-003.backblazeb2.com/production--remote-webapp/videos/82220d7d-0220-419e-98b6-4de54a484923/Sif-%EF%BD%9C-Introduction-video-2019-1.mp4',
    //   type: 'video',
    // )
  ];

  @override
  void initState() {
    super.initState();
    unawaited(WakelockPlus.enable());
    _initializeMedia();
  }

  void _downloadFailed(e) {
    print('[main.dart] [error] Download failed');
    print('[main.dart] [error] $e');

    uriLinks.removeAt(currentLinkIndex);
    print('[main.dart] Link removed from list');
    currentLinkIndex -= 1;
    _playNextVideo();
  }

  Future<void> _initializeMedia() async {
    final media = uriLinks[currentLinkIndex];
    if (media.type == 'image') {
      if (!kIsWeb) {
        try{
          await _downloadImage(link: media.link);
        } catch (e) {
          _downloadFailed(e);
          return;
        }
      }

      if (mounted) {
        setState(() {});
        _imageTimer = Timer(
          Duration(milliseconds: (media.duration ?? 5000).round()),
          _playNextVideo,
        );
      }
      return;
    }

    var controller;
    if(!kIsWeb) {
      try{
        await _downloadVideo(link: media.link);
      } catch (e) {
        _downloadFailed(e);
        return;
      }
      
      controller = VideoPlayerController.file(File(videoData!));
    }
    else {
      controller = VideoPlayerController.networkUrl(
        Uri.parse(media.link),
      );
    }
    _controller = controller;
    controller.addListener(_handleVideoState);

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
        _videoError = error.toString();
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
      _playNextVideo();
    }
  }

  Future<void> _playNextVideo() async {
    _isChangingVideo = true;
    _imageTimer?.cancel();
    _imageTimer = null;
    final controller = _controller;
    controller?.removeListener(_handleVideoState);
    await controller?.dispose();
    _controller = null;
    currentLinkIndex = (currentLinkIndex + 1) % uriLinks.length;
    _videoError = null;
    _isChangingVideo = false;
    await _initializeMedia();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Demo',
      home: Scaffold(
        body: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: _videoError != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Could not load video:\n$_videoError',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : uriLinks[currentLinkIndex].type == 'image'
                    ? kIsWeb
                      ? Image.network(
                        uriLinks[currentLinkIndex].link,
                        fit: BoxFit.contain,
                        height: double.infinity,
                        width: double.infinity,
                      )
                      : imageData == null
                      ? const CircularProgressIndicator()
                      : Image.file(
                          File(imageData!),
                          fit: BoxFit.contain,
                          height: double.infinity,
                          width: double.infinity,
                        )
                  : _controller?.value.isInitialized ?? false
                  ? AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: VideoPlayer(_controller!),
                    )
                  : const CircularProgressIndicator(),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, animation) {
                return ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                );
              },
                    child: _videoError == null &&
                      kIsWeb &&
                      !_hasStartedPlayback &&
                      _controller?.value.isInitialized == true &&
                      !_controller!.value.isPlaying
                  ? FloatingActionButton.extended(
                      key: const ValueKey('sample-button'),
                      backgroundColor: const Color.fromARGB(99, 0, 0, 0),
                      hoverColor: const Color.fromARGB(175, 0, 0, 0),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      onPressed: () {
                        setState(() {
                          _hasStartedPlayback = true;
                          _controller!.play();
                        });
                      },
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start'),
                    )
                  : const SizedBox.shrink(key: ValueKey('hidden-button')),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _imageTimer?.cancel();
    _controller?.dispose();
    unawaited(WakelockPlus.disable());
    super.dispose();
  }
}

extension StringExtension on String {
    String capitalize() {
      return "${this[0].toUpperCase()}${this.substring(1).toLowerCase()}";
    }
}