# type: ignore
import sys
import os

current_dir = os.path.dirname(os.path.realpath(__file__))
utils_dir = os.path.join(current_dir, 'utils')

sys.path.append(current_dir)
sys.path.append(utils_dir)

import tortils

tortils.import_or_install('pycaw')
pycaw = tortils.import_or_install('pycaw.pycaw')
json = tortils.import_or_install('json')

from ctypes import cast, POINTER
from comtypes import CLSCTX_ALL

tunnel = {}

def sendToLua(var, value):
    tunnel[var] = value
    json_data = json.dumps(tunnel)
    print(json_data)

def getvolume():
    devices = pycaw.AudioUtilities.GetSpeakers()
    interface = devices.Activate(
        pycaw.IAudioEndpointVolume._iid_, CLSCTX_ALL, None)
    volume = cast(interface, POINTER(pycaw.IAudioEndpointVolume))
    daVolume = round(volume.GetMasterVolumeLevelScalar()*100)
    sendToLua("Volume", daVolume)

def setvolume(volume_level):
    devices = pycaw.AudioUtilities.GetSpeakers()
    interface = devices.Activate(
        pycaw.IAudioEndpointVolume._iid_, CLSCTX_ALL, None)
    volume = cast(interface, POINTER(pycaw.IAudioEndpointVolume))
    volume.SetMasterVolumeLevelScalar(float(volume_level) / 100, None)

function_name = sys.argv[1]
args = sys.argv[2:]
if function_name in globals() and callable(globals()[function_name]):
    globals()[function_name](*args)