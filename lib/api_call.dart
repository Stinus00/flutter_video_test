import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_video_test/api_mcc_data.dart';
import 'package:flutter_video_test/media_downloader.dart';
import 'package:flutter_video_test/media_link.dart';
import 'package:intl/intl.dart';
import 'package:teno_rrule/teno_rrule.dart';

class ApiCall {
  ApiCall({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  MediaDownloader _downloader = MediaDownloader();

  Future<String> getMediaFromApi() async {
    try {
      final data = await _getJsonFromUrl();

      _saveApiResponse(data);

      List<dynamic> media = [];

      final groupSchedules = _getGroupSchedules(media, data);
      final systemSchedules = _getSystemSchedules(media, data);
      return jsonEncode(data);
    } catch (e) {
      debugPrint('Error fetching media from API: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _getJsonFromUrl() async {
    try {
      final secrets = await _getSecrets();
      _dio.options.headers[secrets['api_header']] = secrets['api_key'];
      final url = secrets['api_url'];
      final urlNow = '$url?start=${_getCurrentDate()}';

      final response = await _dio.get(urlNow);
      response.data;
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

  List<dynamic> _getGroupSchedules(
    List<dynamic> media,
    Map<String, dynamic> data,
  ) {
    media.addAll(getActiveGroupSchedules(data, now: DateTime.now().toUtc()));
    return media;
  }

  List<dynamic> getActiveGroupSchedules(
    Map<String, dynamic> data, {
    DateTime? now,
  }) {
    final groupSchedules = data['group_schedules'] as Map<String, dynamic>;
    final slides = groupSchedules['slides'] as List<dynamic>;

    return slides.where((slide) {
      return _createRRule(slide as Map<String, dynamic>, now: now);
    }).toList();
  }

  List<dynamic> _getSystemSchedules(
    List<dynamic> media,
    Map<String, dynamic> data,
  ) {
    media.addAll(getActiveSystemSchedules(data, now: DateTime.now().toUtc()));
    return media;
  }

  List<dynamic> getActiveSystemSchedules(
    Map<String, dynamic> data, {
    DateTime? now,
  }) {
    final systemSchedules = data['system_schedules'] as Map<String, dynamic>;
    final slides = systemSchedules['slides'] as List<dynamic>;

    return slides.where((slide) {
      return _createRRule(slide as Map<String, dynamic>, now: now);
    }).toList();
  }

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

  void _downloadMedia(List<MediaLink> media) {
    _downloader.downloadAllMedia(links: media);
  }

  void _saveApiResponse(Map<String, dynamic> data) async {
    final directory = await _downloader.downloadDirectory;
    final system = SystemData.fromJson(data);
    final jsonDirectory = Directory('${directory.path}/json');
    final file = File('${jsonDirectory.path}/old_api_response.json');
    await file.create(recursive: true);
    final jsonString = const JsonEncoder.withIndent('  ').convert(system.toJson());
    await file.writeAsString(jsonString);
  }

  Map<String, dynamic> _loadOldApiResponse() {
    final file = File('assets/json/api_response.json');
    if (!file.existsSync()) {
      throw Exception('Old API response file not found.');
    }
    final jsonString = file.readAsStringSync();
    return jsonDecode(jsonString) as Map<String, dynamic>;
  }

  bool _compareApiResponses(Response newResponse) {
    final newData = newResponse.data;
    final oldData = _loadOldApiResponse();
    return newData == oldData;
  }

  String _getCurrentDate() {
    var now = DateTime.now();
    var formatter = DateFormat('yyyy-MM-dd');
    String formattedDate = formatter.format(now);
    return formattedDate;
  }

  Future<dynamic> _getSecrets() async {
    final String jsonString = await rootBundle.loadString(
      'assets/json/secrets.json',
    );

    return jsonDecode(jsonString);
  }

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
