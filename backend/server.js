import express from 'express';
import cors from 'cors';
import { HiAnime } from 'aniwatch';

const app = express();
const PORT = 3001;

app.use(cors());
app.use(express.json());

const hianime = new HiAnime.Scraper();

// Health check
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', message: 'ATOM ANIME Backend is running' });
});

// Get home page data (trending, latest, popular, etc.)
app.get('/api/home', async (req, res) => {
  try {
    const data = await hianime.getHomePage();
    res.json({ success: true, data });
  } catch (error) {
    console.error('Error fetching home:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Get anime info by ID
app.get('/api/anime/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const data = await hianime.getInfo(id);
    res.json({ success: true, data });
  } catch (error) {
    console.error('Error fetching anime info:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Search anime
app.get('/api/search', async (req, res) => {
  try {
    const { q, page = 1 } = req.query;
    if (!q) {
      return res.status(400).json({ success: false, error: 'Query parameter "q" is required' });
    }
    const data = await hianime.search(q, Number(page));
    res.json({ success: true, data });
  } catch (error) {
    console.error('Error searching anime:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Get search suggestions
app.get('/api/search/suggest', async (req, res) => {
  try {
    const { q } = req.query;
    if (!q) {
      return res.status(400).json({ success: false, error: 'Query parameter "q" is required' });
    }
    const data = await hianime.searchSuggestions(q);
    res.json({ success: true, data });
  } catch (error) {
    console.error('Error getting suggestions:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Get anime episodes
app.get('/api/anime/:id/episodes', async (req, res) => {
  try {
    const { id } = req.params;
    const data = await hianime.getEpisodes(id);
    console.log('Episodes response structure:', JSON.stringify(data, null, 2).substring(0, 1000));
    res.json({ success: true, data });
  } catch (error) {
    console.error('Error fetching episodes:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Get episode servers
app.get('/api/episode/:episodeId/servers', async (req, res) => {
  try {
    const episodeId = decodeURIComponent(req.params.episodeId);
    console.log('Getting servers for episode:', episodeId);
    const data = await hianime.getEpisodeServers(episodeId);
    res.json({ success: true, data });
  } catch (error) {
    console.error('Error fetching servers:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Get episode streaming sources
app.get('/api/episode/:episodeId/sources', async (req, res) => {
  try {
    const episodeId = decodeURIComponent(req.params.episodeId);
    const { server = 'hd-1', category = 'sub' } = req.query;
    console.log('Getting sources for episode:', episodeId, 'server:', server, 'category:', category);
    const data = await hianime.getEpisodeSources(episodeId, server, category);
    console.log('Sources result:', JSON.stringify(data).substring(0, 200));
    res.json({ success: true, data });
  } catch (error) {
    console.error('Error fetching sources:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Get A-Z anime list
app.get('/api/az-list', async (req, res) => {
  try {
    const { letter = 'all', page = 1 } = req.query;
    const data = await hianime.getAZList(letter, Number(page));
    res.json({ success: true, data });
  } catch (error) {
    console.error('Error fetching A-Z list:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Get anime by category (sub, dub, movie, tv, etc.)
app.get('/api/category/:category', async (req, res) => {
  try {
    const { category } = req.params;
    const { page = 1 } = req.query;
    const data = await hianime.getCategoryAnime(category, Number(page));
    res.json({ success: true, data });
  } catch (error) {
    console.error('Error fetching category:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Get anime by genre
app.get('/api/genre/:genre', async (req, res) => {
  try {
    const { genre } = req.params;
    const { page = 1 } = req.query;
    const data = await hianime.getGenreAnime(genre, Number(page));
    res.json({ success: true, data });
  } catch (error) {
    console.error('Error fetching genre:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Get schedule
app.get('/api/schedule', async (req, res) => {
  try {
    const { date } = req.query; // Format: YYYY-MM-DD
    const data = await hianime.getEstimatedSchedule(date || new Date().toISOString().split('T')[0]);
    res.json({ success: true, data });
  } catch (error) {
    console.error('Error fetching schedule:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

app.listen(PORT, () => {
  console.log(`🚀 ATOM ANIME Backend running at http://localhost:${PORT}`);
  console.log(`📺 Using aniwatch package for HiAnime data`);
});
