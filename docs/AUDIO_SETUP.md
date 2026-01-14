# Audio Setup Guide

## Problem: Deezer Preview URL Expiration

Deezer preview URLs expire after approximately **1-2 hours**. This means you need to periodically refresh the preview URLs in your database.

## Solution: Periodic URL Refresh

We've added a management command that fetches fresh preview URLs from Deezer API using the stored `deezer_id`.

### Manual Refresh

To manually refresh all preview URLs:

```bash
source .venv/bin/activate
python blindtest_friends/manage.py refresh_preview_urls
```

To see what would be updated without making changes:

```bash
python blindtest_friends/manage.py refresh_preview_urls --dry-run
```

### Automatic Refresh with Cron

Since URLs expire after ~1-2 hours, you should run the refresh command **every hour**.

#### Setup on macOS/Linux:

1. Open your crontab:
```bash
crontab -e
```

2. Add this line (adjust path to your project):
```cron
0 * * * * cd /Users/ethan/Personal/BlindTest-friends && source .venv/bin/activate && python blindtest_friends/manage.py refresh_preview_urls >> /tmp/deezer_refresh.log 2>&1
```

This runs every hour at :00 minutes.

#### Setup on Production Server:

For production, use your deployment platform's scheduler:

**Heroku:**
```bash
heroku addons:create scheduler:standard
heroku addons:open scheduler
# Then add: python blindtest_friends/manage.py refresh_preview_urls
# Run every hour
```

**AWS (EC2/ECS):**
- Use CloudWatch Events / EventBridge to trigger Lambda or ECS task
- Or add to crontab on EC2 instance

**DigitalOcean:**
- Use cron on your droplet (same as macOS/Linux above)

**Docker/Kubernetes:**
- Use CronJob resource in Kubernetes
- Or add cron to your container

### Monitoring

Check the last run:
```bash
tail -f /tmp/deezer_refresh.log
```

### Important Notes

1. **Deezer Rate Limits**: Deezer API has rate limits. If you have many tracks (>1000), consider:
   - Adding delays between requests
   - Only refreshing tracks used in recent/active rooms

2. **Error Handling**: The command logs all errors and continues with other tracks

3. **Database Backup**: Always backup your database before running commands that modify data

### Troubleshooting

**Issue: "No tracks with Deezer ID found"**
- Run `python manage.py fetch_deezer_tracks --count=50` to fetch new tracks
- Old tracks without `deezer_id` won't be refreshed (this is expected)

**Issue: Audio still not playing**
- Check that the refresh command ran successfully
- Verify the mobile app is getting the new URL from the API
- Check mobile app logs for error messages

**Issue: Too many API requests**
- Reduce refresh frequency to every 2 hours (but URLs may expire between refreshes)
- Consider caching at the API level

### Mobile App Integration

The mobile app automatically receives fresh URLs when it calls:
```
GET /api/game/rooms/<room_id>/daily-game/
```

No changes needed on the mobile side as long as the backend URLs are kept fresh.
