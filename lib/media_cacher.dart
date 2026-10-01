import 'package:flutter/services.dart';
import 'package:flutter_video_test/media_link.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'dart:developer';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'package:dio/dio.dart';
import 'package:idb_shim/idb_browser.dart';

class MediaCacher {
  MediaCacher({Dio? dio}) : _dio = dio ?? Dio();
  final Dio _dio;
  final _factory = getIdbFactory();
  Database? _db;

  // Returns IndexedDB for storage in web.
  Future<Database> get database async {
    if (_db != null) return _db!;

    _db = await _factory!.open(
      'media_cache',
      version: 2,
      onUpgradeNeeded: (VersionChangeEvent e) {
        final db = e.database;
        if (db.objectStoreNames.contains('videos')) {
          db.deleteObjectStore('videos');
        }
        db.createObjectStore('videos');
        if (!db.objectStoreNames.contains('images')) {
          db.createObjectStore(
            'images',
            autoIncrement: true,
          );
        }
      },
    );

    return _db!;
  }

  // Go through the list to download/cache all media.
  Future<List<MediaLink>> cacheAllMedia({
    required List<MediaLink> links,
  }) async {
    final downloadedLinks = <MediaLink>[];
    DefaultCacheManager().emptyCache();

    for (final media in links) {
      final path = media.type == 'image'
          ? await _cacheWebImage(_getTemporaryId(media.link), media.link, null)
          : await _cacheWebVideo(_getTemporaryId(media.link), media.link, null);

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

  // Give the name of the file back as id.
  String _getTemporaryId(String link) {
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

  // Turn the bytes into a blob.
  Future<String> _createBlobUrl(
    Uint8List bytes, {
    String contentType = 'video/mp4',
  }) async {
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: contentType),
    );

    return web.URL.createObjectURL(blob);
  }

  // Future<void> _revokeBlobUrl(String blobUrl) async {
  //   web.URL.revokeObjectURL(blobUrl);
  // }

  // Put video into IndexedDB
  // // Change to download to cache. 
  // // Out of memory issue encountered on Firestick.
  Future<String> _cacheWebVideo(
    String videoId,
    String url,
    void Function(double progress)? onProgress,
  ) async {
    // Check if video exists
    // If exists skip download part
    if(await containsVideoWeb(videoId)) {
      final bytes = await getVideoWeb(videoId);
      if (bytes != null && bytes.isNotEmpty) {
        return videoId;
      }
    }

    try{
      // Get video in bytes
      final response = await Dio().get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes), // Set the response type to `bytes`.
      );

      if (response.statusCode != 200 || response.data == null) {
        throw Exception('[media_downloader.dart] Failed to download video');
      }

      final bytes = Uint8List.fromList(response.data!);

      final db = await database;

      final txn = db.transaction('videos', idbModeReadWrite);
      final store = txn.objectStore('videos');

      await store.put({'bytes': bytes}, videoId);

      await txn.completed;
    } catch(e) {
      log('Error caching video: $e');
      rethrow;
    }

    return videoId; // Return the video ID for retrieval later
  }

  Future<String> loadBlobUrlFromIndexedDB(String id) async {
    final bytes = await getVideoWeb(id);
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Video bytes are missing or empty in IndexedDB for "$id".');
    }

    return _createBlobUrl(bytes);
  }

  Future<String> loadImageBlobUrlFromIndexedDB(String id) async {
    final bytes = await getImageWeb(id);
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Image bytes are missing or empty in IndexedDB for "$id".');
    }

    return _createBlobUrl(bytes, contentType: '');
  }

  // Get video from IndexedDB
  Future<Uint8List?> getVideoWeb(String id) async {
    final db = await database;

    final transaction = db.transaction(
      'videos',
      idbModeReadOnly,
    );

    final record = await transaction.objectStore('videos').getObject(id);

    await transaction.completed;

    if (record is! Map) {
      return null;
    }

    final value = record['bytes'];
    if (value is Uint8List) {
      return value;
    }

    if (value is List<int>) {
      return Uint8List.fromList(value);
    }

    return null;
  }

  // Check if video exists in IndexedDB
  Future<bool> containsVideoWeb(String id) async {
    final db = await database;

    final transaction = db.transaction(
      'videos',
      idbModeReadOnly,
    );

    final value = await transaction.objectStore('videos').getObject(id);

    await transaction.completed;

    return value != null;
  }

  // Delete video from IndexedDB
  Future<void> deleteVideoWeb(String id) async {
    final db = await database;

    final transaction = db.transaction(
      'videos',
      idbModeReadWrite,
    );

    await transaction.objectStore('videos').delete(id);

    await transaction.completed;
  }

  // Put image into IndexedDB
  Future<String> _cacheWebImage(
    String imageId,
    String url,
    void Function(double progress)? onProgress,
  ) async {
    // Check if image exists in database.
    // If it does skip download part.
    if(await containsImageWeb(imageId)) {
      final bytes = await getImageWeb(imageId);
      if(bytes != null) {
        return imageId;
      }
    }

    // Get image in bytes format.
    final response = await Dio().get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes), // Set the response type to `bytes`.
    );

    if (response.statusCode != 200 || response.data == null) {
      throw Exception('[media_downloader.dart] Failed to download image');
    }

    final bytes = Uint8List.fromList(response.data!);

    final db = await database;

    final txn = db.transaction('images', idbModeReadWrite);
    final store = txn.objectStore('images');

    await store.put({'bytes': bytes}, imageId);

    await txn.completed;

    return imageId; // Return the image ID for retrieval later
  }

  // Get image from IndexedDB
  Future<Uint8List?> getImageWeb(String id) async {
    final db = await database;

    final transaction = db.transaction(
      'images',
      idbModeReadOnly,
    );

    final record = await transaction.objectStore('images').getObject(id);

    await transaction.completed;

    if (record is! Map) {
      return null;
    }

    final value = record['bytes'];
    if (value is Uint8List) {
      return value;
    }

    if (value is List<int>) {
      return Uint8List.fromList(value);
    }

    return null;
  }

  // Check if image is in IndexedDB
  Future<bool> containsImageWeb(String id) async {
    final db = await database;

    final transaction = db.transaction(
      'images',
      idbModeReadOnly,
    );

    final value = await transaction.objectStore('images').getObject(id);

    await transaction.completed;

    return value != null;
  }

  // Delete image from IndexedDB
  Future<void> deleteImageWeb(String id) async {
    final db = await database;

    final transaction = db.transaction(
      'images',
      idbModeReadWrite,
    );

    await transaction.objectStore('images').delete(id);

    await transaction.completed;
  }
}