"""
Seed packs for each music category by fetching ranked tracks from Deezer.

Strategy (two modes depending on the category):

1. Genre chart (categories with a reliable Deezer genre_id):
   - Page through GET /chart/{genre_id}/tracks (100 tracks/page)
   - Tracks are already genre-filtered by Deezer — includes new artists automatically
   - Apply max-per-artist limit and cross-pack dedup as we go
   - Stop as soon as we have enough tracks OR the chart is exhausted

2. Search queries (categories without a reliable Deezer genre chart, e.g. K-pop, Rap FR):
   - Fetch results for each artist query, sort by rank, apply same filters

In both cases: if fewer than --count-per-pack tracks can be found, no pack is created.

Run --list-genres to print all Deezer genre IDs and verify the CATEGORY_MAP below.
"""

from django.core.management.base import BaseCommand

from game.models import SongPack, Track, PackTrack
from game.services import DeezerService


# Deezer genre IDs verified against GET https://api.deezer.com/genre
# Categories with only genre_id use the Deezer genre chart (already genre-filtered).
# Categories with search_queries use artist search (for genres Deezer doesn't chart well).
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
    'rnb': {
        'name': 'R&B',
        'genre_id': 165,
    },
    'dance': {
        'name': 'Dance',
        'genre_id': 113,
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
        'genre_id': None,
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
        'genre_id': 52,         # Chanson française — chart is reliable here
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
        'genre_id': None,
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
        'genre_id': None,
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

# How many chart tracks to fetch per API page
CHART_PAGE_SIZE = 100


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
            '--list-genres',
            action='store_true',
            help='Print all Deezer genre IDs and exit (useful to verify CATEGORY_MAP)',
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

        for category_key in categories:
            config = CATEGORY_MAP.get(category_key)
            if not config:
                self.stdout.write(self.style.WARNING(f'Unknown category: {category_key} — skipping'))
                continue
            self._seed_category(
                deezer, category_key, config,
                count_per_pack, min_rank, max_per_artist,
            )

    def _seed_category(self, deezer, category_key, config, count_per_pack, min_rank, max_per_artist):
        category_name = config['name']
        genre_id = config.get('genre_id')
        search_queries = config.get('search_queries', [])

        self.stdout.write(self.style.WARNING(f'\n=== {category_name} ==='))

        # Tracks already used in any pack of this category (no cross-pack duplicates)
        existing_packs = SongPack.objects.filter(category=category_key)
        used_track_ids = set(
            PackTrack.objects.filter(pack__in=existing_packs)
            .values_list('track_id', flat=True)
        )
        self.stdout.write(f'Existing packs: {existing_packs.count()} | Used tracks: {len(used_track_ids)}')

        artist_counts: dict[str, int] = {}

        if search_queries:
            # Categories without a reliable Deezer genre chart (K-pop, Rap FR, etc.):
            # collect candidates from search queries, sort by rank, then filter.
            selected_tracks = self._select_from_queries(
                deezer, search_queries, used_track_ids, artist_counts,
                count_per_pack, min_rank, max_per_artist, category_name,
            )
        elif genre_id:
            # Categories with a reliable Deezer genre chart:
            # page through the chart; every track is already genre-filtered by Deezer.
            selected_tracks = self._select_from_chart(
                deezer, genre_id, used_track_ids, artist_counts,
                count_per_pack, min_rank, max_per_artist, category_name,
            )
        else:
            self.stdout.write(self.style.ERROR(
                f'No genre_id or search_queries for {category_name} — skipping'
            ))
            return

        if len(selected_tracks) < count_per_pack:
            self.stdout.write(self.style.WARNING(
                f'Only {len(selected_tracks)}/{count_per_pack} tracks found — skipping pack creation.'
            ))
            return

        pack_name = self._pack_name(category_name, existing_packs.count())
        pack = SongPack.objects.create(
            name=pack_name,
            description=f'{category_name} pack.',
            category=category_key,
        )
        for order, track in enumerate(selected_tracks, start=1):
            PackTrack.objects.create(pack=pack, track=track, order_in_pack=order)

        self.stdout.write(self.style.SUCCESS(
            f'Created "{pack_name}" with {len(selected_tracks)} tracks.'
        ))

    # ------------------------------------------------------------------
    # Selection helpers
    # ------------------------------------------------------------------

    def _select_from_chart(self, deezer, genre_id, used_track_ids, artist_counts,
                           count_per_pack, min_rank, max_per_artist, category_name):
        """
        Page through the Deezer genre chart until count_per_pack tracks are
        selected or the chart is exhausted. Tracks from the chart are already
        genre-filtered by Deezer, so no artist pool is needed.
        """
        selected_tracks = []
        seen_deezer_ids: set[int] = set()
        page = 0

        while len(selected_tracks) < count_per_pack:
            raw_page = deezer.get_genre_chart_tracks(
                genre_id, limit=CHART_PAGE_SIZE, index=page * CHART_PAGE_SIZE
            )
            if not raw_page:
                self.stdout.write(f'  Chart exhausted after {page} page(s).')
                break

            self.stdout.write(f'  Chart page {page + 1}: {len(raw_page)} tracks')
            page += 1

            for raw in raw_page:
                if len(selected_tracks) >= count_per_pack:
                    break

                track = self._try_select(
                    deezer, raw, used_track_ids, artist_counts,
                    seen_deezer_ids, min_rank, max_per_artist, category_name,
                )
                if track:
                    selected_tracks.append(track)

        return selected_tracks

    def _select_from_queries(self, deezer, search_queries, used_track_ids, artist_counts,
                             count_per_pack, min_rank, max_per_artist, category_name):
        """
        Fetch all candidates via artist search queries, sort by rank descending,
        then pick greedily until count_per_pack is reached.
        """
        seen_deezer_ids: set[int] = set()
        candidates = []

        for query in search_queries:
            result = deezer.search_track(query, limit=50)
            tracks = result.get('data', []) if isinstance(result, dict) else []
            for raw in tracks:
                deezer_id = raw.get('id')
                if deezer_id and deezer_id not in seen_deezer_ids:
                    seen_deezer_ids.add(deezer_id)
                    candidates.append(raw)

        self.stdout.write(f'  Search queries ({len(search_queries)}): {len(candidates)} unique raw tracks')

        # Sort by Deezer rank descending so we pick the most famous songs first
        candidates.sort(key=lambda t: t.get('rank', 0), reverse=True)

        # Reset seen_deezer_ids — we deduplicated during collection above,
        # but _try_select also checks it so pass a fresh set.
        seen_for_select: set[int] = set()
        selected_tracks = []

        for raw in candidates:
            if len(selected_tracks) >= count_per_pack:
                break
            track = self._try_select(
                deezer, raw, used_track_ids, artist_counts,
                seen_for_select, min_rank, max_per_artist, category_name,
            )
            if track:
                selected_tracks.append(track)

        return selected_tracks

    def _try_select(self, deezer, raw, used_track_ids, artist_counts,
                    seen_deezer_ids, min_rank, max_per_artist, category_name):
        """
        Extract track info, apply all filters, persist to DB if it passes.
        Returns a Track instance on success, None otherwise.
        """
        info = deezer.enrich_track_info(raw, fallback_genre=category_name)

        if not info['preview_url']:
            return None
        if info.get('rank', 0) < min_rank:
            return None

        deezer_id = info.get('deezer_id')
        if deezer_id in seen_deezer_ids:
            return None
        seen_deezer_ids.add(deezer_id)

        artist = info['artist']
        if artist_counts.get(artist, 0) >= max_per_artist:
            return None

        track, _ = Track.objects.get_or_create(
            title=info['title'],
            artist=info['artist'],
            defaults={
                'preview_url': info['preview_url'],
                'cover_url': info.get('cover_url'),
                'deezer_id': deezer_id,
                'release_year': info.get('release_year'),
                'genre': info.get('genre') or category_name,
            },
        )

        update_fields = []
        field_updates = {
            'cover_url': info.get('cover_url'),
            'deezer_id': deezer_id,
            'release_year': info.get('release_year'),
            'genre': info.get('genre') or category_name,
        }
        for field, new_value in field_updates.items():
            if not new_value:
                continue
            current_value = getattr(track, field)
            if current_value in (None, ''):
                setattr(track, field, new_value)
                update_fields.append(field)

        if update_fields:
            track.save(update_fields=update_fields)

        if track.id in used_track_ids:
            return None

        used_track_ids.add(track.id)
        artist_counts[artist] = artist_counts.get(artist, 0) + 1
        return track

    # ------------------------------------------------------------------
    # Utilities
    # ------------------------------------------------------------------

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
