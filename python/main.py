import sys
import os
import platform
import subprocess

current_dir = os.path.dirname(os.path.realpath(__file__))
utils_dir = os.path.join(current_dir, 'utils')

sys.path.append(current_dir)
sys.path.append(utils_dir)

import tortils

tortils.import_or_install('json')
json = tortils.import_or_install('json')

tunnel = {}

def sendToLua(var, value):
    tunnel[var] = value
    json_data = json.dumps(tunnel)
    print(json_data)

if platform.system() == 'Windows':
    tortils.import_or_install('pycaw')
    from ctypes import cast, POINTER
    from comtypes import CLSCTX_ALL
    import pycaw

    def getvolume():
        devices = pycaw.AudioUtilities.GetSpeakers()
        interface = devices.Activate(
            pycaw.IAudioEndpointVolume._iid_, CLSCTX_ALL, None)
        volume = cast(interface, POINTER(pycaw.IAudioEndpointVolume))
        daVolume = round(volume.GetMasterVolumeLevelScalar() * 100)
        sendToLua("Volume", daVolume)

    def setvolume(volume_level):
        devices = pycaw.AudioUtilities.GetSpeakers()
        interface = devices.Activate(
            pycaw.IAudioEndpointVolume._iid_, CLSCTX_ALL, None)
        volume = cast(interface, POINTER(pycaw.IAudioEndpointVolume))
        volume.SetMasterVolumeLevelScalar(float(volume_level) / 100, None)

elif platform.system() == 'Linux':
    def getvolume():
        result = subprocess.run(['pactl', 'get-sink-volume', '@DEFAULT_SINK@'], capture_output=True, text=True)
        volume_line = result.stdout.splitlines()[0]
        volume_percent = int(volume_line.split('/')[1].strip().replace('%', ''))
        sendToLua("Volume", volume_percent)

    def setvolume(volume_level):
        subprocess.run(['pactl', 'set-sink-volume', '@DEFAULT_SINK@', f'{volume_level}%'])

else:
    def getvolume():
        print("getvolume() is not supported on this OS")

    def setvolume(volume_level):
        print("setvolume() is not supported on this OS")

function_name = sys.argv[1]
args = sys.argv[2:]
if function_name in globals() and callable(globals()[function_name]):
    globals()[function_name](*args)
