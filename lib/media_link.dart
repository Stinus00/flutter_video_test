class MediaLink {
  const MediaLink({required this.link, required this.type, this.duration, this.id, this.mimeType, this.localPath});

  final String? id;
  final String link;
  final String type;
  final String? mimeType;
  final double? duration;
  final String? localPath;
}
