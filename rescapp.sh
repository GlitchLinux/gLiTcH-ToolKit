#!/bin/bash

# Final Rescapp Fix Script
# Fixes all remaining QtWebEngine and OpenGL issues

# 1. Install missing dependencies
sudo apt-get update
sudo apt-get install -y \
    python3-pyqt5.qtwebengine \
    python3-pyqt5.qtsvg \
    libqt5webengine5 \
    libqt5webenginecore5 \
    libqt5webenginewidgets5 \
    libgl1-mesa-dri \
    libegl1-mesa \
    libllvm15

# 2. Fix the main Python file imports
sudo sed -i 's/QtWebKitWidgets.QWebView/QtWebEngineWidgets.QWebEngineView/g' /usr/local/share/rescapp/bin/rescapp.py
sudo sed -i 's/from PyQt5 import QtWebKitWidgets/from PyQt5 import QtWebEngineWidgets/g' /usr/local/share/rescapp/bin/rescapp.py

# 3. Add missing import at the top of the file
if ! grep -q "QtWebEngineWidgets" /usr/local/share/rescapp/bin/rescapp.py; then
    sudo sed -i '/from PyQt5 import/ s/$/, QtWebEngineWidgets/' /usr/local/share/rescapp/bin/rescapp.py
fi

# 4. Update the wrapper script
sudo tee /usr/local/bin/rescapp >/dev/null <<'EOL'
#!/bin/bash
# Rescapp wrapper with proper environment

# Set OpenGL fallback
export LIBGL_ALWAYS_SOFTWARE=1
export QT_XCB_GL_INTEGRATION=xcb_egl

# Set Python path and run
PYTHONPATH="/usr/local/share/rescapp/lib" \
/usr/bin/python3 /usr/local/share/rescapp/bin/rescapp.py "$@"
EOL

# 5. Fix permissions
sudo chmod +x /usr/local/bin/rescapp
sudo chmod +x /usr/local/share/rescapp/bin/rescapp.py

# 6. Create required symlinks
sudo mkdir -p /usr/local/share/rescapp/share/rescapp
sudo ln -sf /usr/local/share/rescapp/menus /usr/local/share/rescapp/share/rescapp/menus

echo "All fixes applied. Try running 'rescapp' now."

# After running this script, verify the imports:
# grep -A5 "from PyQt5 import" /usr/local/share/rescapp/bin/rescapp.py

# Check the QWebEngineView replacement:
# grep "QWebEngineView" /usr/local/share/rescapp/bin/rescapp.py

# then run
# rescapp
