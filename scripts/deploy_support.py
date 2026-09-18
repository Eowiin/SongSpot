#!/usr/bin/env python3
"""Local helpers used on the VPS only when an authorized deployment is run."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
from urllib.parse import parse_qs, unquote, urlsplit

FLAGS = ('SEARCH_BACKEND', 'SEARCH_INDEX_ENABLED', 'SEARCH_ENRICHMENT_ENABLED')
ASSIGNMENT = re.compile(r'^\s*(?:export\s+)?(' + '|'.join(FLAGS) + r')\s*=')


def database_env(backend):
    url = os.environ.get('DATABASE_URL')
    if not url:
        from dotenv import dotenv_values
        url = dotenv_values(backend / '.env').get('DATABASE_URL')
    parsed = urlsplit(url or '')
    if parsed.scheme not in ('postgres', 'postgresql') or not parsed.path.strip('/'):
        raise ValueError('Deployment requires an explicit PostgreSQL DATABASE_URL')
    env = os.environ.copy()
    for key, value in {
        'PGDATABASE': unquote(parsed.path[1:]), 'PGHOST': parsed.hostname,
        'PGPORT': str(parsed.port or 5432), 'PGUSER': unquote(parsed.username or ''),
        'PGPASSWORD': unquote(parsed.password or ''), 'PGCONNECT_TIMEOUT': '10',
    }.items():
        if value is not None:
            env[key] = value
    for name, values in parse_qs(parsed.query).items():
        if name in ('sslmode', 'sslrootcert', 'sslcert', 'sslkey'):
            env['PG' + name.upper()] = values[-1]
        else:
            raise ValueError('Unsupported database connection option for backup: ' + name)
    return env


def atomic_write(path, content, mode=0o600):
    path = path.resolve()
    previous = path.stat() if path.exists() else None
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix='.' + path.name + '-')
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, stat.S_IMODE(previous.st_mode) if previous else mode)
        if previous and (previous.st_uid, previous.st_gid) != (os.geteuid(), os.getegid()):
            os.chown(temporary, previous.st_uid, previous.st_gid)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def enrichment_value(text, override=None):
    configured = override or None
    if configured is None or configured == '':
        for line in text.splitlines():
            match = ASSIGNMENT.match(line)
            if match and match[1] == 'SEARCH_ENRICHMENT_ENABLED':
                configured = line[match.end():].split('#', 1)[0].strip().strip('\"\'')
    if configured is None:
        # Legacy search already discovered new tracks. Preserve discovery on
        # first installation; preserve an explicit existing False thereafter.
        return 'True'
    if configured.lower() not in ('true', 'false'):
        raise ValueError('SEARCH_ENRICHMENT_ENABLED must be True or False')
    return str(configured.lower() == 'true')


def systemd_quote(value):
    value = str(value)
    if '\n' in value or '\r' in value or '\0' in value:
        raise ValueError('Invalid newline or NUL in systemd path')
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('%', '%%') + '"'


def systemd_directory(value):
    value = str(value)
    systemd_quote(value)  # Common newline/NUL validation.
    if value != value.strip() or value.endswith('\\'):
        raise ValueError('Unsupported trailing whitespace or backslash in working directory')
    # Unlike ExecStart/EnvironmentFile, WorkingDirectory treats quotes literally.
    return value.replace('%', '%%')


def configure(args):
    env_path = args.backend / '.env'
    original = env_path.read_text()
    enabled = enrichment_value(original, args.enrichment)
    flags = {'SEARCH_BACKEND': 'postgres', 'SEARCH_INDEX_ENABLED': 'False',
             'SEARCH_ENRICHMENT_ENABLED': enabled}
    lines = [line for line in original.splitlines(keepends=True) if not ASSIGNMENT.match(line)]
    content = ''.join(lines).rstrip('\n') + '\n' + ''.join(f'{k}={v}\n' for k, v in flags.items())
    runtime = args.root / '.deploy' / 'search.env'
    unit = (args.state / 'worker.template').read_text()
    unit = re.sub(r'^User=.*$', 'User=' + args.service_user, unit, flags=re.M)
    unit = re.sub(r'^WorkingDirectory=.*$', lambda _: 'WorkingDirectory=' + systemd_directory(args.backend), unit, flags=re.M)
    unit = re.sub(r'^EnvironmentFile=.*$', lambda _: 'EnvironmentFile=' + systemd_quote(env_path) + '\nEnvironmentFile=' + systemd_quote(runtime), unit, flags=re.M)
    unit = re.sub(r'^ExecStart=.*$', lambda _: 'ExecStart=' + systemd_quote(args.venv / 'bin/python') + ' manage.py search_worker', unit, flags=re.M)
    worker = args.systemd / 'songspot-search-worker.service'
    dropin = args.systemd / (args.service + '.service.d') / '99-songspot-search.conf'
    for path in (worker, dropin):
        if path.is_symlink():
            raise ValueError('Refusing to replace a symlink or masked systemd unit: ' + str(path))
    files = [(env_path, '.env.before'), (runtime, 'search.env.before'),
             (worker, 'worker.service.before'), (dropin, 'search.conf.before')]
    manifest = []
    for path, backup in files:
        manifest.append({'path': str(path.resolve()), 'backup': backup, 'existed': path.exists()})
        if path.exists():
            shutil.copy2(path, args.state / backup)
    atomic_write(args.state / 'configuration.json', json.dumps(manifest, indent=2)+'\n')
    if content != original:
        atomic_write(env_path, content)
    atomic_write(runtime, ''.join(f'{k}={v}\n' for k, v in flags.items()))
    atomic_write(worker, unit, 0o644)
    atomic_write(dropin, '[Service]\nEnvironmentFile=' + systemd_quote(runtime) + '\n', 0o644)
    print(enabled)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=['preflight', 'backup', 'configure'])
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--backend', type=Path, required=True)
    parser.add_argument('--venv', type=Path, required=True)
    parser.add_argument('--state', type=Path, required=True)
    parser.add_argument('--systemd', type=Path, default=Path('/etc/systemd/system'))
    parser.add_argument('--service', default='songspot')
    parser.add_argument('--service-user', default='root')
    parser.add_argument('--enrichment', default='')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_.@-]+', args.service) or not re.fullmatch(r'[A-Za-z0-9_$-]+', args.service_user):
        parser.error('Invalid service name or user')
    if args.mode == 'preflight':
        systemd_directory(args.backend)
        systemd_quote(args.venv)
        database_env(args.backend)
        enrichment_value((args.backend / '.env').read_text(), args.enrichment)
    elif args.mode == 'backup':
        target = args.state / 'database.dump'
        try:
            subprocess.run(['pg_dump', '--format=custom', '--file', str(target)],
                           env=database_env(args.backend), check=True)
            os.chmod(target, 0o600)
            if not target.stat().st_size:
                raise ValueError('Empty database backup')
            subprocess.run(['pg_restore', '--list', str(target)], check=True, stdout=subprocess.DEVNULL)
        except (ValueError, OSError, subprocess.CalledProcessError):
            target.unlink(missing_ok=True)
            raise
        print('[deploy] PostgreSQL backup archive verified')
    else:
        configure(args)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        # Commands never carry the database password; do not print the URL.
        raise SystemExit(str(exc)) from None
