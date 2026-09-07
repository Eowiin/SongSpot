"""
Move artist artwork off `tracks` and onto `artists`, where it belongs.

`Track.artist_picture_url` averaged 103 characters (measured) and was repeated
on every track by the same artist — one URL stored a few hundred times over.
`Artist.picture_url` has held the same value since the catalogue opened, so
this was pure duplication.

It also fills in the artists those tracks imply: an act can own hundreds of
chart-imported tracks and still have no `artists` row, because chart imports
never went through `upsert_artist`. After this, every artist with a Deezer ID
has a row, and `catalog.sync_artists_from_tracks` keeps it that way.

What this cannot reach: acts whose tracks carry no `deezer_artist_id` at all —
around a quarter of the seeded catalogue. `artists` is keyed on that ID, so
they have nowhere to live, and `_local_artists` keeps a name-only fallback for
them. They stay searchable and playable, just without artwork.

Three steps, in order:

1. give every `deezer_artist_id` in `tracks` an `artists` row if it lacks one;
2. fill in the pictures of rows that have none;
3. drop the column.

`bulk_create` bypasses `Model.save()`, so `norm_name` and `is_junk` — which
that method maintains — are computed here by hand. `norm_name` is what artist
search matches on; leaving it empty would make every backfilled artist
unfindable.
"""

from django.db import migrations


def move_pictures_to_artists(apps, schema_editor):
    from game.services.matching import is_junk_artist, normalize_artist

    Track = apps.get_model('game', 'Track')
    Artist = apps.get_model('game', 'Artist')

    names: dict[int, str] = {}
    pictures: dict[int, str] = {}
    rows = (
        Track.objects
        .filter(deezer_artist_id__isnull=False)
        .values('deezer_artist_id', 'artist', 'artist_picture_url')
        .iterator(chunk_size=2000)
    )
    for row in rows:
        artist_id = row['deezer_artist_id']
        names.setdefault(artist_id, row['artist'])
        if row['artist_picture_url']:
            pictures.setdefault(artist_id, row['artist_picture_url'])

    if not names:
        return

    existing = {
        a.deezer_id: a
        for a in Artist.objects.filter(deezer_id__in=list(names))
    }

    created, updated = [], []
    for artist_id, name in names.items():
        artist = existing.get(artist_id)
        picture = pictures.get(artist_id)
        if artist is None:
            created.append(Artist(
                deezer_id=artist_id,
                name=name,
                norm_name=normalize_artist(name),
                picture_url=picture,
                nb_fan=0,
                is_junk=is_junk_artist(name),
            ))
        elif picture and not artist.picture_url:
            artist.picture_url = picture
            updated.append(artist)

    Artist.objects.bulk_create(created, ignore_conflicts=True, batch_size=500)
    if updated:
        Artist.objects.bulk_update(updated, ['picture_url'], batch_size=500)


def noop(apps, schema_editor):
    """Reversing drops nothing: the artwork survives on `artists`."""


class Migration(migrations.Migration):

    dependencies = [
        ('game', '0015_track_has_preview'),
    ]

    operations = [
        migrations.RunPython(move_pictures_to_artists, noop),
        migrations.RemoveField(model_name='track', name='artist_picture_url'),
    ]
