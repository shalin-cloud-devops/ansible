#!/bin/bash

# =====================
# Apache Tomcat Install Script
# =====================

# --- Variables ---
TOMCAT_VERSION=10.1.18  # Confirmed available version
TOMCAT_USER=tomcat
TOMCAT_GROUP=tomcat
TOMCAT_INSTALL_DIR=/opt/tomcat
TOMCAT_TAR="apache-tomcat-${TOMCAT_VERSION}.tar.gz"
TOMCAT_URL="https://archive.apache.org/dist/tomcat/tomcat-10/v${TOMCAT_VERSION}/bin/${TOMCAT_TAR}"

# --- Ensure running as root ---
if [[ $EUID -ne 0 ]]; then
  echo "❌ Please run this script as root (use sudo)."
  exit 1
fi

# --- Fix permission for /tmp download ---
echo "[+] Ensuring /tmp has proper permissions..."
chmod 1777 /tmp

# --- 1. Install Java ---
echo "[+] Installing Java..."
yum install -y java-11-openjdk-devel

# --- 2. Create Tomcat group and user ---
echo "[+] Creating Tomcat user and group..."
if ! getent group $TOMCAT_GROUP >/dev/null; then
  groupadd -r $TOMCAT_GROUP
fi

if ! id -u $TOMCAT_USER >/dev/null 2>&1; then
  useradd -r -g $TOMCAT_GROUP -d $TOMCAT_INSTALL_DIR -s /sbin/nologin $TOMCAT_USER
fi

# --- 3. Download Tomcat ---
echo "[+] Downloading Tomcat ${TOMCAT_VERSION}..."
echo "Download URL: ${TOMCAT_URL}"
if ! curl -L -o "/tmp/${TOMCAT_TAR}" "${TOMCAT_URL}"; then
  echo "❌ Failed to download Tomcat from ${TOMCAT_URL}"
  echo "Please check if the version is available at:"
  echo "https://archive.apache.org/dist/tomcat/tomcat-10/"
  exit 1
fi

# --- 4. Verify Download ---
echo "[+] Verifying download..."
EXPECTED_MIN_SIZE=10000000  # ~10MB
ACTUAL_SIZE=$(stat -c%s "/tmp/${TOMCAT_TAR}" 2>/dev/null || echo 0)

if [ "$ACTUAL_SIZE" -lt "$EXPECTED_MIN_SIZE" ]; then
  echo "❌ Error: Downloaded file is too small (${ACTUAL_SIZE} bytes). Likely an error page."
  echo "First few lines of downloaded file:"
  head -n 5 "/tmp/${TOMCAT_TAR}"
  exit 1
fi

if ! tar -tzf "/tmp/${TOMCAT_TAR}" >/dev/null 2>&1; then
  echo "❌ Error: Downloaded file is not a valid tar.gz archive"
  exit 1
fi

# --- 5. Extract and install ---
echo "[+] Installing Tomcat to ${TOMCAT_INSTALL_DIR}..."
mkdir -p $TOMCAT_INSTALL_DIR
tar -xvzf "/tmp/${TOMCAT_TAR}" -C $TOMCAT_INSTALL_DIR --strip-components=1

# --- 6. Set permissions ---
echo "[+] Setting permissions..."
chown -R $TOMCAT_USER:$TOMCAT_GROUP $TOMCAT_INSTALL_DIR
chmod -R u+x $TOMCAT_INSTALL_DIR/bin/*.sh
chmod -R g+r $TOMCAT_INSTALL_DIR/conf

# --- 7. Create systemd service ---
echo "[+] Creating systemd service..."
JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))

cat <<EOF > /etc/systemd/system/tomcat.service
[Unit]
Description=Apache Tomcat
After=network.target

[Service]
Type=forking

User=${TOMCAT_USER}
Group=${TOMCAT_GROUP}

Environment="JAVA_HOME=${JAVA_HOME}"
Environment="CATALINA_PID=${TOMCAT_INSTALL_DIR}/temp/tomcat.pid"
Environment="CATALINA_HOME=${TOMCAT_INSTALL_DIR}"
Environment="CATALINA_BASE=${TOMCAT_INSTALL_DIR}"

ExecStart=${TOMCAT_INSTALL_DIR}/bin/startup.sh
ExecStop=${TOMCAT_INSTALL_DIR}/bin/shutdown.sh

Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# --- 8. Start and enable service ---
echo "[+] Starting Tomcat service..."
systemctl daemon-reload
systemctl enable tomcat
if ! systemctl start tomcat; then
  echo "❌ Failed to start Tomcat service"
  echo "Check logs with: journalctl -xe"
  exit 1
fi

# --- 9. Confirm ---
echo "[✔] Tomcat ${TOMCAT_VERSION} installed and running."
echo "You can check the status with: systemctl status tomcat"
echo "Tomcat should be accessible at: http://$(hostname -I | awk '{print $1}'):8080"

