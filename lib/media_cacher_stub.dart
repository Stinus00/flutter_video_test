import 'package:dio/dio.dart';
import 'package:flutter_video_test/media_link.dart';

class MediaCacher {
  MediaCacher({Dio? dio});

  Future<List<MediaLink>> cacheAllMedia({
    required List<MediaLink> links,
  }) async => links;

  Future<String> loadVideoBlobUrlFromIndexedDB(String id) async {
    throw UnsupportedError('IndexedDB video caching is available on web only.');
  }

  Future<String> loadImageBlobUrlFromIndexedDB(String id) async {
    throw UnsupportedError('IndexedDB image caching is available on web only.');
  }

  void revokeBlobUrl(String blobUrl) {}
}
