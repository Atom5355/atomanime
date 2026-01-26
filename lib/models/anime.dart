/// Represents a related season of an anime
class RelatedSeason {
  final String id;
  final String title;
  final String? poster;
  final String? season;
  final bool isCurrent;

  RelatedSeason({
    required this.id,
    required this.title,
    this.poster,
    this.season,
    this.isCurrent = false,
  });

  factory RelatedSeason.fromJson(Map<String, dynamic> json, {bool isCurrent = false}) {
    return RelatedSeason(
      id: json['id']?.toString() ?? '',
      title: json['name']?.toString() ?? json['title']?.toString() ?? 'Unknown',
      poster: json['poster']?.toString(),
      season: json['season']?.toString(),
      isCurrent: isCurrent,
    );
  }
}

/// Represents the next airing episode schedule
class NextAiringEpisode {
  final int episodeNumber;
  final DateTime airingTime;

  NextAiringEpisode({
    required this.episodeNumber,
    required this.airingTime,
  });

  /// Time until the episode airs
  Duration get timeUntilAiring => airingTime.difference(DateTime.now());

  /// Whether the episode has already aired
  bool get hasAired => DateTime.now().isAfter(airingTime);
}

class Anime {
  final String id; // Changed to String for HiAnime IDs like "steinsgate-3"
  final String title;
  final String? romajiTitle;
  final String? englishTitle;
  final String? nativeTitle;
  final String? coverImage;
  final String? bannerImage;
  final String? description;
  final int? episodes;
  final int? subEpisodes;
  final int? dubEpisodes;
  final String? status;
  final int? averageScore;
  final List<String> genres;
  final int? year;
  final String? format;
  final String? duration;
  final String? rating;
  final NextAiringEpisode? nextAiringEpisode;
  final List<RelatedSeason> relatedSeasons;

  Anime({
    required this.id,
    required this.title,
    this.romajiTitle,
    this.englishTitle,
    this.nativeTitle,
    this.coverImage,
    this.bannerImage,
    this.description,
    this.episodes,
    this.subEpisodes,
    this.dubEpisodes,
    this.status,
    this.averageScore,
    this.genres = const [],
    this.year,
    this.format,
    this.duration,
    this.rating,
    this.nextAiringEpisode,
    this.relatedSeasons = const [],
  });

  /// Get landscape image URL by converting poster dimensions from 300x400 to 1366x768
  /// This works because the CDN uses the same image hash with different dimensions
  String? get landscapeImage {
    if (coverImage == null) return null;
    
    // If already a landscape image (1366x768), return as-is
    if (coverImage!.contains('1366x768')) return coverImage;
    
    // Convert portrait poster (300x400) to landscape (1366x768)
    // Pattern: https://cdn.noitatnemucod.net/thumbnail/300x400/100/hash.jpg
    final landscapeUrl = coverImage!.replaceFirst(
      RegExp(r'/thumbnail/\d+x\d+/'),
      '/thumbnail/1366x768/',
    );
    
    return landscapeUrl;
  }

  // Factory for HiAnime/aniwatch API response (list items)
  factory Anime.fromHiAnimeJson(Map<String, dynamic> json) {
    return Anime(
      id: json['id']?.toString() ?? '',
      title: json['name']?.toString() ?? json['title']?.toString() ?? 'Unknown',
      englishTitle: json['name']?.toString(),
      nativeTitle: json['jname']?.toString(),
      coverImage: json['poster']?.toString(),
      episodes: json['episodes']?['sub'] ?? json['episodes']?['dub'],
      subEpisodes: json['episodes']?['sub'],
      dubEpisodes: json['episodes']?['dub'],
      format: json['type']?.toString(),
      duration: json['duration']?.toString(),
      rating: json['rating']?.toString(),
    );
  }

  // Factory for HiAnime/aniwatch anime details
  factory Anime.fromHiAnimeDetailsJson(Map<String, dynamic> json) {
    final anime = json['anime'];
    final info = anime?['info'];
    final moreInfo = anime?['moreInfo'];
    
    List<String> genres = [];
    if (moreInfo?['genres'] != null) {
      genres = (moreInfo['genres'] as List<dynamic>).map((g) => g.toString()).toList();
    }

    // Parse related seasons
    List<RelatedSeason> relatedSeasons = [];
    if (json['seasons'] != null && json['seasons'] is List) {
      final seasons = json['seasons'] as List<dynamic>;
      final currentId = info?['id']?.toString() ?? '';
      for (final season in seasons) {
        if (season is Map<String, dynamic>) {
          final isCurrent = season['id']?.toString() == currentId || season['isCurrent'] == true;
          relatedSeasons.add(RelatedSeason.fromJson(season, isCurrent: isCurrent));
        }
      }
    }

    // Parse next airing episode if available (for ongoing anime)
    NextAiringEpisode? nextAiring;
    // Check moreInfo for airing schedule
    if (moreInfo?['status']?.toString().toLowerCase() == 'currently airing') {
      // Try to parse from moreInfo if schedule exists
      if (moreInfo?['nextAiringEpisode'] != null) {
        final nextEp = moreInfo['nextAiringEpisode'];
        final airingAt = nextEp['airingAt'];
        if (airingAt != null) {
          nextAiring = NextAiringEpisode(
            episodeNumber: nextEp['episode'] ?? ((info?['stats']?['episodes']?['sub'] ?? 0) + 1),
            airingTime: DateTime.fromMillisecondsSinceEpoch(airingAt * 1000),
          );
        }
      }
    }
    
    return Anime(
      id: info?['id']?.toString() ?? '',
      title: info?['name']?.toString() ?? 'Unknown',
      englishTitle: info?['name']?.toString(),
      nativeTitle: moreInfo?['japanese']?.toString(),
      coverImage: info?['poster']?.toString(),
      description: info?['description']?.toString(),
      episodes: info?['stats']?['episodes']?['sub'],
      subEpisodes: info?['stats']?['episodes']?['sub'],
      dubEpisodes: info?['stats']?['episodes']?['dub'],
      status: moreInfo?['status']?.toString(),
      averageScore: moreInfo?['malscore'] != null 
          ? (double.tryParse(moreInfo['malscore'].toString())?.toInt() ?? 0) * 10 
          : null,
      genres: genres,
      year: moreInfo?['aired'] != null 
          ? int.tryParse(moreInfo['aired'].toString().split(' ').last)
          : null,
      format: info?['stats']?['type']?.toString() ?? moreInfo?['type']?.toString(),
      duration: info?['stats']?['duration']?.toString() ?? moreInfo?['duration']?.toString(),
      rating: info?['stats']?['rating']?.toString(),
      nextAiringEpisode: nextAiring,
      relatedSeasons: relatedSeasons,
    );
  }
}
