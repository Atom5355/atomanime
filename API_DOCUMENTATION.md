# API Documentation

## AniList GraphQL API

**Base URL:** `https://graphql.anilist.co`

### Authentication
No authentication required for basic queries.

### Queries Used

#### 1. Get Trending Anime
```graphql
query ($page: Int, $perPage: Int) {
  Page(page: $page, perPage: $perPage) {
    media(sort: TRENDING_DESC, type: ANIME) {
      id
      title {
        romaji
        english
        native
      }
      coverImage {
        large
        medium
      }
      bannerImage
      description
      episodes
      status
      averageScore
      genres
      seasonYear
      format
    }
  }
}
```

Variables:
```json
{
  "page": 1,
  "perPage": 20
}
```

#### 2. Get Popular Anime
```graphql
query ($page: Int, $perPage: Int) {
  Page(page: $page, perPage: $perPage) {
    media(sort: POPULARITY_DESC, type: ANIME) {
      id
      title {
        romaji
        english
        native
      }
      coverImage {
        large
        medium
      }
      bannerImage
      description
      episodes
      status
      averageScore
      genres
      seasonYear
      format
    }
  }
}
```

#### 3. Search Anime
```graphql
query ($search: String, $page: Int, $perPage: Int) {
  Page(page: $page, perPage: $perPage) {
    media(search: $search, type: ANIME) {
      id
      title {
        romaji
        english
        native
      }
      coverImage {
        large
        medium
      }
      bannerImage
      description
      episodes
      status
      averageScore
      genres
      seasonYear
      format
    }
  }
}
```

Variables:
```json
{
  "search": "naruto",
  "page": 1,
  "perPage": 20
}
```

#### 4. Get Anime Details
```graphql
query ($id: Int) {
  Media(id: $id, type: ANIME) {
    id
    title {
      romaji
      english
      native
    }
    coverImage {
      large
      medium
    }
    bannerImage
    description
    episodes
    status
    averageScore
    genres
    seasonYear
    format
  }
}
```

Variables:
```json
{
  "id": 1535
}
```

---

## Consumet API (GogoAnime)

**Base URL:** `https://api.consumet.org/anime/gogoanime`

### Endpoints

#### 1. Search Anime
```http
GET /anime/gogoanime/{query}
```

Example:
```
GET https://api.consumet.org/anime/gogoanime/naruto
```

Response:
```json
{
  "results": [
    {
      "id": "naruto",
      "title": "Naruto",
      "image": "https://...",
      "releaseDate": "2002",
      "subOrDub": "sub"
    }
  ]
}
```

#### 2. Get Anime Info & Episodes
```http
GET /anime/gogoanime/info/{animeId}
```

Example:
```
GET https://api.consumet.org/anime/gogoanime/info/naruto
```

Response:
```json
{
  "id": "naruto",
  "title": "Naruto",
  "image": "https://...",
  "description": "...",
  "episodes": [
    {
      "id": "naruto-episode-1",
      "number": 1,
      "title": "Enter: Naruto Uzumaki!",
      "image": "https://..."
    }
  ]
}
```

#### 3. Get Streaming Links
```http
GET /anime/gogoanime/watch/{episodeId}
```

Example:
```
GET https://api.consumet.org/anime/gogoanime/watch/naruto-episode-1
```

Response:
```json
{
  "sources": [
    {
      "url": "https://...",
      "quality": "720p"
    },
    {
      "url": "https://...",
      "quality": "480p"
    }
  ],
  "download": "https://..."
}
```

---

## Rate Limits

### AniList
- **Rate Limit:** 90 requests per minute
- **Burst:** Short bursts allowed
- **Recommendation:** Cache responses when possible

### Consumet API
- **Rate Limit:** Community-hosted, may vary
- **Recommendation:** Implement retry logic for failed requests
- **Note:** Free tier, subject to availability

---

## Error Handling

### Common Error Codes

#### AniList
- `400` - Bad Request (invalid query)
- `404` - Not Found (invalid ID)
- `429` - Too Many Requests (rate limited)
- `500` - Server Error

#### Consumet
- `404` - Anime/Episode not found
- `500` - Server Error
- Network errors - API may be down

### Handling in App

```dart
try {
  final response = await http.post(url);
  if (response.statusCode == 200) {
    // Success
  } else if (response.statusCode == 429) {
    // Rate limited - wait and retry
  } else {
    // Other error
  }
} catch (e) {
  // Network error or parsing error
}
```

---

## Best Practices

1. **Caching**
   - Cache anime data to reduce API calls
   - Use `cached_network_image` for images

2. **Error Recovery**
   - Implement retry logic
   - Show user-friendly error messages
   - Fallback to cached data when possible

3. **Performance**
   - Paginate results
   - Lazy load episode lists
   - Preload next episode data

4. **User Experience**
   - Show loading states
   - Handle network errors gracefully
   - Provide search suggestions

---

## Alternative APIs

If the current APIs are unavailable, consider:

1. **Jikan API** (MyAnimeList)
   - URL: https://api.jikan.moe/v4
   - Free, no auth required

2. **Kitsu API**
   - URL: https://kitsu.io/api/edge
   - RESTful API

3. **AniAPI**
   - URL: https://aniapi.com
   - Requires API key

---

## Testing APIs

### cURL Examples

**AniList:**
```bash
curl -X POST https://graphql.anilist.co \
  -H "Content-Type: application/json" \
  -d '{"query":"{ Media(id: 1535) { title { english } } }"}'
```

**Consumet:**
```bash
curl https://api.consumet.org/anime/gogoanime/naruto
```

---

## Resources

- [AniList API Docs](https://anilist.gitbook.io/anilist-apiv2-docs/)
- [Consumet GitHub](https://github.com/consumet/api.consumet.org)
- [GraphQL Playground](https://graphql.org/swapi-graphql)
