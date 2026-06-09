FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && apt install -y \
    sudo \
    openssh-server \
    ufw \
    python3 \
    vim \
    nano \
    iproute2 \
    procps \
    cron \
    bc \
    unzip \
    acl \
    file \
    logrotate \
    && rm -rf /var/lib/apt/lists/*

# SSH security configuration
RUN sed -i 's/^#\?Port .*/Port 20022/' /etc/ssh/sshd_config && \
    sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config && \
    grep -q "^Port 20022" /etc/ssh/sshd_config || echo "Port 20022" >> /etc/ssh/sshd_config && \
    grep -q "^PermitRootLogin no" /etc/ssh/sshd_config || echo "PermitRootLogin no" >> /etc/ssh/sshd_config

# Create groups and users
RUN groupadd agent-common && \
    groupadd agent-core && \
    useradd -m -s /bin/bash agent-admin && \
    useradd -m -s /bin/bash agent-dev && \
    useradd -m -s /bin/bash agent-test && \
    usermod -aG agent-common,agent-core agent-admin && \
    usermod -aG agent-common,agent-core agent-dev && \
    usermod -aG agent-common agent-test

# Create directory structure and permissions
RUN mkdir -p /home/agent-admin/agent-app/upload_files && \
    mkdir -p /home/agent-admin/agent-app/api_keys && \
    mkdir -p /home/agent-admin/agent-app/bin && \
    mkdir -p /var/log/agent-app && \
    chown agent-admin:agent-core /home/agent-admin/agent-app && \
    chmod 755 /home/agent-admin/agent-app && \
    chown -R agent-admin:agent-common /home/agent-admin/agent-app/upload_files && \
    chmod 770 /home/agent-admin/agent-app/upload_files && \
    chown -R agent-admin:agent-core /home/agent-admin/agent-app/api_keys && \
    chmod 770 /home/agent-admin/agent-app/api_keys && \
    chown -R agent-dev:agent-core /home/agent-admin/agent-app/bin && \
    chmod 750 /home/agent-admin/agent-app/bin && \
    chown -R agent-admin:agent-core /var/log/agent-app && \
    chmod 770 /var/log/agent-app

# Environment variables for agent-admin
RUN cat >> /home/agent-admin/.bashrc <<'EOF'

# Agent App Environment
export AGENT_HOME=/home/agent-admin/agent-app
export AGENT_PORT=15034
export AGENT_UPLOAD_DIR=$AGENT_HOME/upload_files
export AGENT_KEY_PATH=$AGENT_HOME/api_keys
export AGENT_LOG_DIR=/var/log/agent-app
EOF

# Key file required by provided app binary
RUN echo "agent_api_key_test" > /home/agent-admin/agent-app/api_keys/secret.key && \
    chown agent-admin:agent-core /home/agent-admin/agent-app/api_keys/secret.key && \
    chmod 660 /home/agent-admin/agent-app/api_keys/secret.key

# Copy monitor script and logrotate config
COPY bin/monitor.sh /home/agent-admin/agent-app/bin/monitor.sh
COPY config/agent-app-monitor /etc/logrotate.d/agent-app-monitor

RUN chown agent-dev:agent-core /home/agent-admin/agent-app/bin/monitor.sh && \
    chmod 750 /home/agent-admin/agent-app/bin/monitor.sh && \
    chmod 644 /etc/logrotate.d/agent-app-monitor

# Allow agent-admin to check UFW status without full sudo access
RUN echo 'agent-admin ALL=(root) NOPASSWD: /usr/sbin/ufw status' > /etc/sudoers.d/agent-monitor && \
    chmod 440 /etc/sudoers.d/agent-monitor

# Copy provided app package.
# NOTE: agent-app.zip must exist in the build context, but is intentionally ignored by Git.
COPY agent-app.zip /tmp/agent-app.zip

RUN cd /tmp && \
    unzip agent-app.zip && \
    ARCH="$(uname -m)" && \
    if [ "$ARCH" = "x86_64" ]; then \
        cp /tmp/agent-app-linux-x86 /home/agent-admin/agent-app/agent-app; \
    elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then \
        cp /tmp/agent-app-linux-arm64 /home/agent-admin/agent-app/agent-app; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    chown agent-admin:agent-core /home/agent-admin/agent-app/agent-app && \
    chmod 755 /home/agent-admin/agent-app/agent-app

# Register cron for agent-admin
RUN echo '* * * * * /home/agent-admin/agent-app/bin/monitor.sh >> /tmp/monitor_cron.out 2>&1' | crontab -u agent-admin -

EXPOSE 20022
EXPOSE 15034

CMD service ssh start && \
    ufw --force reset && \
    ufw default deny incoming && \
    ufw default allow outgoing && \
    ufw allow 20022/tcp && \
    ufw allow 15034/tcp && \
    ufw --force enable && \
    service cron start && \
    su - agent-admin -c 'export AGENT_HOME=/home/agent-admin/agent-app; export AGENT_PORT=15034; export AGENT_UPLOAD_DIR=/home/agent-admin/agent-app/upload_files; export AGENT_KEY_PATH=/home/agent-admin/agent-app/api_keys; export AGENT_LOG_DIR=/var/log/agent-app; nohup /home/agent-admin/agent-app/agent-app > /tmp/agent_app.out 2>&1 &' && \
    tail -f /tmp/agent_app.out

