"""Make Godot's non-fatal parse/shader/runtime errors fail CI."""
import pathlib
import sys

log = pathlib.Path(sys.argv[1]).read_text(errors='replace')
bad = [line for line in log.splitlines() if any(x in line for x in [
    'SCRIPT ERROR:', 'SHADER ERROR:', 'ERROR:', 'Parse Error', 'Assertion failed'])]
if bad:
    print('\n'.join(bad))
    raise SystemExit(1)
if len(sys.argv) > 2 and sys.argv[2] not in log:
    raise SystemExit('Missing expected completion marker: '+sys.argv[2])
print('Godot log verified.')
