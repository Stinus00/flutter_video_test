import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_video_test/api_mcc_data.dart';
import 'package:flutter_video_test/media_downloader.dart';
import 'package:flutter_video_test/media_link.dart';
import 'package:intl/intl.dart';
import 'package:teno_rrule/teno_rrule.dart';

class ApiCall {
  ApiCall({Dio? dio, MediaDownloader? downloader})
    : _dio = dio ?? Dio(),
      _downloader = downloader ?? MediaDownloader();

  final Dio _dio;
  final MediaDownloader _downloader;
  
  var _playlistsMap = {};

  // Get data from URL
  Future<String> getMediaFromApi() async {
    try {
      final data = await _getJsonFromUrl();

      if(await _compareApiResponses(data))
      {
        _loadOldApiResponse();
        return '';
      }
      await _saveApiResponse(data);

      List<dynamic> media = [];

      final groupSchedules = _getGroupSchedules(media, data);
      final systemSchedules = _getSystemSchedules(media, data);
      return jsonEncode(data);
    } catch (e) {
      debugPrint('Error fetching media from API: $e');
      rethrow;
    }
  }

  // Get JSON from api
  Future<Map<String, dynamic>> _getJsonFromUrl() async {
    try {
      final secrets = await _getSecrets();
      _dio.options.headers[secrets['api_header']] = secrets['api_key'];
      final url = secrets['api_url'];
      final urlNow = '$url?start=${_getCurrentDate()}';

      final response = await _dio.get(urlNow);
      // await _saveApiResponse(response);
      if (response.statusCode == 200) {
        return response.data;
      } else {
        throw Exception('Failed to load JSON from $url');
      }
    } catch (e) {
      debugPrint('Error fetching JSON: $e');
      rethrow;
    }
  }

  // Get the group schedules and return list.
  List<dynamic> _getGroupSchedules(
    List<dynamic> media,
    Map<String, dynamic> data,
  ) {
    media.addAll(_getActiveGroupSchedules(data, now: DateTime.now().toUtc()));
    return media;
  }

  @visibleForTesting
  List<dynamic> getActiveGroupSchedules(Map<String, dynamic> data, DateTime? now) {
    return _getActiveGroupSchedules(data, now: now);
  }

  List<dynamic> _getActiveGroupSchedules(
    Map<String, dynamic> data, {
    DateTime? now,
  }) {
    final groupSchedules = data['group_schedules'] as Map<String, dynamic>;
    final slides = groupSchedules['slides'] as List<dynamic>;

    return slides.where((slide) {
      return _createRRule(slide as Map<String, dynamic>, now: now);
    }).toList();
  }

  // Get the system schedules and return list
  List<dynamic> _getSystemSchedules(
    List<dynamic> media,
    Map<String, dynamic> data,
  ) {
    media.addAll(_getActiveSystemSchedules(data, now: DateTime.now().toUtc()));
    return media;
  }

  @visibleForTesting
  List<dynamic> getActiveSystemSchedules(Map<String, dynamic> data, DateTime? now) {
    return _getActiveSystemSchedules(data, now: now);
  }

  List<dynamic> _getActiveSystemSchedules(
    Map<String, dynamic> data, {
    DateTime? now,
  }) {
    final systemSchedules = data['system_schedules'] as Map<String, dynamic>;
    final slides = systemSchedules['slides'] as List<dynamic>;

    return slides.where((slide) {
      return _createRRule(slide as Map<String, dynamic>, now: now);
    }).toList();
  }

  // Get media that will be shown right now.
  bool _createRRule(Map<String, dynamic> slide, {DateTime? now}) {
    final start = DateTime.parse(slide['start'] as String).toUtc();
    final end = DateTime.parse(slide['end'] as String).toUtc();
    if (!end.isAfter(start)) {
      throw FormatException('Schedule end must be after start.');
    }

    final currentTime = (now ?? DateTime.now()).toUtc();
    final recurrenceRule = (slide['recurrence_rule'] as String?)?.trim();
    if (recurrenceRule == null || recurrenceRule.isEmpty) {
      return !currentTime.isBefore(start) && currentTime.isBefore(end);
    }

    final exceptionDates =
        (slide['recurrence_exception'] as String? ?? '').trim();
    final exDateLine = exceptionDates.isEmpty
        ? ''
        : 'EXDATE:$exceptionDates\n';
    final rule = RecurrenceRule.from(
      'DTSTART:${_formatDateForRRule(start)}Z\n'
      '${exDateLine}RRULE:$recurrenceRule',
    );
    if (rule == null) {
      throw FormatException('Invalid recurrence rule for slide ${slide['id']}.');
    }

    final startOfToday = DateTime.utc(
      currentTime.year,
      currentTime.month,
      currentTime.day,
    );
    final tomorrow = startOfToday.add(const Duration(days: 1));
    final duration = end.difference(start);

    return rule
        .between(startOfToday.subtract(duration), tomorrow)
        .any((occurrenceStart) {
      final occurrenceEnd = occurrenceStart.add(duration);
      return !currentTime.isBefore(occurrenceStart) &&
          currentTime.isBefore(occurrenceEnd);
    });
  }

