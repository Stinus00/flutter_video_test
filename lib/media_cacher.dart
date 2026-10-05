import 'dart:js_interop';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_video_test/media_link.dart';
import 'package:web/web.dart' as web;

class MediaCacher {
  static final _cacheManager = CacheManager(Config('media_cache'));

  final Map<String, Future<String>> _webMediaCache = {};

  Future<List<MediaLink>> cacheAllMedia({
    required List<MediaLink> links,
  }) async {
    final downloadedLinks = <MediaLink>[];

    for (final media in links) {
      downloadedLinks.add(
        MediaLink(
          link: await _cacheWebMedia(media.link, media.type),
          type: media.type,
          duration: media.duration,
        ),
      );
    }

    return downloadedLinks;
  }

  Future<String> _cacheWebMedia(String url, String type) async {
    final cached = _webMediaCache[url];
    if (cached != null) return cached;

    final pending = _downloadWebMedia(url, type);
    _webMediaCache[url] = pending;

    try {
      return await pending;
    } catch (_) {
      _webMediaCache.remove(url);
      rethrow;
    }
  }

  Future<String> _downloadWebMedia(String url, String type) async {
    final file = await _cacheManager.getSingleFile(url);
    final bytes = await file.readAsBytes();
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: _contentType(url, type)),
    );

    return web.URL.createObjectURL(blob);
  }

  String _contentType(String url, String mediaType) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    if (path.endsWith('.png')) return 'image/png';
    if (path.endsWith('.gif')) return 'image/gif';
    if (path.endsWith('.webp')) return 'image/webp';
    if (path.endsWith('.svg')) return 'image/svg+xml';
    if (path.endsWith('.webm')) return 'video/webm';
    if (path.endsWith('.mov')) return 'video/quicktime';

    return mediaType == 'image' ? 'image/jpeg' : 'video/mp4';
  }
}
