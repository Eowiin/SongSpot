"""
Fold `latin` and `reggaeton` into one `latino` category, and spend the freed
slot on `disco`.

The two Latin categories were never really two. Deezer's own Latin editor does
not separate latin pop from reggaeton — "Latin Classics", "Latin Love" and
"10s Latin Music" are all half Bad Bunny — so the pools converged on their own:
34 shared tracks, and Bad Bunny was the most represented artist in *Latin Pop*
with 24 entries against Enrique Iglesias' 9.

The reggaeton row survives the merge rather than the latin one. It is the
larger pool, and duels already point at it.
"""
from django.db import migrations, models


def merge_latino_add_disco(apps, schema_editor):
    Playlist = apps.get_model('game', 'Playlist')
    PlaylistTrack = apps.get_model('game', 'PlaylistTrack')
    DuelMatch = apps.get_model('game', 'DuelMatch')

    survivor = Playlist.objects.filter(category='reggaeton').first()
    absorbed = list(Playlist.objects.filter(category='latin'))

    if survivor is None:
        survivor = absorbed.pop(0) if absorbed else Playlist.objects.create(
            name='Latino', category='latino',
        )

    for old in absorbed:
        # unique_together (playlist, track) — skip what the survivor already
        # holds rather than letting bulk moves collide.
        held = set(
            PlaylistTrack.objects.filter(playlist=survivor)
            .values_list('track_id', flat=True)
        )
        offset = PlaylistTrack.objects.filter(playlist=survivor).count()
        moving = PlaylistTrack.objects.filter(playlist=old).exclude(track_id__in=held)
        for index, row in enumerate(moving):
            row.playlist = survivor
            row.order_in_playlist = offset + index
            row.save(update_fields=['playlist', 'order_in_playlist'])

        # The FK is SET_NULL, so a plain delete would quietly orphan the
        # history of every duel played on the old category.
        DuelMatch.objects.filter(playlist=old).update(playlist=survivor)
        old.delete()

    survivor.name = 'Latino'
    survivor.category = 'latino'
    # Sources changed; force the next --stale-only run to rebuild rather than
    # skip it as fresh.
    survivor.deezer_genre_id = None
    survivor.refreshed_at = None
    survivor.save()

    Playlist.objects.get_or_create(
        category='disco', defaults={'name': 'Disco / Funk / Soul'},
    )

    # Every category whose SOURCES entry changed in this release. Leaving
    # refreshed_at set would have --stale-only skip them for a full TTL and
    # keep serving the old pool.
    Playlist.objects.filter(category__in=['hiphop', 'electro', 'pop']).update(
        refreshed_at=None,
    )


def unmerge(apps, schema_editor):
    """
    Split the row back into two empty categories.

    The original latin/reggaeton partition is not recoverable — nothing
    recorded which side a given PlaylistTrack came from — so this restores the
    shape, not the contents. `refresh_catalog --replace` refills both.
    """
    Playlist = apps.get_model('game', 'Playlist')
    Playlist.objects.filter(category='disco').delete()
    survivor = Playlist.objects.filter(category='latino').first()
    if survivor is not None:
        survivor.name = 'Reggaeton / Urbano'
        survivor.category = 'reggaeton'
        survivor.refreshed_at = None
        survivor.save()
    Playlist.objects.get_or_create(
        category='latin', defaults={'name': 'Latin Pop'},
    )


class Migration(migrations.Migration):

    dependencies = [
        ('game', '0016_artist_pictures_move'),
    ]

    operations = [
        migrations.AlterField(
            model_name='playlist',
            name='category',
            field=models.CharField(
                blank=True,
                choices=[
                    ('pop', 'Pop'), ('hiphop', 'Hip-Hop / Rap'), ('rock', 'Rock'),
                    ('electro', 'Électro'), ('dance', 'Dance'), ('rnb', 'R&B'),
                    ('kpop', 'K-pop'), ('rap_fr', 'Rap Français'),
                    ('variete_fr', 'Variété Française'), ('latino', 'Latino'),
                    ('afrobeats', 'Afrobeats'), ('jpop', 'J-pop'),
                    ('bollywood', 'Bollywood'), ('disco', 'Disco / Funk / Soul'),
                ],
                max_length=20, null=True,
            ),
        ),
        migrations.RunPython(merge_latino_add_disco, unmerge),
    ]
