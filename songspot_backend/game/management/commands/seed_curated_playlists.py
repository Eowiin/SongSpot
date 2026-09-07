"""
One-time command to populate all playlists from the existing artist library.
Edit ARTIST_MAP below to adjust any placement, then re-run.

  python manage.py seed_curated_playlists --dry-run   # preview
  python manage.py seed_curated_playlists              # apply
"""
from django.core.management.base import BaseCommand
from game.models import Playlist, PlaylistTrack, Track

ARTIST_MAP = {
    'pop': [
        'Adele', 'Anne-Marie', 'Ariana Grande', 'Billie Eilish', 'Billy Joel',
        'Camila Cabello', 'Cat Burns', 'Chappell Roan', 'Charlie Puth', 'Coldplay',
        'Doja Cat', 'Dua Lipa', 'Ed Sheeran', 'Ellie Goulding', 'Elton John',
        'Faouzia', 'George Michael', 'Harry Styles', 'Imagine Dragons', 'Jason Derulo',
        'Jessie J', 'Justin Bieber', 'Justin Timberlake', 'Katy Perry', 'Lady Gaga',
        'Lana Del Rey', 'Madonna', 'Mark Ronson', 'Maroon 5', 'Miley Cyrus',
        'Naughty Boy', 'Norah Jones', 'Olivia Rodrigo', 'Reneé Rapp', 'Sabrina Carpenter',
        'Sam Smith', 'Selena Gomez', 'Shawn Mendes', 'Skylar Grey', 'Taylor Swift',
        'Tayna', 'Teddy Swims', 'The Kid Laroi', 'Twenty One Pilots',
    ],
    'hiphop': [
        '21 Savage', 'Busta Rhymes', 'Cardi B', 'Central Cee', 'Childish Gambino',
        'DJ Khaled', 'Dave', 'Dinos', 'Drake', 'Eminem', 'Future', 'Gunna',
        'Internet money', 'J. Cole', 'JAY Z', 'Juice Wrld', 'Kanye West',
        'Kendrick Lamar', 'Lil Baby', 'Lil Durk', 'Lil Nas X', 'Lil Tjay',
        'Lil Uzi Vert', 'Megan Thee Stallion', 'Metro Boomin', 'Migos', 'Mustard',
        'Nicki Minaj', 'Offset', 'POLO G', 'Pharrell Williams', 'Playboi Carti',
        'Post Malone', 'Quality Control', 'Roddy Ricch', 'Travis Scott', 'Trippie Redd',
        'Tyler, The Creator', 'Young Thug',
    ],
    'rock': [
        'AC/DC', 'Arctic Monkeys', 'Bob Dylan', 'Bruce Springsteen', 'David Bowie',
        'Eagles', 'Elvis Presley', 'Fall Out Boy', 'Fleetwood Mac', 'Foo Fighters',
        'Green Day', 'Jimi Hendrix', 'Led Zeppelin', 'Linkin Park', 'Metallica',
        'Nirvana', 'Oasis', 'Paramore', 'Pink Floyd', 'Queen',
        'Radiohead', 'Red Hot Chili Peppers', 'The Beatles', 'The Rolling Stones',
    ],
    'electro': [
        'Daft Punk', 'Disclosure', 'DJ Snake', 'Fred again..', 'KAYTRANADA',
        'Kavinsky', 'Paul Kalkbrenner', 'ZEDD', 'Zerb',
    ],
    'dance': [
        'Avicii', 'Black Eyed Peas', 'Calvin Harris', 'David Guetta', 'Deorro',
        'Dimitri Vegas & Like Mike', 'Felix Jaehn', 'John Summit', 'Kygo',
        'Marshmello', 'Martin Garrix', 'NEIKED', 'The Chainsmokers', 'Tiësto', 'Topic',
    ],
    'rnb': [
        'Alicia Keys', 'Amy Winehouse', 'Aretha Franklin', 'Beyoncé', 'Blood Orange',
        'Bruno Mars', 'Chris Brown', 'Craig David', 'Daniel Caesar', 'Frank Ocean',
        'GIVĒON', 'H.E.R.', 'James Brown', 'Janet Jackson', 'Khalid',
        'Lolo Zouai', 'Mariah Carey', 'Mary J. Blige', 'Ne-Yo', 'Normani',
        'Ray Charles', 'Rihanna', 'SZA', 'Sevdaliza', 'Stevie Wonder',
        'The Weeknd', 'Tina Turner', 'USHER', 'Victoria Monét', 'Whitney Houston',
    ],
    'kpop': [
        'BLACKPINK', 'BTS', 'Bigbang', 'EXO', 'ITZY', 'IVE', 'LE SSERAFIM',
        'NCT 127', 'NewJeans', 'Red Velvet', 'SEVENTEEN', 'Stray Kids', 'TWICE', 'aespa',
    ],
    'rap_fr': [
        'Alonzo', 'Bigflo & Oli', 'Booba', 'Damso', 'Dinos', 'Doums',
        'Freeze Corleone', 'Freeman', 'GIMS', 'Guizmo', 'Hamza',
        "Heuss L'enfoiré", 'Hiro', 'IAM', 'JRK 19', 'Jul', 'Jungeli',
        'Kaaris', 'Kalash Criminel', 'Kery James', 'Kheops', 'Kofs',
        "L'Or du Commun", 'La Fouine', 'La Mano 1.9', 'La Rvfleuze',
        'Laylow', 'Lefa', 'Lomepal', 'Maes', 'Naps', 'Nekfeu', 'Ninho',
        'Niska', 'No Limit', 'Oboy', 'Orelsan', 'Oxmo Puccino',
        'PLK', 'PNL', 'RK', 'Rohff', 'SCH', 'Sky', 'Soolking', 'Soprano',
        'Suprême NTM', 'TK', 'Tandem', 'Vald', 'Werenoi', 'Zeg P', 'Zuukou mayzie',
    ],
    'variete_fr': [
        'Alain Souchon', 'Angèle', 'Aya Nakamura', 'Ben Mazué', 'Calogero',
        'Carole Fredericks', 'Catherine Deneuve', 'Céline Dion', 'Christophe Maé',
        'Clara Luciani', 'Claude François', 'Corneille', 'Eddy Mitchell',
        'Eddy de Pretto', 'France Gall', 'Francis Cabrel', 'Garou',
        'Hoshi', 'Ici c\'est Paris', 'Jacques Brel', 'Jean-Jacques Goldman',
        'Jenifer', 'Johnny Hallyday', 'Julien Doré', 'Kendji Girac',
        'Lamomali', 'Lous and The Yakuza', 'Michel Berger', 'Michel Sardou',
        'Patrick Bruel', 'Pomme', 'Serge Gainsbourg', 'Slimane', 'Stromae',
        'Superbus', 'Véronique Sanson', 'Vianney', 'Vitaa', 'Zaho de Sagazan',
        'mademoiselle lou',
    ],
    'latino': [
        'Anuel AA', 'Bad Bunny', 'Bizarrap', 'Carlos Vives', 'Daddy Yankee',
        'Don Omar', 'Enrique Iglesias', 'Feid', 'FloyyMenor', 'J Balvin',
        'Jay Wheeler', 'Jennifer Lopez', 'KAROL G', 'Luis Fonsi', 'Lunay',
        'Maluma', 'Manuel Turizo', 'Myke Towers', 'NATTI NATASHA', 'Nicky Jam',
        'Ozuna', 'Pitbull', 'Quevedo', 'ROSALÍA', 'Rauw Alejandro',
        'Ricky Martin', 'Rvssian', 'Shakira', 'W Sound', 'Yandel',
    ],
    'afrobeats': [
        'AriBeatz', 'Asake', 'Ayra Starr', 'Burna Boy', 'CKay', 'DJ Neptune',
        'Davido', 'Eugy Official', 'Fally Ipupa', 'Fireboy Dml', 'GuiltyBeatz',
        'Genezio', 'Jaden Bojsen', 'Maisak', 'Majeeed', 'Mr Eazi', 'Odeal',
        'Pheelz', 'Rema', 'Ruger', 'Shallipopi', 'Spinall', 'Spellz',
        'Spyro', 'Tems', 'Tiwa Savage', 'WizKid',
    ],
    # jpop, bollywood and disco: no matching artists in current library
}

