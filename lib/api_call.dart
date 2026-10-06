import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class ApiCall {
  ApiCall({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<Map<String, dynamic>> getJsonFromUrl() async {
    try {
      final secrets = await getSecrets();
      _dio.options.headers[secrets['api_header']] = secrets['api_key'];
      final url = secrets['api_url'];
      final urlNow = '$url?start=${getCurrentDate()}';
      
      final response = await _dio.get(urlNow);
      if (response.statusCode == 200) {
        return jsonDecode(response.data);
      } else {
        throw Exception('Failed to load JSON from $url');
      }
    } catch (e) {
      debugPrint('Error fetching JSON: $e');
      rethrow;
    }
  }

  String getCurrentDate() {
    var now = DateTime.now();
    var formatter = DateFormat('yyyy-MM-dd');
    String formattedDate = formatter.format(now);
    return formattedDate;
  }

 Future<Map<String, dynamic>> getSecrets() async{
    final secrets = await rootBundle.loadString('json/secrets.json');
    return jsonDecode(secrets);
  }
}