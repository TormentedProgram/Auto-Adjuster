# type: ignore
import sys
import os

current_dir = os.path.dirname(os.path.realpath(__file__))
utils_dir = os.path.join(current_dir, 'utils')

sys.path.append(current_dir)
sys.path.append(utils_dir)

import utils

scriptnamewithext = os.path.basename(__file__)
scriptnamewithoutext = os.path.splitext(scriptnamewithext)[0]

utils.impkg('setuptools')
guessit = utils.impkg('guessit')
json = utils.impkg('json')

tunnel = {}
def sendToLua(var, value):
    tunnel[var] = value
    json_data = json.dumps(tunnel)
    print(json_data)

def guessIt(title):
    anime_table = guessit.guessit(title)

    if "title" in anime_table:
        if "season" in anime_table:
            anime_table["title"] = anime_table["title"] + " " + str(anime_table["season"])
        if "part" in anime_table:
            anime_table["title"] = anime_table["title"] + " " + str(anime_table["part"])

    animetitle = {}
    animetitle["title"] = anime_table["title"]

    sendToLua("myGuess", animetitle)

function_name = sys.argv[1]
args = sys.argv[2:]
if function_name in globals() and callable(globals()[function_name]):
    globals()[function_name](*args)