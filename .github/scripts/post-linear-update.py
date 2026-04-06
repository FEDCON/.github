#!/usr/bin/env python3
"""Post a project update to Linear via GraphQL API."""
import urllib.request, json, sys, os

payload = open('/tmp/linear-payload.json', 'rb').read()
api_key = os.environ['LINEAR_API_KEY'].strip()

req = urllib.request.Request(
    'https://api.linear.app/graphql',
    data=payload,
    headers={'Content-Type': 'application/json', 'Authorization': api_key},
    method='POST'
)

try:
    resp = urllib.request.urlopen(req)
    data = json.loads(resp.read())
    if data.get('data', {}).get('projectUpdateCreate', {}).get('success'):
        url = data['data']['projectUpdateCreate']['projectUpdate']['url']
        print(f'Posted Linear project update: {url}')
    else:
        print(f'Linear API error: {json.dumps(data)}', file=sys.stderr)
        sys.exit(1)
except urllib.error.HTTPError as e:
    print(f'HTTP {e.code}: {e.read().decode()}', file=sys.stderr)
    sys.exit(1)
