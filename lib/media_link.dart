class MediaLink {
  const MediaLink({required this.link, required this.type, this.duration, this.id, this.blobUrl, this.localPath});

  final String link;
  final String type;
  final double? duration;
  final String? id;
  final String? blobUrl;
  final String? localPath;
}
