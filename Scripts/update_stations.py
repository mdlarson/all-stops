#!/usr/bin/env python3
"""Refresh the bundled official MTA station-complex snapshot."""
import json
import pathlib
import sys
import urllib.request

SOURCE = 'https://data.ny.gov/resource/5f5g-n3cz.json?$limit=2000'
ROOT = pathlib.Path(__file__).resolve().parents[1]
BOROUGHS = {'M': 'Manhattan', 'Bk': 'Brooklyn', 'Q': 'Queens', 'Bx': 'Bronx', 'SI': 'Staten Island'}

def transform(rows):
    stations = [dict(id=row['complex_id'], name=row['stop_name'],
                     borough=BOROUGHS[row['borough']], routes=row['daytime_routes'].split(),
                     latitude=float(row['latitude']), longitude=float(row['longitude'])) for row in rows]
    assert len(stations) > 400, 'Unexpectedly incomplete dataset'
    assert len({s['id'] for s in stations}) == len(stations), 'Duplicate complex IDs'
    assert all(s['routes'] and 40 < s['latitude'] < 42 and -75 < s['longitude'] < -72 for s in stations)
    return sorted(stations, key=lambda s: s['id'])

if __name__ == '__main__':
    if len(sys.argv) > 1:
        rows = json.loads(pathlib.Path(sys.argv[1]).read_text())
    else:
        with urllib.request.urlopen(SOURCE) as response:
            rows = json.load(response)
    stations = transform(rows)
    (ROOT / 'AllStops/Resources/stations.json').write_text(json.dumps(stations, indent=2) + '\n')
    print(f'Wrote {len(stations)} station complexes.')
