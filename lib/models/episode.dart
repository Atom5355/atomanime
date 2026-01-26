class Episode {
  final String id;
  final int number;
  final String? title;
  final String? thumbnail;
  final bool isFiller;
  final String? category; // 'sub', 'dub', or 'raw'

  Episode({
    required this.id,
    required this.number,
    this.title,
    this.thumbnail,
    this.isFiller = false,
    this.category,
  });

  factory Episode.fromJson(Map<String, dynamic> json) {
    return Episode(
      id: json['episodeId']?.toString() ?? json['id']?.toString() ?? '',
      number: json['number'] ?? 0,
      title: json['title'],
      thumbnail: json['image'],
      isFiller: json['isFiller'] == true,
      category: json['category'],
    );
  }
}

class StreamingLink {
  final String quality;
  final String url;
  final bool isM3U8;

  StreamingLink({
    required this.quality,
    required this.url,
    this.isM3U8 = false,
  });

  factory StreamingLink.fromJson(Map<String, dynamic> json) {
    return StreamingLink(
      quality: json['quality'] ?? 'default',
      url: json['url'] ?? '',
      isM3U8: json['isM3U8'] == true,
    );
  }
}

class SubtitleInfo {
  final String url;
  final String lang;
  final bool isDefault;

  SubtitleInfo({
    required this.url,
    required this.lang,
    this.isDefault = false,
  });

  factory SubtitleInfo.fromJson(Map<String, dynamic> json) {
    return SubtitleInfo(
      url: json['url'] ?? '',
      lang: json['lang'] ?? json['label'] ?? 'Unknown',
      isDefault: json['default'] == true,
    );
  }
}

class StreamingData {
  final List<StreamingLink> sources;
  final List<SubtitleInfo> subtitles;
  final Map<String, int> intro;
  final Map<String, int> outro;
  final String? referer;

  StreamingData({
    required this.sources,
    required this.subtitles,
    this.intro = const {},
    this.outro = const {},
    this.referer,
  });

  factory StreamingData.fromJson(Map<String, dynamic> json) {
    List<StreamingLink> sources = [];
    List<SubtitleInfo> subtitles = [];

    if (json['sources'] != null) {
      for (var source in json['sources']) {
        sources.add(StreamingLink.fromJson(source));
      }
    }

    if (json['tracks'] != null) {
      for (var track in json['tracks']) {
        // Only add subtitle tracks (not thumbnails)
        if (track['lang'] != 'thumbnails') {
          subtitles.add(SubtitleInfo.fromJson(track));
        }
      }
    }

    return StreamingData(
      sources: sources,
      subtitles: subtitles,
      intro: {
        'start': json['intro']?['start'] ?? 0,
        'end': json['intro']?['end'] ?? 0,
      },
      outro: {
        'start': json['outro']?['start'] ?? 0,
        'end': json['outro']?['end'] ?? 0,
      },
      referer: json['headers']?['Referer'],
    );
  }
}
