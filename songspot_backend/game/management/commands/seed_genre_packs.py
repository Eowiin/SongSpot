"""
Seed packs for each music category by fetching ranked tracks from Deezer.

Strategy:
- Fetch candidate tracks via Deezer genre chart (stable, rank-ordered)
- Fall back to artist-based fetching if chart returns insufficient results
- Sort all candidates by rank (highest = most famous first)
- Exclude tracks already in any pack of the same category (no duplicates)
- Fill pack in rank order: most famous songs first
- Name packs automatically based on how many packs of that category exist:
    1st → "{Category} — Mega Hits"
    2nd → "{Category} — Top Hits"
    3rd → "{Category} — Hits"
    4th+ → "{Category} Vol. N"

Run --list-genres to print all Deezer genre IDs and verify the CATEGORY_MAP below.
"""

from django.core.management.base import BaseCommand

from game.models import SongPack, Track, PackTrack
from game.services import DeezerService


# Deezer genre IDs verified against GET https://api.deezer.com/genre
# Categories using playlist_id instead of genre_id fetch from an editorial playlist.
CATEGORY_MAP = {
    'pop': {
        'name': 'Pop',
        'genre_id': 132,
    },
    'hiphop': {
        'name': 'Hip-Hop / Rap',
        'genre_id': 116,
    },
    'rock': {
        'name': 'Rock',
        'genre_id': 152,
    },
    'electro': {
        'name': 'Électro',
        'genre_id': 106,
    },
    'dance': {
        'name': 'Dance',
        'genre_id': 113,
        'search_queries': [
            'Avicii', 'David Guetta', 'Calvin Harris', 'Martin Garrix',
            'Tiësto', 'Marshmello', 'Kygo', 'Robin Schulz',
            'Galantis', 'Zedd', 'Alan Walker', 'Afrojack',
            'Swedish House Mafia', 'Illenium', 'Diplo',
            'Hardwell', 'Armin van Buuren', 'W&W', 'Nicky Romero',
            'Don Diablo', 'Quintino', 'Oliver Heldens', 'Sam Feldt',
            'Jonas Blue', 'Sigala', 'Alle Farben', 'Lost Frequencies',
        ],
    },
    'rnb': {
        'name': 'R&B',
        'genre_id': 165,
    },
    'kpop': {
        'name': 'K-pop',
        'genre_id': None,       # No dedicated K-pop genre on Deezer; search queries are the sole source
        'search_queries': [
            # 4th gen
            'BTS', 'BLACKPINK', 'TWICE', 'aespa', 'IVE',
            'NewJeans', 'Stray Kids', 'SEVENTEEN', 'NCT 127', 'NCT Dream',
            'ATEEZ', 'TXT', 'ENHYPEN', 'Le Sserafim', 'ITZY',
            'Kep1er', 'NMIXX', 'fromis_9', 'MONSTA X', '(G)I-DLE',
            # 3rd gen
            'EXO', 'GOT7', 'SHINee', 'Red Velvet', 'MAMAMOO',
            'Wanna One', 'iKON', 'WINNER', 'ASTRO kpop', 'VIXX',
            'B.A.P.', 'Block B', 'BEAST kpop', 'Apink', 'GFRIEND',
            # soloists
            'IU kpop', 'Taeyeon', 'PSY', 'G-Dragon', 'Taeyang',
            'CL kpop', 'Lee Hi', 'Zico kpop', 'Crush kpop', 'Dean kpop',
            # 1st & 2nd gen legends
            'BIGBANG', 'Super Junior', '2NE1', 'Girls Generation', 'SHINee',
            'H.O.T', 'BoA kpop', 'Rain kpop', 'Se7en kpop', 'Fin.K.L',
        ],
    },
    'rap_fr': {
        'name': 'Rap Français',
        'genre_id': 116,        # hip-hop genre for artist pool
        # Search queries guarantee French artists are well represented
        'search_queries': [
            'Jul', 'PNL', 'Nekfeu', 'Orelsan', 'Ninho', 'Booba',
            'Kaaris', 'Damso', 'SCH', 'Hamza', 'Lomepal', 'Laylow',
            'Vald', 'Gradur', 'Aya Nakamura rap', 'Gims',
            'Niska', 'Freeze Corleone', 'Gambi', 'Gazo',
            'Lacrim', 'Rohff', 'Soprano rap', 'Oxmo Puccino',
            'IAM rap', 'NTM rap', 'Lunatic rap', 'Kery James',
            'Josman', 'Pilule', 'Imen ES', 'PLK',
        ],
    },
    'variete_fr': {
        'name': 'Variété Française',
        'genre_id': 52,         # Chanson française
        'search_queries': [
            # classics
            'Edith Piaf', 'Charles Aznavour', 'Jacques Brel', 'Michel Sardou',
            'Georges Brassens', 'Serge Gainsbourg', 'Françoise Hardy',
            'Claude François', 'Dalida', 'Joe Dassin', 'Johnny Hallyday',
            # modern
            'Stromae', 'Clara Luciani', 'Angèle', 'Zaz',
            'Patrick Bruel', 'Véronique Sanson', 'Francis Cabrel',
            'Mika', 'Soprano variété', 'Christophe Maé',
            'Amel Bent', 'Calogero', 'Julien Doré', 'Louane',
            'Slimane', 'Vianney', 'Hoshi', 'Cœur de Pirate',
        ],
    },
    'reggaeton': {
        'name': 'Reggaeton / Urbano',
        'genre_id': 197,        # Latin genre
        'search_queries': [
            'Bad Bunny', 'J Balvin', 'Maluma', 'Ozuna', 'Anuel AA',
            'Karol G', 'Daddy Yankee', 'Nicky Jam', 'Sech', 'Myke Towers',
            'Farruko', 'Don Omar', 'Wisin', 'Yandel', 'Rauw Alejandro',
            'Jhay Cortez', 'Lunay', 'Jhayco', 'Bryant Myers', 'Arcangel',
            'De La Ghetto', 'Ñengo Flow', 'Lenny Tavárez', 'Mora reggaeton',
            'Chencho Corleone', 'Justin Quiles', 'Eladio Carrion',
        ],
    },
    'latin': {
        'name': 'Latin Pop',
        'genre_id': 197,        # same base genre
        'search_queries': [
            'Shakira', 'Enrique Iglesias', 'Ricky Martin', 'Jennifer Lopez',
            'Marc Anthony', 'Luis Fonsi', 'Sebastian Yatra', 'Carlos Vives',
            'Juanes', 'Alejandro Sanz', 'Camilo', 'Paulo Londra', 'CNCO',
            'Maluma pop', 'Karol G pop', 'Becky G', 'Natti Natasha',
            'Leslie Grace', 'Anitta', 'Gloria Estefan', 'Chayanne',
            'Marco Antonio Solís', 'Ricardo Montaner', 'Sin Bandera',
            'Reik', 'Ha-Ash', 'Jesse & Joy', 'Morat',
        ],
    },
    'afrobeats': {
        'name': 'Afrobeats',
        'genre_id': 2,          # Musique africaine
        'search_queries': [
            'Burna Boy', 'Wizkid', 'Davido', 'Tems', 'Omah Lay',
            'Ckay', 'Rema', 'Fireboy DML', 'Asake', 'Kizz Daniel',
            'Tiwa Savage', 'Yemi Alade', 'Mr Eazi', 'Joeboy',
            'Ayra Starr', 'Oxlade', 'Ruger afrobeats', 'Zinoleesky',
            'Lojay', 'Victony', 'BNXN', 'Seun Kuti',
            'Fela Kuti', 'Adekunle Gold', 'Simi afrobeats', 'Flavour',
            'Phyno', 'Olamide', 'Naira Marley', 'Patoranking',
        ],
    },
    'jpop': {
        'name': 'J-pop',
        'genre_id': None,       # No dedicated J-pop genre on Deezer; search queries are the sole source
        'search_queries': [
            # modern
            'Kenshi Yonezu', 'Official Hige Dandism', 'Ado', 'YOASOBI',
            'King Gnu', 'Mrs. GREEN APPLE', 'LiSA', 'Fujii Kaze',
            'Yorushika', 'Eve jpop', 'Radwimps', 'Creepy Nuts',
            'Vaundy', 'imase', 'Tatsuya Kitani', 'Atarashii Gakko',
            'Zutomayo', 'syudou', 'Reol', 'Daoko',
            # anime & game osts
            'Hikaru Utada', 'Aimer', 'ClariS', 'Nana Mizuki',
            'T.M. Revolution', 'Fripside', 'Nano jpop', 'GARNiDELiA',
            # rock & alternative jpop
            'ONE OK ROCK', 'Bump of Chicken', 'Back Number',
            'Spitz', 'Mr.Children', 'B z jpop', 'L Arc en Ciel',
            # pop idols & classics
            'Perfume jpop', 'Kyary Pamyu Pamyu', 'AKB48',
            'Arashi', 'SMAP', 'Namie Amuro', 'Koda Kumi',
            'Ayumi Hamasaki', 'Speed jpop', 'Globe jpop',
        ],
    },
    'bollywood': {
        'name': 'Bollywood',
        'genre_id': 81,         # Musique indienne
        # Search queries supplement the chart with well-known Bollywood artists
        'search_queries': [
            # modern
            'Arijit Singh', 'Shreya Ghoshal', 'AR Rahman', 'Pritam',
            'Atif Aslam', 'Neha Kakkar', 'Vishal Shekhar', 'Shankar Ehsaan Loy',
            'Guru Randhawa', 'Badshah', 'Armaan Malik', 'Jubin Nautiyal',
            'Darshan Raval', 'Dhvani Bhanushali', 'Tulsi Kumar', 'B Praak',
            'Tanishk Bagchi', 'Yo Yo Honey Singh', 'Raftaar', 'Divine rapper',
            # classics
            'Kumar Sanu', 'Udit Narayan', 'Lata Mangeshkar', 'Kishore Kumar',
            'Mohammed Rafi', 'Asha Bhosle', 'Alka Yagnik', 'Sonu Nigam',
            'Kavita Krishnamurthy', 'S.P. Balasubrahmanyam',
        ],
    },
}

