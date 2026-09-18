"""Execute the real deploy script with local fake system services/DB executables."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('deploy_support', REPO / 'scripts/deploy_support.py')
support = importlib.util.module_from_spec(spec)
spec.loader.exec_module(support)

FAKE = r'''#!/usr/bin/env python3
import json,os,pathlib,subprocess,sys
name=pathlib.Path(sys.argv[0]).name
args=sys.argv[1:]
log=pathlib.Path(os.environ['TEST_LOG'])
with log.open('a') as f:f.write(json.dumps([name]+args)+'\n')
fail=os.environ.get('TEST_FAIL','')
if name=='sudo':
    os.execvpe(args[1],args[1:],os.environ)
if name=='git':
    if args[:2]==['rev-parse','HEAD']: print('a'*40)
    if args[:2]==['branch','--show-current']: print('main')
    if args and args[0]=='show':
        resource=args[1].split(':',1)[1]
        print((pathlib.Path(os.environ['TEST_ROOT'])/resource).read_text(),end='')
    sys.exit(0)
if name=='pg_dump':
    if fail=='backup':sys.exit(9)
    pathlib.Path(args[args.index('--file')+1]).write_bytes(b'fake archive')
    sys.exit(0)
if name=='pg_restore':sys.exit(9 if fail=='backup-verify' else 0)
if name=='systemctl':
    state_file=pathlib.Path(os.environ['TEST_STATE'])
    state=json.loads(state_file.read_text())
    if args[0]=='show':
        prop=args[args.index('-p')+1];unit=args[-1]
        if prop=='LoadState':print('loaded' if unit in state else 'not-found')
        elif prop=='User':print('root')
        elif prop=='ActiveState':print(state.get(unit,'inactive'))
    elif args[0]=='is-active':
        if fail=='worker-start' and args[-1]=='songspot-search-worker.service':sys.exit(3)
        sys.exit(0 if state.get(args[-1])=='active' else 3)
    elif args[0] in ('start','stop'):
        for unit in args[1:]:state[unit]='active' if args[0]=='start' else 'inactive'
        state_file.write_text(json.dumps(state))
    sys.exit(0)
if name=='python':
    if args and args[0].endswith('deploy_support.py'):
        os.execv(sys.executable,[sys.executable]+args)
    if args[:2]==['-m','pip']:sys.exit(9 if fail=='pip' else 0)
    if args and args[0]=='manage.py':
        if fail==args[1]:sys.exit(9)
        # The deployment must not call providers before activation.
        if args[1]=='search_worker' and os.environ.get('SEARCH_ENRICHMENT_ENABLED')!='False':sys.exit(12)
        sys.exit(0)
sys.exit(0)
'''


class DeploymentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='songspot-deploy-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'repo with spaces'
        self.backend = self.root / 'songspot_backend'
        self.venv = self.backend / '.venv'
        (self.venv / 'bin').mkdir(parents=True)
        (self.root / 'scripts/systemd').mkdir(parents=True)
        for relative in ['scripts/deploy_backend.sh', 'scripts/deploy_support.py',
                         'scripts/systemd/songspot-search-worker.service']:
            shutil.copy2(REPO / relative, self.root / relative)
        self.envfile = self.backend / '.env'
        self.original = '# Keep me\nSOME_SECRET="literal $() # content"\nOTHER_VALUE=unchanged\n'
        self.envfile.write_text(self.original)
        self.envfile.chmod(0o640)
        (self.backend / 'requirements.txt').touch()
        self.bin = Path(self.temp.name) / 'bin'
        self.bin.mkdir()
        for name in ['git', 'systemctl', 'sudo', 'pg_dump', 'pg_restore']:
            target = self.bin / name
            target.write_text(FAKE.replace('#!/usr/bin/env python3', '#!' + sys.executable))
            target.chmod(0o755)
        python = self.venv / 'bin/python'
        python.write_text(FAKE.replace('#!/usr/bin/env python3', '#!' + sys.executable))
        python.chmod(0o755)
        self.log = Path(self.temp.name) / 'events'
        self.log.touch()
        self.state = Path(self.temp.name) / 'services.json'
        self.initial = {
            'songspot.service': 'active',
            'songspot-crawl-artists.timer': 'active',
            'songspot-refresh-catalog.timer': 'inactive',
            'songspot-crawl-artists.service': 'inactive',
            'songspot-refresh-catalog.service': 'inactive',
        }
        self.state.write_text(json.dumps(self.initial))
        self.systemd = Path(self.temp.name) / 'units'
        self.env = {**os.environ, 'PATH': str(self.bin) + os.pathsep + os.environ['PATH'],
                    'DATABASE_URL': 'postgres://test:secret@127.0.0.1:5432/test_deploy',
                    'TEST_LOG': str(self.log), 'TEST_STATE': str(self.state),
                    'TEST_ROOT': str(self.root), 'SYSTEMD_DIR': str(self.systemd),
                    'VERIFY_DELAY_SECONDS': '0', 'JOB_WAIT_SECONDS': '0'}
        for name in ['DEPLOY_SEARCH_ENRICHMENT_ENABLED','PRE_DEPLOY_CMD','POST_DEPLOY_CMD',
                     'VENV_PATH','BACKEND_DIR','DEPLOY_REVISION','DEPLOY_ROOT']:
            self.env.pop(name, None)

    def run_deploy(self, failure='', revision=True, stdin=False):
        invocation = ['bash', '-s', '--', str(self.root)] if stdin else ['bash', str(self.root / 'scripts/deploy_backend.sh'), str(self.root)]
        result = subprocess.run(invocation + (['b'*40] if revision else []),
                                input=(self.root / 'scripts/deploy_backend.sh').read_text() if stdin else None,
                                env={**self.env, 'TEST_FAIL': failure}, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
        self.events = [json.loads(line) for line in self.log.read_text().splitlines()]
        return result

    def index(self, name, *parts):
        return next(i for i,e in enumerate(self.events) if e[0]==name and all(p in e[1:] for p in parts))

    def test_success_order_configuration_and_timer_state(self):
        result = self.run_deploy()
        self.assertEqual(result.returncode, 0, result.stdout)
        stop = self.index('systemctl','stop','songspot.service')
        merge = self.index('git','merge','--ff-only')
        migration = self.index('python','manage.py','migrate')
        backfill = self.index('python','manage.py','search_backfill')
        health = self.index('python','manage.py','search_health')
        start = self.index('systemctl','start','songspot.service')
        self.assertLess(self.index('pg_restore','--list'),stop)
        self.assertLess(stop,merge)
        self.assertLess(merge,migration)
        self.assertLess(migration,backfill)
        self.assertLess(backfill,health)
        self.assertLess(health,start)
        content = self.envfile.read_text()
        self.assertIn(self.original,content)
        self.assertIn('SEARCH_BACKEND=postgres\n',content)
        self.assertIn('SEARCH_INDEX_ENABLED=False\n',content)
        self.assertIn('SEARCH_ENRICHMENT_ENABLED=True\n',content)
        self.assertEqual(self.envfile.stat().st_mode & 0o777,0o640)
        self.assertNotIn('literal $()',result.stdout)
        state = json.loads(self.state.read_text())
        self.assertEqual(state['songspot-crawl-artists.timer'],'active')
        self.assertEqual(state['songspot-refresh-catalog.timer'],'inactive')
        self.assertEqual(state['songspot-search-worker.service'],'active')
        unit = (self.systemd / 'songspot-search-worker.service').read_text()
        self.assertIn('WorkingDirectory='+str(self.backend)+'\n',unit)
        self.assertIn('ExecStart="'+str(self.venv / 'bin/python')+'" manage.py search_worker',unit)

    def test_stdin_invocation_used_by_github_actions(self):
        result=self.run_deploy(stdin=True)
        self.assertEqual(result.returncode,0,result.stdout)

    def test_generated_service_passes_systemd_parser(self):
        analyzer=shutil.which('systemd-analyze')
        if not analyzer:
            self.skipTest('systemd-analyze unavailable')
        result=self.run_deploy()
        self.assertEqual(result.returncode,0,result.stdout)
        verified=subprocess.run([analyzer,'verify','--man=no',str(self.systemd / 'songspot-search-worker.service')],
                                text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        self.assertEqual(verified.returncode,0,verified.stdout)

    def test_backfill_failure_never_starts_application(self):
        result = self.run_deploy('search_backfill')
        self.assertNotEqual(result.returncode,0)
        self.assertFalse(any(e[:2]==['systemctl','start'] for e in self.events))
        self.assertEqual(self.envfile.read_text(),self.original)
        self.assertEqual(json.loads(self.state.read_text())['songspot.service'],'inactive')

    def test_backup_failure_does_not_stop_backend(self):
        for failure in ['backup','backup-verify']:
            with self.subTest(failure=failure):
                self.log.write_text('')
                result = self.run_deploy(failure)
                self.assertNotEqual(result.returncode,0)
                self.assertFalse(any(e[:2]==['systemctl','stop'] for e in self.events))
                self.assertFalse(any(e[:2]==['git','merge'] for e in self.events))

    def test_health_failure_keeps_everything_stopped(self):
        result = self.run_deploy('search_health')
        self.assertNotEqual(result.returncode,0)
        self.assertFalse(any(e[:2]==['systemctl','start'] for e in self.events))

    def test_worker_failure_stops_backend_and_does_not_restore_timers(self):
        result = self.run_deploy('worker-start')
        self.assertNotEqual(result.returncode,0)
        state = json.loads(self.state.read_text())
        self.assertEqual(state['songspot.service'],'inactive')
        self.assertEqual(state['songspot-crawl-artists.timer'],'inactive')

    def test_busy_import_aborts_before_checkout_and_restores_timer(self):
        self.initial['songspot-crawl-artists.service']='activating'
        self.state.write_text(json.dumps(self.initial))
        result=self.run_deploy()
        self.assertNotEqual(result.returncode,0)
        self.assertFalse(any(e[:2]==['git','merge'] for e in self.events))
        state=json.loads(self.state.read_text())
        self.assertEqual(state['songspot.service'],'active')
        self.assertEqual(state['songspot-crawl-artists.timer'],'active')

    def test_repeat_preserves_explicit_disabled_enrichment(self):
        self.envfile.write_text(self.original+'SEARCH_ENRICHMENT_ENABLED=False\n')
        for _ in range(2):
            result=self.run_deploy()
            self.assertEqual(result.returncode,0,result.stdout)
            self.assertEqual(self.envfile.read_text().count('SEARCH_BACKEND='),1)
            self.assertIn('SEARCH_ENRICHMENT_ENABLED=False\n',self.envfile.read_text())

    def test_deployment_lock_blocks_a_second_runner(self):
        import fcntl
        (self.root / '.deploy').mkdir()
        with (self.root / '.deploy/backend.lock').open('w') as lock:
            fcntl.flock(lock,fcntl.LOCK_EX | fcntl.LOCK_NB)
            result=self.run_deploy()
        self.assertNotEqual(result.returncode,0)
        self.assertFalse(any(e[:2]==['systemctl','stop'] for e in self.events))


class SupportTests(unittest.TestCase):
    def test_systemd_paths_escape_specifiers_quotes_and_backslashes(self):
        self.assertEqual(support.systemd_quote('/x %n/"a\\b'), '"/x %%n/\\"a\\\\b"')
        with self.assertRaises(ValueError):support.systemd_quote('/x\nExecStart=bad')

    def test_backup_password_is_only_in_environment(self):
        from unittest.mock import patch
        with patch.dict(os.environ, {'DATABASE_URL':'postgres://usr:p%40ss@localhost:5432/songspot?sslmode=require'}):
            env=support.database_env(Path('/unused'))
        self.assertEqual(env['PGPASSWORD'],'p@ss')
        self.assertEqual(env['PGSSLMODE'],'require')


if __name__=='__main__':
    unittest.main()
