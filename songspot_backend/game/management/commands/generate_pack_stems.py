import os
import shutil
import subprocess
import tempfile
from pathlib import Path

import requests
from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from django.db.models import Q

from game.models import PackTrack


class Command(BaseCommand):
    help = 'Generate stems with Demucs for pack tracks and store them under MEDIA_ROOT.'

    def add_arguments(self, parser):
        parser.add_argument('--pack-track-id', type=str, help='PackTrack UUID to process')
        parser.add_argument('--pack-id', type=str, help='SongPack UUID to process all tracks')
        parser.add_argument('--all', action='store_true', help='Process all PackTracks')
        parser.add_argument(
            '--missing-only',
            action='store_true',
            help='Process only PackTracks missing any stem URLs',
        )
        parser.add_argument('--source', type=str, help='Local audio file path (only for single track)')
        parser.add_argument('--model', type=str, default='htdemucs', help='Demucs model name (default: htdemucs)')
        parser.add_argument('--overwrite', action='store_true', help='Overwrite existing stem URLs')

    def handle(self, *args, **options):
        pack_track_id = options.get('pack_track_id')
        pack_id = options.get('pack_id')
        process_all = options.get('all')
        missing_only = options.get('missing_only')
        source = options.get('source')
        model = options.get('model')
        overwrite = options.get('overwrite')

        if not pack_track_id and not pack_id and not process_all:
            raise CommandError('Provide --pack-track-id, --pack-id, or --all')
        if source and not pack_track_id:
            raise CommandError('--source can only be used with --pack-track-id')

        if shutil.which('demucs') is None:
            raise CommandError('demucs is not available in PATH')

        if pack_track_id:
            pack_tracks = PackTrack.objects.filter(id=pack_track_id)
        elif pack_id:
            pack_tracks = PackTrack.objects.filter(pack_id=pack_id)
        else:
            pack_tracks = PackTrack.objects.all()

        if missing_only and not overwrite:
            missing_q = (
                Q(vocals_url__isnull=True) | Q(vocals_url='') |
                Q(drums_url__isnull=True) | Q(drums_url='') |
                Q(bass_url__isnull=True) | Q(bass_url='') |
                Q(other_url__isnull=True) | Q(other_url='')
            )
            pack_tracks = pack_tracks.filter(missing_q)

        if not pack_tracks.exists():
            raise CommandError('No PackTrack records found')

        for pack_track in pack_tracks:
            self._process_pack_track(pack_track, source, model, overwrite)

    def _process_pack_track(self, pack_track, source, model, overwrite):
        if not overwrite and all([
            pack_track.vocals_url,
            pack_track.drums_url,
            pack_track.bass_url,
            pack_track.other_url,
        ]):
            self.stdout.write(self.style.WARNING(f'Skipping {pack_track.id}: stems already set'))
            return

        input_path = None
        temp_dir = None
        try:
            if source:
                input_path = Path(source)
                if not input_path.exists():
                    raise CommandError(f'Source file not found: {source}')
            else:
                if not pack_track.track.preview_url:
                    raise CommandError(f'No preview_url for track {pack_track.track_id}')
                temp_dir = tempfile.TemporaryDirectory()
                input_path = Path(temp_dir.name) / f'{pack_track.track_id}.mp3'
                self._download_preview_with_refresh(pack_track, input_path)

            output_dir = Path(settings.MEDIA_ROOT) / 'stems'
            output_dir.mkdir(parents=True, exist_ok=True)

            self.stdout.write(self.style.WARNING(f'Running demucs for {pack_track.track.title}...'))
            subprocess.run(
                ['demucs', '-n', model, '--mp3', '-o', str(output_dir), str(input_path)],
                check=True
            )

            stems_dir = self._find_stems_dir(output_dir, model, input_path.stem)
            if not stems_dir:
                raise CommandError('Could not locate demucs output directory')

            target_dir = output_dir / f'pack_{pack_track.pack_id}' / f'track_{pack_track.track_id}'
            target_dir.mkdir(parents=True, exist_ok=True)

            stem_map = {
                'vocals_url': 'vocals.mp3',
                'drums_url': 'drums.mp3',
                'bass_url': 'bass.mp3',
                'other_url': 'other.mp3',
            }
            updated_fields = []
            for field, filename in stem_map.items():
                source_file = stems_dir / filename
                if not source_file.exists():
                    self.stdout.write(self.style.WARNING(f'Missing stem: {filename}'))
                    continue
                dest_file = target_dir / filename
                shutil.copy2(source_file, dest_file)
                url = f'{settings.MEDIA_URL}stems/pack_{pack_track.pack_id}/track_{pack_track.track_id}/{filename}'
                setattr(pack_track, field, url)
                updated_fields.append(field)

            if updated_fields:
                pack_track.save(update_fields=updated_fields)
                self.stdout.write(self.style.SUCCESS(f'Updated stems for {pack_track.id}'))
        finally:
            if temp_dir:
                temp_dir.cleanup()

    def _download_preview(self, url, dest_path):
        response = requests.get(url, timeout=30)
        response.raise_for_status()
        dest_path.write_bytes(response.content)

    def _download_preview_with_refresh(self, pack_track, dest_path):
        try:
            self._download_preview(pack_track.track.preview_url, dest_path)
            return
        except requests.HTTPError as exc:
            status_code = getattr(exc.response, 'status_code', None)
            if status_code != 403:
                raise

        # Refresh preview URL and retry once on 403 (expired Deezer URL).
        refreshed_url = pack_track.track.get_fresh_preview_url(
            prefer_cached=False,
            force_refresh=True,
        )
        if not refreshed_url:
            raise CommandError(f'Preview URL refresh failed for track {pack_track.track_id}')
        self._download_preview(refreshed_url, dest_path)

    def _find_stems_dir(self, output_dir, model, stem_name):
        candidate = output_dir / model / stem_name
        if candidate.exists():
            return candidate
        # Fallback: search for any dir containing vocals.mp3
        for path in (output_dir / model).rglob('vocals.mp3'):
            return path.parent
        return None