# Pack name templates by how many packs of that category already exist (0-indexed)
PACK_NAME_TIERS = [
    '— Mega Hits',
    '— Top Hits',
    '— Hits',
]

# Minimum Deezer rank to include a track (0–1,000,000 scale)
DEFAULT_MIN_RANK = 400_000


class Command(BaseCommand):
    help = 'Fetch ranked tracks from Deezer and create genre packs.'

    def add_arguments(self, parser):
        parser.add_argument(
            '--categories',
            type=str,
            default=','.join(CATEGORY_MAP.keys()),
            help='Comma-separated category keys to seed (default: all)',
        )
        parser.add_argument(
            '--count-per-pack',
            type=int,
            default=30,
            help='Tracks per pack (default: 30)',
        )
        parser.add_argument(
            '--min-rank',
            type=int,
            default=DEFAULT_MIN_RANK,
            help=f'Minimum Deezer rank to include a track (default: {DEFAULT_MIN_RANK})',
        )
        parser.add_argument(
            '--max-per-artist',
            type=int,
            default=3,
            help='Maximum tracks per artist in a pack (default: 3)',
        )
        parser.add_argument(
            '--artist-pool',
            type=int,
            default=200,
            help='Number of genre artists to sample when chart falls short (default: 200)',
        )
        parser.add_argument(
            '--list-genres',
            action='store_true',
            help='Print all Deezer genre IDs and exit (useful to verify CATEGORY_MAP)',
        )
        parser.add_argument(
            '--price-coins',
            type=int,
            default=1000,
            help='Price of each created pack in coins (default: 1000)',
        )

    def handle(self, *args, **options):
        deezer = DeezerService()

        if options['list_genres']:
            self._list_genres(deezer)
            return

        categories = [c.strip().lower() for c in options['categories'].split(',') if c.strip()]
        count_per_pack = options['count_per_pack']
        min_rank = options['min_rank']
        max_per_artist = options['max_per_artist']
        artist_pool = options['artist_pool']
        price_coins = options['price_coins']

        for category_key in categories:
            config = CATEGORY_MAP.get(category_key)
            if not config:
                self.stdout.write(self.style.WARNING(f'Unknown category: {category_key} — skipping'))
                continue
            self._seed_category(
                deezer, category_key, config,
                count_per_pack, min_rank, max_per_artist, artist_pool, price_coins,
            )

    def _seed_category(self, deezer, category_key, config, count_per_pack, min_rank, max_per_artist, artist_pool, price_coins):  # noqa: E501
        category_name = config['name']
        genre_id = config.get('genre_id')
        playlist_id = config.get('playlist_id')

        self.stdout.write(self.style.WARNING(f'\n=== {category_name} ==='))

        # Collect tracks already used in any pack of this category to avoid overlap
        existing_packs = SongPack.objects.filter(category=category_key)
        used_track_ids = set(
            PackTrack.objects.filter(pack__in=existing_packs)
            .values_list('track_id', flat=True)
        )
        self.stdout.write(f'Existing packs: {existing_packs.count()} | Used tracks: {len(used_track_ids)}')

        # Fetch candidates
        search_queries = config.get('search_queries', [])
        raw_candidates = self._fetch_candidates(deezer, genre_id, playlist_id, search_queries, artist_pool)
        if not raw_candidates:
            self.stdout.write(self.style.ERROR(f'No candidates found for {category_name}'))
            return

        # Extract, filter, deduplicate by deezer_id, sort by rank
        seen_deezer_ids = set()
        candidates = []
        for raw in raw_candidates:
            info = deezer.extract_track_info(raw)
            if not info['preview_url']:
                continue
            deezer_id = info.get('deezer_id')
            if deezer_id in seen_deezer_ids:
                continue
            seen_deezer_ids.add(deezer_id)
            candidates.append(info)

        # Sort by rank descending (most famous first)
        candidates.sort(key=lambda t: t.get('rank', 0), reverse=True)

        # Filter by minimum rank; lower threshold if not enough candidates
        filtered = [t for t in candidates if t.get('rank', 0) >= min_rank]
        if len(filtered) < count_per_pack:
            self.stdout.write(self.style.WARNING(
                f'Only {len(filtered)} tracks above rank {min_rank}. '
                f'Using all {len(candidates)} candidates instead.'
            ))
            filtered = candidates

        # Select tracks: most famous first, skipping already-used, max N per artist
        selected_tracks = []
        artist_counts = {}
        for info in filtered:
            if len(selected_tracks) >= count_per_pack:
                break

            track, _ = Track.objects.get_or_create(
                title=info['title'],
                artist=info['artist'],
                defaults={
                    'preview_url': info['preview_url'],
                    'cover_url': info.get('cover_url'),
                    'deezer_id': info.get('deezer_id'),
                    'release_year': info.get('release_year'),
                    'genre': info.get('genre') or config['name'],
                },
            )

            if track.id in used_track_ids:
                continue

            artist = info['artist']
            if artist_counts.get(artist, 0) >= max_per_artist:
                continue

            selected_tracks.append(track)
            used_track_ids.add(track.id)
            artist_counts[artist] = artist_counts.get(artist, 0) + 1

        if not selected_tracks:
            self.stdout.write(self.style.ERROR(f'No tracks available — skipping {category_name}'))
            return

        if len(selected_tracks) < count_per_pack:
            self.stdout.write(self.style.WARNING(
                f'Only {len(selected_tracks)}/{count_per_pack} unique tracks found.'
            ))

        # Determine pack name based on existing pack count for this category
        pack_name = self._pack_name(category_name, existing_packs.count())

        pack = SongPack.objects.create(
            name=pack_name,
            description=f'{category_name} stem pack.',
            category=category_key,
            price_coins=price_coins,
            is_featured=True,
            auto_unlock=False,
        )
        for order, track in enumerate(selected_tracks, start=1):
            PackTrack.objects.create(pack=pack, track=track, order_in_pack=order)

        self.stdout.write(self.style.SUCCESS(
            f'Created "{pack_name}" with {len(selected_tracks)} tracks.'
        ))

    def _fetch_candidates(self, deezer, genre_id, playlist_id, search_queries, artist_pool):
        """
        Fetch a large pool of raw track dicts (~500+).
        1. Genre chart (rank-ordered, geo-stable)
        2. Editorial playlist (optional)
        3. Search queries (for categories without a genre_id, e.g. Bollywood, Rap FR)
        4. Artist-based fill — always runs for genre_id categories to expand the pool
           to hundreds of candidates so rank-filtering and deduplication leave enough tracks.
        """
        candidates = []

        if genre_id:
            # Fetch up to 200 from the genre chart
            chart_tracks = deezer.get_genre_chart_tracks(genre_id, limit=200)
            candidates.extend(chart_tracks)
            self.stdout.write(f'  Chart ({genre_id}): {len(chart_tracks)} tracks')

        if playlist_id:
            playlist_tracks = deezer.get_playlist_tracks(playlist_id, limit=100)
            candidates.extend(playlist_tracks)
            self.stdout.write(f'  Playlist ({playlist_id}): {len(playlist_tracks)} tracks')

        # Search queries expand the pool for categories that need geographic specificity
        # (Rap FR, Bollywood, Reggaeton/Latin, etc.)
        for query in search_queries:
            result = deezer.search_track(query, limit=50)
            tracks = result.get('data', []) if isinstance(result, dict) else []
            candidates.extend(tracks)

        if search_queries:
            self.stdout.write(f'  Search queries ({len(search_queries)}): added tracks')

        # Artist-based fill always runs for genre_id categories.
        # The chart alone gives ~100-200 tracks; after cross-pack dedup and max-per-artist
        # filtering that often leaves fewer than 30.  Fetching top-5 from each genre artist
        # pushes the raw pool to 500+ so the selection step always has enough to work with.
        if genre_id:
            artists = deezer.get_genre_artists(genre_id, limit=artist_pool)
            added = 0
            for artist in artists:
                artist_id = artist.get('id')
                if not artist_id:
                    continue
                top_tracks = deezer.get_artist_top_tracks(artist_id, limit=10)
                candidates.extend(top_tracks)
                added += len(top_tracks)
                if len(candidates) >= 600:
                    break
            self.stdout.write(f'  Artist fallback: {added} tracks from {len(artists)} artists')

        self.stdout.write(f'  Total raw candidates: {len(candidates)}')
        return candidates

    @staticmethod
    def _pack_name(category_name, existing_count):
        """
        1st pack → "{Category} — Mega Hits"
        2nd pack → "{Category} — Top Hits"
        3rd pack → "{Category} — Hits"
        4th+ pack → "{Category} Vol. N"
        """
        if existing_count < len(PACK_NAME_TIERS):
            return f'{category_name} {PACK_NAME_TIERS[existing_count]}'
        return f'{category_name} Vol. {existing_count + 1}'

    def _list_genres(self, deezer):
        genres = deezer.list_genres()
        if not genres:
            self.stdout.write(self.style.ERROR('Could not fetch genres from Deezer.'))
            return
        self.stdout.write(self.style.SUCCESS(f'{"ID":<8} {"Name"}'))
        self.stdout.write('-' * 40)
        for g in sorted(genres, key=lambda x: x.get('name', '')):
            self.stdout.write(f'{g["id"]:<8} {g["name"]}')
