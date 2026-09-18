"""Atomic rolling window in durable PostgreSQL, fail closed on coordination loss."""
from django.db import connection, transaction, DatabaseError
from ..models import DeezerBudget

# Reserved headroom: background cannot consume interactive/preview slots.
CAPACITY = {'preview': 40, 'search': 34, 'background': 24}
WINDOW = 5.0


def admit(calls, now, priority):
    active = [t for t in calls if t > now-WINDOW]
    return active+[now] if len(active) < CAPACITY[priority] else None


def reserve(priority='search'):
    if connection.vendor != 'postgresql':
        return False
    try:
        with transaction.atomic():
            with connection.cursor() as cursor:
                cursor.execute("SELECT current_setting('lock_timeout'), current_setting('statement_timeout')")
                previous_timeouts = cursor.fetchone()
                cursor.execute("SET LOCAL lock_timeout = '100ms'")
                cursor.execute("SET LOCAL statement_timeout = '100ms'")
            DeezerBudget.objects.get_or_create(pk=1)
            row = DeezerBudget.objects.select_for_update().get(pk=1)
            with connection.cursor() as cursor:
                cursor.execute('SELECT extract(epoch from clock_timestamp())')
                now = float(cursor.fetchone()[0])
            calls = admit(row.calls, now, priority)
            if calls is not None:
                row.calls = calls
                row.save(update_fields=['calls'])
            # A caller may own the outer transaction: do not leave its later
            # statements subject to the quota reservation's short deadline.
            with connection.cursor() as cursor:
                cursor.execute(
                    "SELECT set_config('lock_timeout', %s, true), "
                    "set_config('statement_timeout', %s, true)",
                    previous_timeouts,
                )
            return calls is not None
    except DatabaseError:
        return False
