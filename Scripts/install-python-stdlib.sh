#!/bin/bash
#
# Xcode run-script build phase for the Echo target (see project.yml).
#
# Copies the Python standard library into Echo.app/python and turns every
# binary module (.so) into a signed framework under Echo.app/Frameworks, as
# iOS requires. Uses BeeWare's helper that ships with Python.xcframework.

set -eo pipefail

XCFRAMEWORK="Python/Python.xcframework"

if [ ! -d "$PROJECT_DIR/$XCFRAMEWORK" ]; then
    echo "error: $XCFRAMEWORK is missing. Run Scripts/fetch-python.sh first."
    exit 1
fi

# Unsigned CI builds (CODE_SIGNING_ALLOWED=NO) have no identity; sign the
# module frameworks ad hoc. SideStore re-signs everything on install.
if [ -z "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
    export EXPANDED_CODE_SIGN_IDENTITY="-"
    export EXPANDED_CODE_SIGN_IDENTITY_NAME="ad hoc"
fi

# Used to pick the Info.plist template for the module frameworks.
export PLATFORM_FAMILY_NAME="${PLATFORM_FAMILY_NAME:-iOS}"

source "$PROJECT_DIR/$XCFRAMEWORK/build/utils.sh"
# Same steps as BeeWare's install_python, but drop the parts of the standard
# library Echo never uses (the test suite alone is ~36 MB) before the binary
# modules are turned into frameworks.
install_stdlib "$XCFRAMEWORK"

PYTHON_VER=$(ls -1 "$CODESIGNING_FOLDER_PATH/python/lib" | grep -E "^python3\.[0-9]+$")
STDLIB="$CODESIGNING_FOLDER_PATH/python/lib/$PYTHON_VER"

for UNUSED in test idlelib tkinter turtledemo ensurepip; do
    rm -rf "$STDLIB/$UNUSED"
done
rm -f "$STDLIB"/lib-dynload/_test*.so "$STDLIB"/lib-dynload/xxlimited*.so

echo "Install Python $PYTHON_VER standard library extension modules..."
process_dylibs "$XCFRAMEWORK" "python/lib/$PYTHON_VER/lib-dynload"
