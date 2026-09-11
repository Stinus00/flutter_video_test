/// Representation of a video returned by the video API.
class Video {
  Video({
    required this.title,
    required this.videoUrl,
    required this.duration,
    required this.thumbnailUrl,
    this.uploadTime,
    this.views,
    this.author,
    this.isLive,
    this.subscriber,
    this.description,
  });

  final String title;
  final String videoUrl;
  final String duration;
  final String thumbnailUrl;
  final String? uploadTime;
  final String? views;
  final String? author;
  final bool? isLive;
  final String? subscriber;
  final String? description;

  /// Creates a video from a JSON object.
  static Video fromJson(Map<String, Object?> json) {
    String requiredString(String key) {
      final value = json[key];
      if (value is String) return value;
      throw FormatException('Missing or invalid $key, json=$json');
    }

    String? optionalString(String key) => json[key] as String?;

    return Video(
      title: requiredString('title'),
      videoUrl: requiredString('videoUrl'),
      duration: requiredString('duration'),
      thumbnailUrl: requiredString('thumbnailUrl'),
      uploadTime: optionalString('uploadTime'),
      views: optionalString('views'),
      author: optionalString('author'),
      isLive: json['isLive'] as bool?,
      subscriber: optionalString('subscriber'),
      description: optionalString('description'),
    );
  }

  /// Creates a list of videos from a JSON array.
  static List<Video> fromJsonList(Object? json) {
    if (json is! List) {
      throw FormatException('Expected a list of videos, json=$json');
    }

    return json.map((item) {
      if (item is! Map) {
        throw FormatException('Expected a video object, json=$item');
      }
      return Video.fromJson(Map<String, Object?>.from(item));
    }).toList();
  }

  @override
  String toString() =>
      'Video['
      'title=$title, '
      'videoUrl=$videoUrl, '
      'duration=$duration, '
      'thumbnailUrl=$thumbnailUrl, '
      'uploadTime=${uploadTime ?? 'null'}, '
      'views=${views ?? 'null'}, '
      'author=${author ?? 'null'}, '
      'isLive=${isLive ?? 'null'}, '
      'subscriber=${subscriber ?? 'null'}, '
      'description=${description ?? 'null'}'
      ']';
}