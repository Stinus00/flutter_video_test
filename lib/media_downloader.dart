import 'dart:io';
import 'package:flutter_video_test/media_link.dart';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class MediaDownloader {
  MediaDownloader({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<List<MediaLink>> downloadAllMedia({
    required List<MediaLink> links,
  }) async {
    final downloadedLinks = <MediaLink>[];

    for (final media in links) {
      final path = media.type == 'image'
          ? await _downloadImage(link: media.link)
          : await _downloadVideo(link: media.link);

      downloadedLinks.add(
        MediaLink(
          link: path,
          type: media.type,
          duration: media.duration,
        ),
      );
    }

    return downloadedLinks;
  }

  // Start download on image
  Future<String> _downloadImage({required String link}) async {
    final directory = await getApplicationDocumentsDirectory();
    final name = _fileName(link);
    final imageDirectory = Directory('${directory.path}/images');
    final file = File('${imageDirectory.path}/$name.jpg');

    if (!await file.exists()) {
      final response = await http.get(Uri.parse(link));
      if (response.statusCode != 200) {
        throw HttpException('Failed to download image: ${response.statusCode}');
      }
      await imageDirectory.create(recursive: true);
      await file.writeAsBytes(response.bodyBytes);
    }

    return file.path;
  }

  // Start download on video
  Future<String> _downloadVideo({
    required String link,
    void Function(int received, int total)? onReceiveProgress,
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    final name = _fileName(link);
    final videoDirectory = Directory('${directory.path}/videos');
    final file = File('${videoDirectory.path}/$name.mp4');

    if (!await file.exists()) {
      await videoDirectory.create(recursive: true);
      await _dio.download(
        link,
        file.path,
        onReceiveProgress: onReceiveProgress,
      );
    }

    return file.path;
  }

  // Get the file name
  String _fileName(String link) {
    final path = Uri.parse(link).pathSegments.last;
    final decodedName = Uri.decodeComponent(path);
    final extensionIndex = decodedName.lastIndexOf('.');
    return extensionIndex == -1
        ? decodedName
        : decodedName.substring(0, extensionIndex);
  }
}
