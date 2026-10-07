import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_video_test/media_link.dart';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class MediaDownloader {
  MediaDownloader({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<Directory> get downloadDirectory async {
    final directory = await getApplicationDocumentsDirectory();
    return directory;
  }

  // Download all media gathered from media_sources
  Future<List<MediaLink>> downloadAllMedia({
    required List<MediaLink> links,
  }) async {
    final downloadedLinks = <MediaLink>[];

    for (final media in links) {
      final path = media.type == 'image'
          ? await _downloadImage(link: media.link)
          : await _downloadVideo(link: media.link);

      if(path == '') {
        continue;
      }

      downloadedLinks.add(
        MediaLink(
          id: media.id,
          link: media.link,
          type: media.type,
          duration: media.duration,
          mimeType: media.mimeType,
          localPath: path,
        ),
      );
    }

    return downloadedLinks;
  }

  // Start download on image
  Future<String> _downloadImage({
    required String link,
    void Function(int received, int total)? onReceiveProgress,
  }) async {
    final directory = await downloadDirectory;
    final name = _fileName(link);
    final imageDirectory = Directory('${directory.path}/images');
    final file = File('${imageDirectory.path}/$name.jpg');

    try {
      if (!await file.exists()) {
        await imageDirectory.create(recursive: true);
        await _dio.download(
          link,
          file.path,
          onReceiveProgress: onReceiveProgress,
        );
      }
    } catch (e) {
      return '';
    }

    return file.path;
  }

  // Start download on video
  Future<String> _downloadVideo({
    required String link,
    void Function(int received, int total)? onReceiveProgress,
  }) async {

    final directory = await downloadDirectory;
    final name = _fileName(link);
    final videoDirectory = Directory('${directory.path}/videos');
    final file = File('${videoDirectory.path}/$name.mp4');

    if (!_checkHttp(link) && _checkAsset(link)){
      final byteData = await rootBundle.load(link);
      await file.writeAsBytes(
        byteData.buffer.asUint8List(),
        flush: true,
      );
      return file.path;
    }

    try {
      if (!await file.exists()) {
        await videoDirectory.create(recursive: true);
        await _dio.download(
          link,
          file.path,
          onReceiveProgress: onReceiveProgress,
        );
      }
    } catch (e) {
      return '';
    }

    return file.path;
  }

  // Get the file name
  String _fileName(String link) {
    final path = Uri.parse(link).pathSegments.last;

    final extensionIndex = path.lastIndexOf('.');
    final name = extensionIndex == -1
        ? path
        : path.substring(0, extensionIndex);

    try {
      return Uri.decodeComponent(name);
    } catch (_) {
      return name;
    }
  }

  // Check if video is a link
  bool _checkHttp(String link) {
    return link.contains('http');
  }

  // Check if video is an asset
  bool _checkAsset(String link) {
    return link.contains('assets/');
  }
}
