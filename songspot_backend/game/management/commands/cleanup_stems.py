import os
from datetime import datetime, timedelta, timezone

from django.conf import settings
from django.core.management.base import BaseCommand

from game.models import PackTrack


class Command(BaseCommand):
    help = 'Delete stem files older than a TTL and clear PackTrack URLs.'

    def add_arguments(self, parser):
        parser.add_argument(
            '--max-age-hours',
            type=int,
            default=settings.STEM_TTL_HOURS,
            help='Delete stems older than this many hours',
        )
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='Show what would be deleted without removing files',
        )

    def handle(self, *args, **options):
        max_age_hours = options['max_age_hours']
        dry_run = options['dry_run']
        cutoff = datetime.now(timezone.utc) - timedelta(hours=max_age_hours)

        stems_root = os.path.join(settings.MEDIA_ROOT, 'stems')
        if not os.path.exists(stems_root):
            self.stdout.write(self.style.WARNING('No stems directory found.'))
            return

        cleared = 0
        deleted = 0

        for pack_track in PackTrack.objects.all():
            updated_fields = []
            for field in ['vocals_url', 'drums_url', 'bass_url', 'other_url']:
                url = getattr(pack_track, field)
                path = self._path_from_media_url(url)
                if not path:
                    continue
                if not os.path.exists(path):
                    setattr(pack_track, field, None)
                    updated_fields.append(field)
                    continue
                mtime = datetime.fromtimestamp(os.path.getmtime(path), timezone.utc)
                if mtime <= cutoff:
                    if not dry_run:
                        os.remove(path)
                    deleted += 1
                    setattr(pack_track, field, None)
                    updated_fields.append(field)

            if updated_fields and not dry_run:
                pack_track.save(update_fields=updated_fields)
                cleared += 1

        self.stdout.write(self.style.SUCCESS(
            f'Cleanup complete. Files deleted: {deleted}, PackTracks cleared: {cleared}'
        ))

    def _path_from_media_url(self, url):
        if not url:
            return None
        media_url = settings.MEDIA_URL.rstrip('/') + '/'
        if not url.startswith(media_url):
            return None
        relative = url[len(media_url):].lstrip('/')
        return os.path.join(settings.MEDIA_ROOT, relative)
