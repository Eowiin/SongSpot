"""
Clear artist artwork that belongs to a different artist.

Walking an artist's catalogue grafted that artist's picture onto every track
payload the walk returned, because album track payloads carry an artist object
with an id and a name but no picture. Payloads credited to *another* entity —
a feature billed as the main artist on an album cut — kept their own
`deezer_artist_id` and took the walked artist's photo with them, and
`sync_artists_from_tracks` then created those artists wearing the wrong face.
One photo reached fifteen artists that way.

The grafting is fixed in `_persist_artist_payloads` and `fetch_and_save_artist`;
this cleans up what it already wrote.

Which row in a group is the real owner is not recorded anywhere, but it is
legible: the artist that was walked went through `upsert_artist`, which fills
`nb_fan` from `/artist/{id}`, while the borrowers were created by
`bulk_create` from a track payload and have no follower count at all. So the
top row by `nb_fan` keeps the picture and the rest are emptied.

A group where nobody has followers has no owner to keep it on, and is emptied
whole. Nothing is guessed from a name here — that is the ambiguity the Artist
entity exists to avoid.

Emptied rows fall back to the placeholder avatar until

    python manage.py backfill_artist_pictures

re-fetches them, which asks Deezer by ID and cannot pick the wrong face.
"""

from django.db import migrations


def clear_borrowed_pictures(apps, schema_editor):
    Artist = apps.get_model('game', 'Artist')

    groups: dict[str, list[tuple[int, int]]] = {}
    rows = (
        Artist.objects
        .exclude(picture_url__isnull=True)
        .exclude(picture_url='')
        .values_list('picture_url', 'deezer_id', 'nb_fan')
        .iterator(chunk_size=2000)
    )
    for picture_url, deezer_id, nb_fan in rows:
        groups.setdefault(picture_url, []).append((deezer_id, nb_fan))

    borrowed: list[int] = []
    for holders in groups.values():
        if len(holders) < 2:
            continue
        # Ties break on the lower id so a rerun clears the same rows.
        owner_id, owner_fans = max(holders, key=lambda h: (h[1], -h[0]))
        keep = owner_id if owner_fans else None
        borrowed.extend(i for i, _ in holders if i != keep)

    for start in range(0, len(borrowed), 500):
        Artist.objects.filter(deezer_id__in=borrowed[start:start + 500]).update(
            picture_url=None,
        )


def noop(apps, schema_editor):
    """Reversing restores nothing: the borrowed URLs were never theirs."""


class Migration(migrations.Migration):

    dependencies = [
        ('game', '0018_drop_playlist_pool_floor'),
    ]

    operations = [
        migrations.RunPython(clear_borrowed_pictures, noop),
    ]