  Future<void> _mapPlaylists(playlists) async {
    for (var playlist in playlists) {
      if (_playlistsMap[playlist['id']] != null) continue;

      _playlistsMap[playlist['id']] = playlist;
    }
  }

  Future<void> _getPlaylistData(schedules, data) async {
    for (var schedule in schedules) {
      String playlistId = schedule["playlist"]["id"];
      bool slideShuffle = schedule["slide_shuffle"] == 1;

      data['playlists']['slides'];
    }
  }

  // Convert media gotten from API to MediaLink
  List<MediaLink> _convertMediaToMediaLink(List<dynamic> media) {
    List<MediaLink> mediaLinks = [];
    for (var item in media) {
      final type = item['media_type'];
      final duration = item['ad_duration'];
      final url = type == 'image' ? item['image']['url'] : item['video']['url'];
      final id = type == 'image' ? item['image']['id'] : item['video']['id'];
      final mimeType = type == 'image' ? item['image']['mime_type'] : item['video']['mime_type'];
      mediaLinks.add(MediaLink(link: url, type: type, duration: duration, id: id, mimeType: mimeType));

    }
    return mediaLinks;
  }

  // Download all media gotten from API
  void _downloadMedia(List<MediaLink> media) {
    _downloader.downloadAllMedia(links: media);
  }

  @visibleForTesting
  Future<void> saveApiResponse(Map<String, dynamic> data) {
    return _saveApiResponse(data);
  }

  Future<SystemData> _convertToSystemData(Map<String, dynamic> data) async {
    final system = SystemData.fromJson(data);
    return system;
  }

  // Save API response to file for comparison later
  Future<void> _saveApiResponse(Map<String, dynamic> data) async {
    final directory = await _downloader.downloadDirectory;
    final system = SystemData.fromJson(data);
    final jsonDirectory = Directory('${directory.path}/json');
    final file = File('${jsonDirectory.path}/old_api_response.json');
    await file.create(recursive: true);
    final jsonString = const JsonEncoder.withIndent('  ').convert(system.toJson());
    await file.writeAsString(jsonString);
  }

  // Load old API response from file for comparison
  Future<Map<String, dynamic>> _loadOldApiResponse() async {
    final directory = await _downloader.downloadDirectory;
    final jsonDirectory = Directory('${directory.path}/json');
    final file = File('${jsonDirectory.path}/old_api_response.json');
    if (!file.existsSync()) {
      throw Exception('Old API response file not found.');
    }
    final jsonString = file.readAsStringSync();
    return jsonDecode(jsonString) as Map<String, dynamic>;
  }

  // Compare old and new response
  Future<bool> _compareApiResponses(Map<String, dynamic> data) async {
    final system = SystemData.fromJson(data);
    final jsonString = const JsonEncoder.withIndent('  ').convert(system.toJson());
    final newData = jsonDecode(jsonString) as Map<String, dynamic>;
    final oldData = await _loadOldApiResponse();

    final newDataString = jsonEncode(newData);
    final oldDataString = jsonEncode(oldData);

    final returnBool = newDataString == oldDataString;
    return returnBool;
  }

  // Get current date
  String _getCurrentDate() {
    var now = DateTime.now();
    var formatter = DateFormat('yyyy-MM-dd');
    String formattedDate = formatter.format(now);
    return formattedDate;
  }

  // Get secrets in secrets.json
  Future<dynamic> _getSecrets() async {
    final String jsonString = await rootBundle.loadString(
      'assets/json/secrets.json',
    );

    return jsonDecode(jsonString);
  }

  // Format date for Recurrence Rule
  String _formatDateForRRule(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');

    return '${date.year}'
        '${two(date.month)}'
        '${two(date.day)}T'
        '${two(date.hour)}'
        '${two(date.minute)}'
        '${two(date.second)}';
  }
}
