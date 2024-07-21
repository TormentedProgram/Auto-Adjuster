import importlib
import sys

def install_package(package):
    import subprocess
    try:
        importlib.import_module('pip')
    except ImportError:
        print("Pip installing now")
        subprocess.run([sys.executable, "-m", "ensurepip", "--upgrade"])

    subprocess.run([sys.executable, "-m", "pip", "install", package])
    return True

def import_or_install(package_name):
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

requests = import_or_install('requests')