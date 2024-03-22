import importlib
import os
import sys

sys.dont_write_bytecode = True
key_path = os.path.join(os.getenv('LOCALAPPDATA'), 'mpv', 'keys', 'key.txt')

if os.path.exists(key_path):
    with open(key_path, 'r') as keyfile:
        anilist_id = keyfile.read().strip()

if not anilist_id:
    anilist_id = "your_default_id_here"

def install_package(package):
    import subprocess
    try:
        importlib.import_module('pip')
    except ImportError:
        print("Pip installing now")
        subprocess.run([sys.executable, "-m", "ensurepip", "--upgrade"])

    subprocess.run([sys.executable, "-m", "pip", "install", package])
    return True

def impkg(package_name):
    try:
        package = importlib.import_module(package_name)
    except ImportError:
        print(f"{package_name} is not installed. Installing...")
        if install_package(package_name):  # Wait for install_package to return True
            package = importlib.import_module(package_name)
        else:
            print(f"Failed to install {package_name}.")
            return None  # Return None if installation failed
    return package

requests = impkg('requests')

def anilist_call(query, variables, validate=False):
    url = 'https://graphql.anilist.co'
    if validate:
        response = requests.post(
            url,
            headers = {'Authorization': 'Bearer ' + anilist_id, 'Content-Type': 'application/json', 'Accept': 'application/json'},
            json = {'query': query, 'variables': variables}
        )
    else:
        response = requests.post(
            url,
            json = {'query': query, 'variables': variables}
        )
    return response.json()

def get_id(name):
    variables = {
        "searchStr": name
    }
    query = '''
    query ($searchStr: String) {
        Media(search: $searchStr, type: ANIME) {
            id
        }
    }
    '''
    result = anilist_call(query, variables)
    if "errors" in result:
        return None
    else:
        return result["data"]["Media"]["id"]
    
def update_progress(mediaId, progress):
    variables = {
        "mediaId": mediaId,
        "progress": progress
    }
    query = '''
    mutation ($mediaId: Int, $progress: Int) {
      SaveMediaListEntry (mediaId: $mediaId, progress: $progress) {
          progress
      }
    }
    '''
    anilist_call(query, variables, True)

def get_progress(mediaId):
    variables = {
        "userName": "tormented",
        "mediaId": mediaId
    }
    query = '''
    query ($userName: String, $mediaId: Int) {
      MediaList(userName: $userName, mediaId: $mediaId) {
          progress
      }
    }
    '''
    result = anilist_call(query, variables)
    if result["data"]["MediaList"] == None:
        raise ValueError(f'AniList ID {mediaId} is not on your AniList.')
    return result["data"]["MediaList"]["progress"]
