import 'package:flutter/services.dart';
import 'package:flutter_video_test/media_link.dart';

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
      version: 1,
      onUpgradeNeeded: (VersionChangeEvent e) {
        final db = e.database;
        if (!db.objectStoreNames.contains('videos')) {
          db.createObjectStore(
            'videos',
            autoIncrement: true,
          );
        }
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
  Future<String> _createBlobUrl(Uint8List bytes) async {
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'video/mp4'),
    );

    return web.URL.createObjectURL(blob);
  }

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
      if(bytes != null) {
        final blob = _createBlobUrl(bytes);
        return blob;
      }
    }

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

    final key = await store.add({'id': videoId, 'bytes': bytes});
    final video = await store.getObject(key);

    await txn.completed;

    return _createBlobUrl(bytes);
  }

  // Get video from IndexedDB
  Future<Uint8List?> getVideoWeb(String id) async {
    final db = await database;

    final transaction = db.transaction(
      'videos',
      idbModeReadOnly,
    );

    final value = await transaction.objectStore('videos').getObject(id);

    await transaction.completed;

    if (value == null) {
      return null;
    }

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
        final blob = _createBlobUrl(bytes);
        return blob;
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

    final key = await store.put({'id': imageId, 'bytes': bytes});
    final image = await store.getObject(key);

    await txn.completed;

    log(await _createBlobUrl(bytes));

    return await _createBlobUrl(bytes);
  }

  // Get image from IndexedDB
  Future<Uint8List?> getImageWeb(String id) async {
    final db = await database;

    final transaction = db.transaction(
      'images',
      idbModeReadOnly,
    );

    final value = await transaction.objectStore('images').getObject(id);

    await transaction.completed;

    if (value == null) {
      return null;
    }

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