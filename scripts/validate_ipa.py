import hashlib
import json
import plistlib
import struct
import sys
import zipfile
from pathlib import Path


def device_executable(data):
    if len(data) < 32:
        raise ValueError('Truncated executable')
    magic, cpu = struct.unpack_from('<II', data)
    if magic != 0xFEEDFACF or cpu != 0x0100000C:
        raise ValueError('Expected an arm64 Mach-O executable')
    command_count = struct.unpack_from('<I', data, 16)[0]
    offset = 32
    platform = None
    for _ in range(command_count):
        if offset + 8 > len(data):
            raise ValueError('Truncated load command')
        command, size = struct.unpack_from('<II', data, offset)
        if size < 8 or offset + size > len(data):
            raise ValueError('Invalid load command length')
        if command == 0x32 and size >= 24:
            platform = struct.unpack_from('<I', data, offset + 8)[0]
        offset += size
    if platform != 2:
        raise ValueError('Executable is not built for physical iOS devices')


def validate(path):
    with zipfile.ZipFile(path) as archive:
        base = 'Payload/MonitorDiagnostics.app/'
        extension_base = base + 'PlugIns/MonitorActivity.appex/'
        try:
            app = plistlib.loads(archive.read(base + 'Info.plist'))
            extension = plistlib.loads(archive.read(extension_base + 'Info.plist'))
            app_id = app['CFBundleIdentifier']
            extension_id = extension['CFBundleIdentifier']
            if not extension_id.startswith(app_id + '.'):
                raise ValueError('Extension identifier is not a child of the app identifier')
            if not {'audio', 'location'}.issubset(app.get('UIBackgroundModes', [])):
                raise ValueError('Missing background declarations')
            if app.get('NSSupportsLiveActivities') is not True:
                raise ValueError('Missing Live Activity support')
            if extension.get('NSExtension', {}).get('NSExtensionPointIdentifier') != 'com.apple.widgetkit-extension':
                raise ValueError('Missing WidgetKit extension declaration')
            device_executable(archive.read(base + app['CFBundleExecutable']))
            device_executable(archive.read(extension_base + extension['CFBundleExecutable']))
        except (KeyError, plistlib.InvalidFileException) as error:
            raise ValueError('Missing or invalid app/extension files') from error
    return {'app_identifier': app_id, 'extension_identifier': extension_id, 'architecture': 'arm64', 'platform': 'iPhoneOS', 'signing': 'unsigned; sign through SideStore/AltStore and preserve the extension', 'jit_required': False, 'sha256': hashlib.sha256(Path(path).read_bytes()).hexdigest()}


if __name__ == '__main__':
    print(json.dumps(validate(Path(sys.argv[1])), indent=2))