# Artists intentionally not placed (no matching category):
# Bob Marley & The Wailers (reggae), Luciano Pavarotti (opera),
# League of Legends (soundtrack), GP Explorer (meme), L2B (unclear),
# Theodora (unclear), Corsu - Mezu Mezu (Corsican)


class Command(BaseCommand):
    help = 'Populate all playlists from the artist map defined in this file.'

    def add_arguments(self, parser):
        parser.add_argument('--dry-run', action='store_true',
                            help='Preview without making changes.')

    def handle(self, *args, **options):
        dry_run = options['dry_run']
        if dry_run:
            self.stdout.write(self.style.WARNING('--- DRY RUN ---'))

        total_added = 0
        total_skipped = 0
        total_not_found = 0

        for category, artists in ARTIST_MAP.items():
            try:
                playlist = Playlist.objects.get(category=category)
            except Playlist.DoesNotExist:
                self.stdout.write(self.style.ERROR(f'Playlist "{category}" not found — run reset_playlists first'))
                continue

            existing_track_ids = set(
                PlaylistTrack.objects.filter(playlist=playlist)
                .values_list('track_id', flat=True)
            )
            current_order = (
                PlaylistTrack.objects.filter(playlist=playlist)
                .order_by('-order_in_playlist')
                .values_list('order_in_playlist', flat=True)
                .first() or 0
            )

            to_create = []
            not_found = []

            for artist in artists:
                tracks = list(
                    Track.objects
                    .filter(artist__iexact=artist)
                    .exclude(id__in=existing_track_ids)
                    .filter(has_preview=True)
                )
                # No substring fallback. `artist__icontains` was here and it
                # put nine Linkin Park tracks in Rap Français ('RK' matches
                # "Linkin Park"), three Williamses too ('IAM'), ten tracks by
                # Nirvana (UK) — a 1967 psych band — in Rock, and "Adele & The
                # Chandeliers" in Pop. Short names in ARTIST_MAP make substring
                # matching indefensible; an unmatched name is reported instead.
                if not tracks:
                    not_found.append(artist)
                    continue
                for t in tracks:
                    current_order += 1
                    to_create.append(
                        PlaylistTrack(playlist=playlist, track=t, order_in_playlist=current_order)
                    )
                    existing_track_ids.add(t.id)

            added = len(to_create)
            skipped = sum(
                1 for a in artists
                if Track.objects.filter(artist__iexact=a).exists() and a not in not_found
            ) - added  # rough already-present count
            skipped = max(skipped, 0)

            if not dry_run and to_create:
                PlaylistTrack.objects.bulk_create(to_create)

            total_added += added
            total_not_found += len(not_found)

            status = 'WOULD ADD' if dry_run else 'Added'
            self.stdout.write(
                f'{playlist.name:<25} {status} {added:>4} tracks'
                + (f'  |  not found: {", ".join(not_found)}' if not_found else '')
            )

        self.stdout.write('')
        if dry_run:
            self.stdout.write(self.style.WARNING(
                f'Dry run complete. Would add {total_added} tracks. '
                f'{total_not_found} artist name(s) not matched.'
            ))
        else:
            self.stdout.write(self.style.SUCCESS(
                f'Done. Added {total_added} tracks total. '
                f'{total_not_found} artist name(s) not matched in DB.'
            ))
