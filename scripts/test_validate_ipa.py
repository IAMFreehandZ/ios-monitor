import io
import plistlib
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

from validate_ipa import validate


class IPAValidationTests(unittest.TestCase):
    def make_ipa(self, path, platform=2, include_extension=True):
        binary = struct.pack('<IiiIIIII', 0xFEEDFACF, 0x0100000C, 0, 2, 1, 24, 0, 0) + struct.pack('<IIIIII', 0x32, 24, platform, 0, 0, 0)
        base = 'Payload/MonitorDiagnostics.app/'
        app = {'CFBundleIdentifier': 'com.iamfreehandz.iosmonitor.diagnostics', 'CFBundleExecutable': 'MonitorDiagnostics', 'UIBackgroundModes': ['audio', 'location'], 'NSSupportsLiveActivities': True}
        extension = {'CFBundleIdentifier': app['CFBundleIdentifier'] + '.activity', 'CFBundleExecutable': 'MonitorActivity', 'NSExtension': {'NSExtensionPointIdentifier': 'com.apple.widgetkit-extension'}}
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr(base + 'Info.plist', plistlib.dumps(app))
            archive.writestr(base + 'MonitorDiagnostics', binary)
            if include_extension:
                archive.writestr(base + 'PlugIns/MonitorActivity.appex/Info.plist', plistlib.dumps(extension))
                archive.writestr(base + 'PlugIns/MonitorActivity.appex/MonitorActivity', binary)

    def test_device_app_and_extension_are_accepted(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'test.ipa'
            self.make_ipa(path)
            result = validate(path)
            self.assertEqual(result['app_identifier'], 'com.iamfreehandz.iosmonitor.diagnostics')
            self.assertEqual(result['extension_identifier'], 'com.iamfreehandz.iosmonitor.diagnostics.activity')

    def test_arm64_simulator_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'test.ipa'
            self.make_ipa(path, platform=7)
            with self.assertRaises(ValueError):
                validate(path)

    def test_missing_activity_extension_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'test.ipa'
            self.make_ipa(path, include_extension=False)
            with self.assertRaises(ValueError):
                validate(path)


if __name__ == '__main__':
    unittest.main()
